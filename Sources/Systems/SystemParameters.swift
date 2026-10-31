import WorldModule

/// A type a system's `run` method can take in place of the whole world, whose type states what
/// the system reads and writes.
///
/// You don't conform to this protocol yourself. The ``System()`` macro builds a system's
/// ``System/access`` from the types of its parameters, and fetches the parameters from the world
/// before each run. The parameter types are:
///
/// - term ``/WorldModule/Query`` and ``/WorldModule/Query/Where``: Read components.
/// - term ``Update``: Writes components, optionally reading others.
/// - term ``ResourceReader`` and ``ResourceWriter``: Read or write a resource.
/// - term ``EventReader`` and ``EventWriter``: Read or send events.
/// - term ``RemovedComponents``: Lists the entities that lost a component.
/// - term `inout` ``/WorldModule/Commands``: Queues structural changes, which apply at the end of
///   the wave the system runs in and conflict with nothing.
public protocol SystemParameter {
    /// The types the parameter reads and writes as a parameter of a system of the given type.
    static func _access<S>(in system: S.Type) -> Access
}

/// The access of a system's parameters, every one, trapping if two conflict.
///
/// - Precondition: No parameter writes a type another reads or writes.
@inlinable
public func _parameterAccess(_ accesses: Access...) -> Access {
    for first in accesses.indices {
        for second in accesses.indices where second > first {
            precondition(!accesses[first].conflicts(with: accesses[second]), "Parameters \(first) and \(second) of a system conflict: one writes what the other reads or writes")
        }
    }
    return accesses.reduce(Access()) { $0.merging($1) }
}

// MARK: Reading components

extension Query: SystemParameter {
    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        var access = Access()
        for type in repeat (each T).self {
            access = type._reading(access)
        }
        return access
    }

    /// The query of this type, bound to `world`'s rows through `query`, which a call site that
    /// knows the terms' types writes as `{ world, query in world.query(query) }` so the rows are
    /// read by the overload for the query's shape.
    @inlinable
    public static func _fetch(
        from world: World, query: (World, Query) -> QueryView<repeat (each T).Value>
    ) -> Query {
        let unbound = Query(filter: QueryFilter())
        return unbound._bound(to: query(world, unbound))
    }

    /// The query of this type, bound to `world`.
    @inlinable
    public static func _fetch(from world: World) -> Query {
        _fetch(from: world) { world, query in world.query(query) }
    }
}

extension Query.Where: SystemParameter {
    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        var access = Query._access(in: system)
        for type in repeat (each F).self {
            access = type._reading(access)
        }
        return access
    }

    /// The query of this type with its filter, bound to `world`'s rows through `query`; see
    /// ``/WorldModule/Query/_fetch(from:query:)``.
    @inlinable
    public static func _fetch(
        from world: World, query: (World, Query) -> QueryView<repeat (each T).Value>
    ) -> Query.Where<repeat each F> {
        let unbound = Query(filter: filter)
        return Query.Where(_bound: unbound._bound(to: query(world, unbound)))
    }

    /// The query of this type with its filter, bound to `world`.
    @inlinable
    public static func _fetch(from world: World) -> Query.Where<repeat each F> {
        _fetch(from: world) { world, query in world.query(query) }
    }
}

// MARK: Resources

/// A system parameter that reads a resource.
///
/// Read the resource through ``value``. The following system slows every velocity by an amount
/// that depends on the time step:
///
/// ```swift
/// @System
/// struct Drag {
///     func run(_ velocities: Update<Velocity>, _ step: ResourceReader<TimeStep>) {
///         velocities { velocity, _ in velocity.dx *= 1 - step.value.seconds }
///     }
/// }
///
/// var world = World()
/// world.resources.insert(TimeStep(seconds: 0.25))
/// let puck = world.spawn(Velocity(dx: 8, dy: 0))
/// Schedule { Drag() }.run(on: &world)
/// print(world[Velocity.self, of: puck].dx)
/// // Prints "6.0"
/// ```
///
/// Systems that only read a resource can run at the same time as one another.
///
/// - Important: The world must hold the resource when the system runs.
@frozen
public struct ResourceReader<R: Resource>: SystemParameter, Sendable {
    /// The resource, as it was when the system started running.
    public let value: R

    @inlinable
    init(value: R) {
        self.value = value
    }

    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        .reads(resources: R.self)
    }

    /// The resource of `world`.
    ///
    /// - Precondition: `world` holds an `R`.
    @inlinable
    public static func _fetch(from world: World) -> ResourceReader {
        ResourceReader(value: world.resources[R.self])
    }
}

/// A system parameter that reads and writes a resource.
///
/// Change the resource through ``value``; the changes are kept in the world when the system
/// finishes. The following system scores a point for each entity at or below the ground:
///
/// ```swift
/// @System
/// struct Scoring {
///     func run(_ positions: Query<Position>, _ score: ResourceWriter<Score>) {
///         for (_, position) in positions where position.y <= 0 {
///             score.value.points += 1
///         }
///     }
/// }
///
/// var world = World()
/// world.resources.insert(Score(points: 0))
/// world.spawn(Position(x: 0, y: 0))
/// world.spawn(Position(x: 5, y: -2))
/// world.spawn(Position(x: 9, y: 40))
/// Schedule { Scoring() }.run(on: &world)
/// print(world.resources[Score.self].points)
/// // Prints "2"
/// ```
///
/// - Important: The world must hold the resource when the system runs.
public final class ResourceWriter<R: Resource>: SystemParameter, @unchecked Sendable {
    @usableFromInline var part: World

    @inlinable
    init(part: World) {
        self.part = part
    }

    /// The resource, which you can change in place.
    ///
    /// - Precondition: The world holds an `R`.
    @inlinable
    public var value: R {
        get { part.resources[R.self] }
        set { part.resources[R.self] = newValue }
        _modify { yield &part.resources[R.self] }
    }

    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        .writes(resources: R.self)
    }

    /// Takes the resource out of `world` until ``_restore(into:)``.
    @inlinable
    public static func _fetch(from world: inout World) -> ResourceWriter {
        ResourceWriter(part: world.split(writing: _access(in: Self.self)))
    }

    /// Puts the resource back into `world`.
    @inlinable
    public func _restore(into world: inout World) {
        world.merge(writing: Self._access(in: Self.self), from: part)
    }
}

// MARK: Events

/// A system parameter that reads the events of one type sent since the system last read them.
///
/// An event reader is a collection of the new events, oldest first. Each system type has its own
/// place in the events, so it sees each event once however many other systems read them too. The
/// following system applies each `Damage` event to the health of its target:
///
/// ```swift
/// @System
/// struct ApplyDamage {
///     func run(_ damages: EventReader<Damage>, _ health: Update<Health>) {
///         health { health, entity in
///             for damage in damages where damage.target == entity {
///                 health.current -= damage.amount
///             }
///         }
///     }
/// }
///
/// var world = World()
/// let knight = world.spawn(Health(current: 30))
/// world.send(Damage(target: knight, amount: 12))
/// Schedule { ApplyDamage() }.run(on: &world)
/// print(world[Health.self, of: knight].current)
/// // Prints "18"
/// ```
///
/// A world keeps an event for the rest of the update it was sent in and all of the next; see
/// ``UpdateEvents``. A system that doesn't run for longer than that misses the events dropped in
/// between.
@frozen
public struct EventReader<E: Event>: SystemParameter, RandomAccessCollection, Sendable {
    /// The new events, oldest first.
    public let events: EventsView<E>

    @inlinable
    init(events: EventsView<E>) {
        self.events = events
    }

    @inlinable
    public var startIndex: Int { events.startIndex }
    @inlinable
    public var endIndex: Int { events.endIndex }
    @inlinable
    public subscript(position: Int) -> E { events[position] }

    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        .readsEvents(E.self, by: S.self)
    }

    /// The events `world` holds that a system of type `system` has not read, marking them read.
    @inlinable
    public static func _fetch<S>(from world: inout World, system: S.Type) -> EventReader {
        EventReader(events: world.readEvents(E.self, by: S.self))
    }
}

/// A system parameter that sends events of one type.
///
/// Call ``send(_:)`` for each event. The following system sends a `Damage` event for each entity
/// that has fallen below the ground:
///
/// ```swift
/// @System
/// struct Combat {
///     func run(_ positions: Query<Position>, _ damages: EventWriter<Damage>) {
///         for (entity, position) in positions where position.y < 0 {
///             damages.send(Damage(target: entity, amount: 10))
///         }
///     }
/// }
///
/// var world = World()
/// world.spawn(Position(x: 0, y: -1))
/// Schedule { Combat() }.run(on: &world)
/// print(world.events(Damage.self).count)
/// // Prints "1"
/// ```
///
/// Readers see an event from the next time they read after it was sent.
public final class EventWriter<E: Event>: SystemParameter, @unchecked Sendable {
    @usableFromInline var part: World

    @inlinable
    init(part: World) {
        self.part = part
    }

    /// Sends an event, which readers see from the next time they read.
    ///
    /// - Parameter event: The event to send.
    @inlinable
    public func send(_ event: E) {
        part.send(event)
    }

    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        .sends(E.self)
    }

    /// Takes the events of type `E` out of `world` until ``_restore(into:)``.
    @inlinable
    public static func _fetch(from world: inout World) -> EventWriter {
        if !world.resources.contains(Events<E>.self) {
            world.resources.insert(Events<E>())
        }
        return EventWriter(part: world.split(writing: _access(in: Self.self)))
    }

    /// Puts the events back into `world`.
    @inlinable
    public func _restore(into world: inout World) {
        world.merge(writing: Self._access(in: Self.self), from: part)
    }
}

// MARK: Removals

/// A system parameter that lists the entities that lost a component since the system last read
/// them.
///
/// The collection holds each entity that lost a `C`, whether the component was removed or the
/// entity despawned, oldest first. The following system scores a point for each entity that
/// thawed:
///
/// ```swift
/// @System
/// struct CountThawed {
///     func run(_ thawed: RemovedComponents<Frozen>, _ score: ResourceWriter<Score>) {
///         score.value.points += thawed.count
///     }
/// }
///
/// var world = World()
/// world.resources.insert(Score(points: 0))
/// let statue = world.spawn(Position(x: 0, y: 0), Frozen())
/// let frame = Schedule { CountThawed() }
/// frame.run(on: &world)
///
/// world.remove(Frozen.self, from: statue)
/// frame.run(on: &world)
/// print(world.resources[Score.self].points)
/// // Prints "1"
/// ```
///
/// The schedule starts recording removals of `C` (``/WorldModule/World/trackRemovals(of:)``)
/// before the system first runs, so removals before then aren't listed. Removals are kept as
/// events are; see ``EventReader``.
@frozen
public struct RemovedComponents<C: Component>: SystemParameter, RandomAccessCollection, Sendable {
    /// The new removals, oldest first.
    public let removals: EventsView<RemovedComponent<C>>

    @inlinable
    init(removals: EventsView<RemovedComponent<C>>) {
        self.removals = removals
    }

    @inlinable
    public var startIndex: Int { removals.startIndex }
    @inlinable
    public var endIndex: Int { removals.endIndex }
    @inlinable
    public subscript(position: Int) -> Entity { removals[position].entity }

    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        .readsEvents(RemovedComponent<C>.self, by: S.self)
    }

    /// Starts recording removals of `C` in `world`.
    @inlinable
    public static func _initialize(in world: inout World) {
        world.trackRemovals(of: C.self)
    }

    /// The removals `world` recorded that a system of type `system` has not read, marking them
    /// read.
    @inlinable
    public static func _fetch<S>(from world: inout World, system: S.Type) -> RemovedComponents {
        RemovedComponents(removals: world.readEvents(RemovedComponent<C>.self, by: S.self))
    }
}

// MARK: Commands

extension Commands: SystemParameter {
    /// Commands read and write nothing while the system runs: they apply after it.
    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        Access()
    }
}
