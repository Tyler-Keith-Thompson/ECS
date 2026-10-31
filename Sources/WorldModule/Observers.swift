/// An event triggered on an entity, which the observers watching it run at once.
///
/// ```swift
/// struct Explode: EntityEvent { var radius: Double }
/// world.observe(Explode.self, on: barrel) { world, trigger in
///     world.despawn(trigger.entity)
/// }
/// world.trigger(Explode(radius: 3), on: barrel)
/// ```
///
/// Unlike an ``Event``, which waits in a queue for systems to read, an entity event runs its
/// observers before ``World/trigger(_:on:)`` returns.
public protocol EntityEvent: Sendable {
    /// Whether the event moves on to the entity's parent (``ChildOf``) after its observers run,
    /// and so on up to the root. False by default; an observer can change it for one trigger.
    static var propagates: Bool { get }
}

extension EntityEvent {
    /// False: the event stops at the entity it was triggered on.
    @inlinable
    public static var propagates: Bool { false }
}

/// What an observer receives: the event, the entity it is being observed on and the entity it
/// was triggered on.
@frozen
public struct Trigger<E: EntityEvent>: Sendable {
    /// The event, which observers may change for the observers after them.
    public var event: E
    /// The entity whose observers are running: the one the event was triggered on, or an
    /// ancestor it propagated to.
    public let entity: Entity
    /// The entity the event was triggered on.
    public let originalEntity: Entity
    /// Whether the event moves on to ``entity``'s parent after its observers run.
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

    /// Runs `observer` whenever an `E` is triggered on any entity, after the observers of that
    /// entity.
    ///
    /// ```swift
    /// world.observe(Explode.self) { world, trigger in
    ///     world.resources[Log.self].append("\(trigger.entity) exploded")
    /// }
    /// ```
    ///
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func observe<E: EntityEvent>(_ type: E.Type, perform observer: @escaping @Sendable (inout World, inout Trigger<E>) -> Void) {
        var observers = observers.global[ObjectIdentifier(E.self)] as? [@Sendable (inout World, inout Trigger<E>) -> Void] ?? []
        observers.append(observer)
        self.observers.global[ObjectIdentifier(E.self)] = observers
    }

    /// Runs `observer` whenever an `E` is triggered on `entity`, or propagates to it, until the
    /// entity is despawned.
    ///
    /// - Complexity: O(1) amortized.
    /// - Precondition: `entity` is live.
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

    /// Triggers `event` on `entity`: runs the observers of `entity`, then those of every entity,
    /// and, while the trigger propagates, the same for each ancestor in turn.
    ///
    /// Observers run before this returns, in the order they were registered, each seeing the
    /// world as the observers before it left it.
    ///
    /// - Complexity: O(*o*·*d*) besides the observers themselves, for *o* observers and *d*
    ///   ancestors visited.
    /// - Precondition: `entity` is live. Use ``trigger(_:checkedOn:)`` to throw instead.
    @inlinable
    public mutating func trigger<E: EntityEvent>(_ event: E, on entity: Entity) {
        precondition(contains(entity), "Triggering on stale entity \(entity)")
        runObservers(event, on: entity)
        endOperation()
    }

    /// Triggers `event` on `entity`; see ``trigger(_:on:)``.
    ///
    /// - Throws: ``StaleEntity`` when `entity` is not live; nothing runs.
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

    /// Runs `hook` whenever an entity starts matching `query`'s structural conditions: by
    /// spawning, inserting, removing or a command.
    ///
    /// The conditions are those a cache of the query keeps (``cache(_:)``): its component terms
    /// and the types its filter requires, excludes or skips by default. Entities that already
    /// match when the hook is registered do not run it. Hooks run as the component
    /// `onAdd(_:perform:)` describes.
    ///
    /// ```swift
    /// world.onAdd(Query(Position.self, Velocity.self).without(Frozen.self)) { world, entity in
    ///     world.resources[Movers.self].count += 1
    /// }
    /// ```
    ///
    /// - Complexity: That of ``cache(_:)`` when no cache of the conditions exists; then O(1)
    ///   amortized.
    @inlinable
    public mutating func onAdd<each T: QueryTerm>(_ query: Query<repeat each T>, perform hook: @escaping @Sendable (inout World, Entity) -> Void) {
        let position = cachePosition(of: query)
        caches[position].onAdd.append(hook)
    }

    /// Runs `hook` whenever an entity stops matching `query`'s structural conditions: by
    /// inserting, removing, despawning or a command; see the query `onAdd(_:perform:)`.
    ///
    /// A despawned entity is no longer live when the hook runs.
    ///
    /// - Complexity: That of ``cache(_:)`` when no cache of the conditions exists; then O(1)
    ///   amortized.
    @inlinable
    public mutating func onRemove<each T: QueryTerm>(_ query: Query<repeat each T>, perform hook: @escaping @Sendable (inout World, Entity) -> Void) {
        let position = cachePosition(of: query)
        caches[position].onRemove.append(hook)
    }
}
