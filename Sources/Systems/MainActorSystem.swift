import WorldModule

/// A system that runs on the main actor, for work that touches main-actor state such as a user
/// interface.
///
/// Use a main-actor system to carry results out of the world into objects isolated to the main
/// actor: a label showing the score, a view tracking an entity. Conform to the protocol and mark
/// ``run(in:)`` `@MainActor`:
///
/// ```swift
/// @MainActor
/// final class ScoreLabel { var text = "" }
///
/// struct ShowScore: MainActorSystem {
///     let label: ScoreLabel
///     var access: Access? { .reads(resources: Score.self) }
///
///     @MainActor func run(in world: inout World) {
///         label.text = "Score: \(world.resources[Score.self].points)"
///     }
/// }
///
/// let label = ScoreLabel()
/// var world = World()
/// world.resources.insert(Score(points: 3))
/// Schedule { ShowScore(label: label) }.run(on: &world)
/// print(label.text)
/// // Prints "Score: 3"
/// ```
///
/// The ``System()`` macro also makes a main-actor system of a type marked `@MainActor`, or of
/// one whose `run` method is.
///
/// A schedule runs a main-actor system on the thread that runs the schedule, after the other
/// systems of its wave and never at the same time as them.
///
/// - Important: A schedule that holds a main-actor system must run on the main actor; running
///   it elsewhere traps.
public protocol MainActorSystem: SystemSet, Sendable {
    /// The component, resource and event types the system reads and writes, or `nil` if it may
    /// change anything.
    ///
    /// See ``System/access``. A type isolated to the main actor declares this property
    /// `nonisolated`.
    var access: Access? { get }

    /// Runs the system's rule once on a world, on the main actor.
    ///
    /// - Parameter world: The world to read and change.
    @MainActor
    func run(in world: inout World)

    /// Prepares a world for the system before the system first runs on it.
    ///
    /// See ``System/initialize(in:)``. A type isolated to the main actor declares this method
    /// `nonisolated`.
    ///
    /// - Parameter world: The world the system is about to run on.
    func initialize(in world: inout World)
}

extension MainActorSystem {
    public var access: Access? { nil }

    public func initialize(in world: inout World) {}
}

extension MainActorSystem {
    /// Returns this system, ordered to run after every system in each of the given sets.
    ///
    /// See ``System/after(_:)``.
    ///
    /// - Parameter sets: The system types and system sets to run after.
    /// - Returns: A scheduled system with the ordering constraint added.
    @inlinable
    public func after<each S: SystemSet>(_ sets: repeat (each S).Type) -> ScheduledSystem {
        ScheduledSystem(self).after(repeat each sets)
    }

    /// Returns this system, ordered to run before every system in each of the given sets.
    ///
    /// - Parameter sets: The system types and system sets to run before.
    /// - Returns: A scheduled system with the ordering constraint added.
    @inlinable
    public func before<each S: SystemSet>(_ sets: repeat (each S).Type) -> ScheduledSystem {
        ScheduledSystem(self).before(repeat each sets)
    }

    /// Returns this system as a member of each of the given system sets.
    ///
    /// See ``ScheduledSystem/inSet(_:)``.
    ///
    /// - Parameter sets: The system sets to join.
    /// - Returns: A scheduled system in the given sets.
    @inlinable
    public func inSet<each S: SystemSet>(_ sets: repeat (each S).Type) -> ScheduledSystem {
        ScheduledSystem(self).inSet(repeat each sets)
    }

    /// Returns this system, free to run in either order with every system in each of the given
    /// sets.
    ///
    /// See ``ScheduledSystem/ambiguous(with:)``.
    ///
    /// - Parameter sets: The system types and system sets either order is right with.
    /// - Returns: A scheduled system that ``Schedule/ambiguities()`` doesn't report with those
    ///   sets.
    @inlinable
    public func ambiguous<each S: SystemSet>(with sets: repeat (each S).Type) -> ScheduledSystem {
        ScheduledSystem(self).ambiguous(with: repeat each sets)
    }

    /// Returns this system, run only when a condition holds.
    ///
    /// See ``System/runIf(_:)``.
    ///
    /// - Parameter condition: A closure that takes the world and returns whether the system
    ///   runs. It must read only what the system's ``access`` lists.
    /// - Returns: A scheduled system with the condition added.
    @inlinable
    public func runIf(_ condition: @escaping @Sendable (World) -> Bool) -> ScheduledSystem {
        ScheduledSystem(self).runIf(condition)
    }
}
