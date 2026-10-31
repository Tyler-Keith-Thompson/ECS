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
public protocol System: Sendable {
    /// Runs the rule once on `world`.
    func run(in world: inout World)
}

extension System {
    /// This system, ordered to run after every system of each of `types` in its schedule.
    @inlinable
    public func after<each S: System>(_ types: repeat (each S).Type) -> ScheduledSystem {
        ScheduledSystem(self).after(repeat each types)
    }

    /// This system, ordered to run before every system of each of `types` in its schedule.
    @inlinable
    public func before<each S: System>(_ types: repeat (each S).Type) -> ScheduledSystem {
        ScheduledSystem(self).before(repeat each types)
    }
}

/// A system as a ``Schedule`` holds it: its name and the systems it must run after or before.
@frozen
public struct ScheduledSystem: Sendable {
    /// The name of the system's type.
    public let name: String
    /// Identifies this system, and copies of it, to the schedules that run it: the key of its
    /// last run in the world.
    @usableFromInline let id: UInt64
    @usableFromInline let type: ObjectIdentifier
    /// Types whose systems must run before this one.
    @usableFromInline var predecessors: [ObjectIdentifier] = []
    /// Types whose systems must run after this one.
    @usableFromInline var successors: [ObjectIdentifier] = []
    @usableFromInline let body: @Sendable (inout World) -> Void

    /// `system`, unordered.
    @inlinable
    public init<S: System>(_ system: S) {
        name = String(describing: S.self)
        id = nextSystemID.wrappingAdd(1, ordering: .relaxed).newValue
        type = ObjectIdentifier(S.self)
        body = { world in system.run(in: &world) }
    }

    /// This system, also ordered after every system of each of `types`.
    @inlinable
    public func after<each S: System>(_ types: repeat (each S).Type) -> ScheduledSystem {
        var system = self
        for type in repeat each types {
            system.predecessors.append(ObjectIdentifier(type))
        }
        return system
    }

    /// This system, also ordered before every system of each of `types`.
    @inlinable
    public func before<each S: System>(_ types: repeat (each S).Type) -> ScheduledSystem {
        var system = self
        for type in repeat each types {
            system.successors.append(ObjectIdentifier(type))
        }
        return system
    }

    /// Runs the system once on `world`.
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
