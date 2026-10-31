import Synchronization
import WorldModule

/// A rule that reads and changes a world: one step of a tick.
///
/// A system's state between runs belongs in the world, as components or resources, so it is
/// copied, compared and replayed along with everything else.
///
/// ```swift
/// struct Movement: System {
///     func run(in world: inout World) {
///         world.update(Position.self, reading: Velocity.self) { position, row in
///             position.x += row.components.dx
///         }
///     }
/// }
/// ```
public protocol System: SystemSet, Sendable {
    /// What the system reads and writes, so ``Schedule/run(on:)`` can run it alongside
    /// systems it does not conflict with; nil, the default, when it may change anything and must
    /// run alone.
    ///
    /// ```swift
    /// struct Movement: System {
    ///     var access: Access? { .reads(Velocity.self).writes(Position.self) }
    ///     func run(in world: inout World) { … }
    /// }
    /// ```
    ///
    /// A system with an access reads and writes only what it lists (relations through their
    /// `Targets`, the hierarchy through `Targets<ChildOf>`), and spawns and despawns not at all.
    var access: Access? { get }

    /// Runs the rule once on `world`.
    func run(in world: inout World)

    /// Prepares `world` for the system, before its first run on it: a schedule calls this
    /// before the wave the system first runs in, outside any concurrent run. Nothing, by default.
    ///
    /// `@System` starts what its parameters record, such as the removals a
    /// ``RemovedComponents`` reads.
    func initialize(in world: inout World)
}

extension System {
    public var access: Access? { nil }

    public func initialize(in world: inout World) {}
}

extension System {
    /// This system, ordered to run after every system of each of `sets` in its schedule: every
    /// system of a system type, or in a ``SystemSet``.
    @inlinable
    public func after<each S: SystemSet>(_ sets: repeat (each S).Type) -> ScheduledSystem {
        ScheduledSystem(self).after(repeat each sets)
    }

    /// This system, ordered to run before every system of each of `sets` in its schedule.
    @inlinable
    public func before<each S: SystemSet>(_ sets: repeat (each S).Type) -> ScheduledSystem {
        ScheduledSystem(self).before(repeat each sets)
    }

    /// This system, in each of `sets`; see ``ScheduledSystem/inSet(_:)``.
    @inlinable
    public func inSet<each S: SystemSet>(_ sets: repeat (each S).Type) -> ScheduledSystem {
        ScheduledSystem(self).inSet(repeat each sets)
    }

    /// This system, free to run in either order with every system of each of `sets`; see
    /// ``ScheduledSystem/ambiguous(with:)``.
    @inlinable
    public func ambiguous<each S: SystemSet>(with sets: repeat (each S).Type) -> ScheduledSystem {
        ScheduledSystem(self).ambiguous(with: repeat each sets)
    }

    /// This system, run only when `condition` holds for the world at the start of its wave.
    ///
    /// ```swift
    /// Movement().runIf { world in !world.resources.contains(Paused.self) }
    /// ```
    @inlinable
    public func runIf(_ condition: @escaping @Sendable (World) -> Bool) -> ScheduledSystem {
        ScheduledSystem(self).runIf(condition)
    }
}

/// A system as a ``Schedule`` holds it: its name, its sets and the sets it must run after or
/// before.
@frozen
public struct ScheduledSystem: Sendable {
    /// The name of the system's type.
    public let name: String
    /// Identifies this system, and copies of it, to the schedules that run it: the key of its
    /// last run in the world.
    @usableFromInline let id: UInt64
    @usableFromInline let type: ObjectIdentifier
    /// The sets the system is in besides its type's.
    @usableFromInline var sets: [ObjectIdentifier] = []
    /// Sets whose systems must run before this one.
    @usableFromInline var predecessors: [ObjectIdentifier] = []
    /// Sets whose systems must run after this one.
    @usableFromInline var successors: [ObjectIdentifier] = []
    /// Sets whose systems this one may run in either order with, though their accesses
    /// conflict: ``Schedule/ambiguities()`` leaves those pairs out.
    @usableFromInline var ambiguousTypes: [ObjectIdentifier] = []
    /// What must hold for the world, every one, for the system to run.
    @usableFromInline var conditions: [@Sendable (World) -> Bool] = []
    @usableFromInline let body: @Sendable (inout World) -> Void
    @usableFromInline let initializer: @Sendable (inout World) -> Void
    /// What the system reads and writes, or nil if it must run alone.
    public let access: Access?

    /// `system`, unordered.
    @inlinable
    public init<S: System>(_ system: S) {
        access = system.access
        name = String(describing: S.self)
        id = nextSystemID.wrappingAdd(1, ordering: .relaxed).newValue
        type = ObjectIdentifier(S.self)
        body = { world in system.run(in: &world) }
        initializer = { world in system.initialize(in: &world) }
    }

    /// The sets the system is in: its type's, then those it joined.
    @inlinable
    var labels: [ObjectIdentifier] { [type] + sets }

    /// This system, also ordered after every system of each of `sets`: every system of a system
    /// type, or in a ``SystemSet``.
    @inlinable
    public func after<each S: SystemSet>(_ sets: repeat (each S).Type) -> ScheduledSystem {
        var system = self
        for set in repeat each sets {
            system.predecessors.append(ObjectIdentifier(set))
        }
        return system
    }

    /// This system, also ordered before every system of each of `sets`.
    @inlinable
    public func before<each S: SystemSet>(_ sets: repeat (each S).Type) -> ScheduledSystem {
        var system = self
        for set in repeat each sets {
            system.successors.append(ObjectIdentifier(set))
        }
        return system
    }

    /// This system, also in each of `sets`, so constraints naming a set order it and
    /// ``ambiguous(with:)`` naming a set covers it.
    @inlinable
    public func inSet<each S: SystemSet>(_ sets: repeat (each S).Type) -> ScheduledSystem {
        var system = self
        for set in repeat each sets {
            system.sets.append(ObjectIdentifier(set))
        }
        return system
    }

    /// This system, also free to run in either order with every system of each of `sets`:
    /// ``Schedule/ambiguities()`` does not report it with them.
    ///
    /// For systems whose conflicting writes commute, such as two that add to one score.
    @inlinable
    public func ambiguous<each S: SystemSet>(with sets: repeat (each S).Type) -> ScheduledSystem {
        var system = self
        for set in repeat each sets {
            system.ambiguousTypes.append(ObjectIdentifier(set))
        }
        return system
    }

    /// This system, also run only when `condition` holds for the world at the start of its wave.
    ///
    /// A system with several conditions runs when all of them hold; they are checked in the
    /// order they were added, stopping at the first that does not.
    @inlinable
    public func runIf(_ condition: @escaping @Sendable (World) -> Bool) -> ScheduledSystem {
        var system = self
        system.conditions.append(condition)
        return system
    }

    /// Whether every condition of the system holds for `world`.
    @inlinable
    public func shouldRun(in world: World) -> Bool {
        conditions.allSatisfy { $0(world) }
    }

    /// Prepares `world` for the system; see ``System/initialize(in:)``.
    @inlinable
    public func initialize(in world: inout World) {
        initializer(&world)
    }

    /// Runs the system once on `world`, whatever its conditions.
    @inlinable
    public func run(in world: inout World) {
        body(&world)
    }
}

/// The source of ``ScheduledSystem`` identifiers.
@usableFromInline
let nextSystemID = Atomic<UInt64>(0)

/// Ends an update for every event type in the world: put it first in the schedule that runs once
/// per frame or step.
///
/// ```swift
/// let frame = Schedule {
///     UpdateEvents()
///     Physics()
///     Damage()
/// }
/// ```
public struct UpdateEvents: System {
    /// The system.
    public init() {}

    public func run(in world: inout World) {
        world.updateEvents()
    }
}
