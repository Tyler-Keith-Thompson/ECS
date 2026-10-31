/// A type that describes something that happens to a particular entity, which its observers
/// respond to at once.
///
/// Use an entity event when one part of a program needs to tell an entity that something
/// happened to it, and other parts need to respond right away: a barrel is hit, a button is
/// clicked. Declare the event as a type that conforms to `EntityEvent`, register observers with
/// ``World/observe(_:on:perform:)`` or ``World/observe(_:perform:)``, and trigger it with
/// ``World/trigger(_:on:)``. The observers run before `trigger(_:on:)` returns.
///
/// The following example despawns a barrel when it explodes:
///
/// ```swift
/// struct Explode: EntityEvent { var radius: Double }
///
/// var world = World()
/// let barrel = world.spawn(Name(value: "Barrel"))
/// world.observe(Explode.self, on: barrel) { world, trigger in
///     world.despawn(trigger.entity)
/// }
///
/// world.trigger(Explode(radius: 3), on: barrel)
/// print(world.contains(barrel))
/// // Prints "false"
/// ```
///
/// An entity event differs from an ``Event``, which waits in a queue until systems read it.
///
/// ### Propagating Up the Hierarchy
///
/// An event whose ``propagates`` property is `true` moves on to the entity's parent
/// (``ChildOf``) after the entity's observers run, then to that entity's parent, and so on up to
/// the root. The following example lets a panel respond to clicks on any of its buttons:
///
/// ```swift
/// struct Clicked: EntityEvent {
///     static var propagates: Bool { true }
/// }
/// struct ClickLog: Resource { var entries: [String] = [] }
///
/// var world = World()
/// world.resources.insert(ClickLog())
/// let panel = world.spawn(Name(value: "Panel"))
/// let button = world.spawn(Name(value: "OK"))
/// try world.addChild(button, to: panel)
///
/// world.observe(Clicked.self, on: panel) { world, trigger in
///     let name = world[Name.self, of: trigger.originalEntity].value
///     world.resources[ClickLog.self].entries.append("Panel saw a click on \(name)")
/// }
///
/// world.trigger(Clicked(), on: button)
/// print(world.resources[ClickLog.self].entries)
/// // Prints "["Panel saw a click on OK"]"
/// ```
///
/// An observer can stop an event from going further by setting the trigger's
/// ``Trigger/propagates`` property to `false`.
public protocol EntityEvent: Sendable {
    /// A Boolean value indicating whether the event moves on to the entity's parent after the
    /// entity's observers run.
    ///
    /// When this is `true`, the event continues up the hierarchy (``ChildOf``) to the root. An
    /// observer can stop one trigger by setting ``Trigger/propagates`` to `false`. The default
    /// implementation returns `false`.
    static var propagates: Bool { get }
}

extension EntityEvent {
    /// A Boolean value indicating whether the event moves on to the entity's parent; by
    /// default, `false`.
    @inlinable
    public static var propagates: Bool { false }
}

/// The event an observer receives, with the entity it's being observed on and the entity it was
/// triggered on.
///
/// Each observer receives the trigger `inout`, so it can change the event for the observers
/// after it, or stop the event from propagating further by setting ``propagates`` to `false`.
@frozen
public struct Trigger<E: EntityEvent>: Sendable {
    /// The event, which an observer can change for the observers after it.
    public var event: E
    /// The entity whose observers are running: the entity the event was triggered on, or an
    /// ancestor it propagated to.
    public let entity: Entity
    /// The entity the event was triggered on.
    public let originalEntity: Entity
    /// A Boolean value indicating whether the event moves on to the parent of ``entity`` after
    /// its observers run.
    public var propagates: Bool

    @inlinable
    init(event: E, entity: Entity, originalEntity: Entity, propagates: Bool) {
        self.event = event
        self.entity = entity
        self.originalEntity = originalEntity
        self.propagates = propagates
    }
}

/// A world's observers of entity events.
@usableFromInline
struct Observers: Sendable {
    /// Each event type's observers of every entity, as `[Observer<E>]`.
    @usableFromInline var global: [ObjectIdentifier: any Sendable] = [:]
    /// Each event type's observers of one entity, as `[Entity: [Observer<E>]]`.
    @usableFromInline var byEntity: [ObjectIdentifier: any Sendable] = [:]
    /// For each event type in `byEntity`, removes an entity's observers from its value.
    @usableFromInline var forgetters: [ObjectIdentifier: @Sendable (inout any Sendable, Entity) -> Void] = [:]

    @usableFromInline
    init() {}

    /// Forgets the observers of `entity`, which is being despawned.
    @usableFromInline
    mutating func forget(_ entity: Entity) {
        for (type, forget) in forgetters {
            guard var observers = byEntity[type] else { continue }
            forget(&observers, entity)
            byEntity[type] = observers
        }
    }
}

extension World {
    // MARK: Observers

    /// Registers a closure to run whenever an event of the given type is triggered on any
    /// entity.
    ///
    /// A global observer runs after the observers of the entity the event reached. If the event
    /// propagates, the observer runs again for each ancestor it reaches.
    ///
    /// The following example counts every explosion in the world:
    ///
    /// ```swift
    /// struct ExplosionCount: Resource { var count = 0 }
    ///
    /// var world = World()
    /// world.resources.insert(ExplosionCount())
    /// world.observe(Explode.self) { world, _ in
    ///     world.resources[ExplosionCount.self].count += 1
    /// }
    ///
    /// let barrel = world.spawn(Name(value: "Barrel"))
    /// let crate = world.spawn(Name(value: "Crate"))
    /// world.trigger(Explode(radius: 3), on: barrel)
    /// world.trigger(Explode(radius: 1), on: crate)
    /// print(world.resources[ExplosionCount.self].count)
    /// // Prints "2"
    /// ```
    ///
    /// - Parameters:
    ///   - type: The event type to observe.
    ///   - observer: The closure to run, given the world and the trigger.
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func observe<E: EntityEvent>(_ type: E.Type, perform observer: @escaping @Sendable (inout World, inout Trigger<E>) -> Void) {
        var observers = observers.global[ObjectIdentifier(E.self)] as? [@Sendable (inout World, inout Trigger<E>) -> Void] ?? []
        observers.append(observer)
        self.observers.global[ObjectIdentifier(E.self)] = observers
    }

    /// Registers a closure to run whenever an event of the given type is triggered on an
    /// entity, or propagates to it.
    ///
    /// The observer stays registered until `entity` is despawned. See ``EntityEvent`` for an
    /// example.
    ///
    /// - Parameters:
    ///   - type: The event type to observe.
    ///   - entity: The entity to observe.
    ///   - observer: The closure to run, given the world and the trigger.
    /// - Precondition: `entity` is live.
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func observe<E: EntityEvent>(_ type: E.Type, on entity: Entity, perform observer: @escaping @Sendable (inout World, inout Trigger<E>) -> Void) {
        precondition(contains(entity), "Observing stale entity \(entity)")
        let key = ObjectIdentifier(E.self)
        var observers = observers.byEntity[key] as? [Entity: [@Sendable (inout World, inout Trigger<E>) -> Void]] ?? [:]
        observers[entity, default: []].append(observer)
        self.observers.byEntity[key] = observers
        if self.observers.forgetters[key] == nil {
            self.observers.forgetters[key] = { observers, entity in
                var typed = observers as! [Entity: [@Sendable (inout World, inout Trigger<E>) -> Void]]
                typed[entity] = nil
                observers = typed
            }
        }
    }

    /// Triggers an event on an entity, running its observers before returning.
    ///
    /// The observers of `entity` run first, then the global observers of `E`. While the trigger
    /// propagates (``EntityEvent/propagates``), the same happens for each ancestor in turn.
    /// Observers run in the order they were registered, each seeing the world as the observers
    /// before it left it. See ``EntityEvent`` for an example.
    ///
    /// - Parameters:
    ///   - event: The event to trigger.
    ///   - entity: The entity to trigger it on.
    /// - Precondition: `entity` is live. The checked spelling, ``trigger(_:checkedOn:)``, throws
    ///   instead.
    /// - Complexity: O(*o* × *d*), not counting the observers' own work, where *o* is the number
    ///   of observers and *d* is the number of ancestors visited.
    @inlinable
    public mutating func trigger<E: EntityEvent>(_ event: E, on entity: Entity) {
        precondition(contains(entity), "Triggering on stale entity \(entity)")
        runObservers(event, on: entity)
        endOperation()
    }

    /// Triggers an event on an entity, throwing if the entity is stale.
    ///
    /// This method behaves like ``trigger(_:on:)``, but reports a stale entity as an error
    /// rather than trapping.
    ///
    /// - Parameters:
    ///   - event: The event to trigger.
    ///   - entity: The entity to trigger it on.
    /// - Throws: ``StaleEntity`` if `entity` isn't live. No observer runs.
    @inlinable
    public mutating func trigger<E: EntityEvent>(_ event: E, checkedOn entity: Entity) throws(StaleEntity) {
        guard contains(entity) else { throw StaleEntity() }
        runObservers(event, on: entity)
        endOperation()
    }

    @usableFromInline
    mutating func runObservers<E: EntityEvent>(_ event: E, on entity: Entity) {
        let key = ObjectIdentifier(E.self)
        var trigger = Trigger(event: event, entity: entity, originalEntity: entity, propagates: E.propagates)
        while true {
            let current = trigger.entity
            if let byEntity = observers.byEntity[key] as? [Entity: [@Sendable (inout World, inout Trigger<E>) -> Void]] {
                for observer in byEntity[current] ?? [] {
                    observer(&self, &trigger)
                }
            }
            if let global = observers.global[key] as? [@Sendable (inout World, inout Trigger<E>) -> Void] {
                for observer in global {
                    observer(&self, &trigger)
                }
            }
            guard trigger.propagates, contains(current), let parent = parent(of: current) else { return }
            trigger = Trigger(event: trigger.event, entity: parent, originalEntity: entity, propagates: true)
        }
    }

    /// Forgets the observers of `entity`, which is being despawned.
    @usableFromInline
    mutating func forgetObservers(of entity: Entity) {
        observers.forget(entity)
    }

    // MARK: Query observers

    /// Registers a closure to run whenever an entity starts matching a query.
    ///
    /// Use this method to respond when an entity gains the combination of components a query
    /// describes, rather than a single component. The hook runs when spawning, inserting,
    /// removing or applying a command makes an entity match. Entities that already match when
    /// you register the hook don't run it. Query hooks run at the same point component hooks do
    /// (see the component `onAdd(_:perform:)`).
    ///
    /// Only the query's structural conditions count: its component terms and the types its
    /// filter requires, excludes or skips by default, the conditions a cache of the query keeps
    /// (``cache(_:)``). The following example counts the entities that start moving:
    ///
    /// ```swift
    /// struct MoverCount: Resource { var count = 0 }
    ///
    /// var world = World()
    /// world.resources.insert(MoverCount())
    /// world.onAdd(Query(Position.self, Velocity.self).without(Frozen.self)) { world, _ in
    ///     world.resources[MoverCount.self].count += 1
    /// }
    ///
    /// let rock = world.spawn(Position(x: 0, y: 0))
    /// world.insert(Velocity(dx: 1, dy: 0), into: rock)
    /// print(world.resources[MoverCount.self].count)
    /// // Prints "1"
    /// ```
    ///
    /// - Parameters:
    ///   - query: The query whose matches to watch.
    ///   - hook: The closure to run, given the world and the entity that started matching.
    /// - Complexity: That of ``cache(_:)`` when the world keeps no cache of the query's
    ///   conditions; otherwise, O(1) amortized.
    @inlinable
    public mutating func onAdd<each T: QueryTerm>(_ query: Query<repeat each T>, perform hook: @escaping @Sendable (inout World, Entity) -> Void) {
        let position = cachePosition(of: query)
        caches[position].onAdd.append(hook)
    }

    /// Registers a closure to run whenever an entity stops matching a query.
    ///
    /// The hook runs when inserting, removing, despawning or applying a command makes an entity
    /// stop matching the query's structural conditions, as the query `onAdd(_:perform:)`
    /// describes. After a despawn, the entity is no longer live when the hook runs.
    ///
    /// The following example counts the movers that are frozen in place:
    ///
    /// ```swift
    /// struct StoppedCount: Resource { var count = 0 }
    ///
    /// var world = World()
    /// world.resources.insert(StoppedCount())
    /// world.onRemove(Query(Position.self, Velocity.self).without(Frozen.self)) { world, _ in
    ///     world.resources[StoppedCount.self].count += 1
    /// }
    ///
    /// let rock = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    /// world.insert(Frozen(), into: rock)
    /// print(world.resources[StoppedCount.self].count)
    /// // Prints "1"
    /// ```
    ///
    /// - Parameters:
    ///   - query: The query whose matches to watch.
    ///   - hook: The closure to run, given the world and the entity that stopped matching.
    /// - Complexity: That of ``cache(_:)`` when the world keeps no cache of the query's
    ///   conditions; otherwise, O(1) amortized.
    @inlinable
    public mutating func onRemove<each T: QueryTerm>(_ query: Query<repeat each T>, perform hook: @escaping @Sendable (inout World, Entity) -> Void) {
        let position = cachePosition(of: query)
        caches[position].onRemove.append(hook)
    }
}
