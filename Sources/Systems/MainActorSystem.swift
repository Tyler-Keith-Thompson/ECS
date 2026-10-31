import WorldModule

/// A system whose `run` is isolated to the main actor, for work that touches main-actor state
/// such as a user interface.
///
/// ```swift
/// @MainActor
/// final class ScoreLabel { var text = "" }
///
/// struct ShowScore: MainActorSystem {
///     let label: ScoreLabel
///     var access: Access? { .reads(resources: Score.self) }
///     @MainActor func run(in world: inout World) {
///         label.text = "\(world.resources[Score.self].points)"
///     }
/// }
/// ```
///
/// A schedule runs a main-actor system on the thread that runs the schedule, after the other
/// systems of its wave, never inside a concurrent run; so a schedule holding one runs on the
/// main actor, and running it elsewhere traps. `@System` makes a main-actor system of a type, or
/// a `run`, marked `@MainActor`.
public protocol MainActorSystem: SystemSet, Sendable {
    /// What the system reads and writes; see ``System/access``. A `@MainActor` type declares it
    /// `nonisolated`.
    var access: Access? { get }

    /// Runs the rule once on `world`, on the main actor.
    @MainActor
    func run(in world: inout World)

    /// Prepares `world` for the system; see ``System/initialize(in:)``. A `@MainActor` type
    /// declares it `nonisolated`.
    func initialize(in world: inout World)
}

extension MainActorSystem {
    public var access: Access? { nil }

    public func initialize(in world: inout World) {}
}

extension MainActorSystem {
    /// This system, ordered to run after every system of each of `sets` in its schedule.
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
    @inlinable
    public func runIf(_ condition: @escaping @Sendable (World) -> Bool) -> ScheduledSystem {
        ScheduledSystem(self).runIf(condition)
    }
}
