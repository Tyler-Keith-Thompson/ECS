import Synchronization
import WorldModule

/// A rule that reads and changes a world, run once each time its schedule runs.
///
/// A system is one step of a frame or tick: moving everything with a velocity, applying damage,
/// counting the score. You put systems in a ``Schedule``, which runs each of them once per run,
/// and at the same time as one another where it can.
///
/// Most systems are declared with the ``System()`` macro, which writes the conformance from a
/// `run` method's parameters. Conform to `System` yourself when a system needs the whole world,
/// for example to spawn and despawn entities directly or to reach types chosen at run time. A
/// conforming type implements ``run(in:)`` and, so that it can run alongside other systems,
/// declares an ``access`` listing what it reads and writes:
///
/// ```swift
/// struct Friction: System {
///     var access: Access? { .writes(Velocity.self) }
///
///     func run(in world: inout World) {
///         world.update(Velocity.self) { velocity, _ in
///             velocity.dx *= 0.5
///         }
///     }
/// }
///
/// var world = World()
/// let puck = world.spawn(Velocity(dx: 8, dy: 0))
/// Schedule { Friction() }.run(on: &world)
/// print(world[Velocity.self, of: puck].dx)
/// // Prints "4.0"
/// ```
///
/// A system keeps no state of its own between runs. Anything it needs to remember belongs in the
/// world, as components or resources, so it is copied, compared and restored along with
/// everything else.
///
/// Every system type is also a ``SystemSet`` containing each of its systems, so ordering
/// constraints such as ``after(_:)`` can name it.
public protocol System: SystemSet, Sendable {
    /// The component, resource and event types the system reads and writes, or `nil` if it may
    /// change anything.
    ///
    /// A schedule runs a system alongside the systems whose accesses don't conflict with its
    /// own. A system whose access is `nil`, the default, runs alone.
    ///
    /// Build an access by chaining what the system reads and writes:
    /// `.reads(Velocity.self).writes(Position.self)`. A system with an access must reach only the
    /// types it lists (a relation through its `Targets`, the hierarchy through
    /// `Targets<ChildOf>`), and must not spawn or despawn entities directly; it can queue those
    /// changes as ``/WorldModule/Commands`` instead.
    ///
    /// - Important: In debug builds, a system that reaches a component or resource type its
    ///   access doesn't list traps, whether it runs alone or alongside others. The types that
    ///   entities are skipped for by default, ``/WorldModule/Disabled`` and
    ///   ``/WorldModule/Prefab``, can always be read.
    var access: Access? { get }

    /// Runs the system's rule once on a world.
    ///
    /// - Parameter world: The world to read and change.
    func run(in world: inout World)

    /// Prepares a world for the system before the system first runs on it.
    ///
    /// A schedule calls this method once per world, before the first run of the system on that
    /// world and outside any concurrent run. The default implementation does nothing. Systems
    /// declared with ``System()`` use it to start recording what their parameters read, such as
    /// the removals a ``RemovedComponents`` parameter lists.
    ///
    /// - Parameter world: The world the system is about to run on.
    func initialize(in world: inout World)
}

extension System {
    public var access: Access? { nil }

    public func initialize(in world: inout World) {}
}

extension System {
    /// Returns this system, ordered to run after every system in each of the given sets.
    ///
    /// A set is either a system type, standing for every system of that type in the schedule, or
    /// a ``SystemSet``. Sets with no systems in the schedule are ignored.
    ///
    /// ```swift
    /// let frame = Schedule {
    ///     Movement().after(Gravity.self)
    ///     Gravity()
    /// }
    /// print(frame.names)
    /// // Prints "["Gravity", "Movement"]"
    /// ```
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
    /// The schedule checks the condition against the world at the start of the wave the system
    /// runs in, and skips the system for that run when it returns `false`. The following example
    /// stops movement while the world holds a `Paused` resource:
    ///
    /// ```swift
    /// var world = World()
    /// world.resources.insert(Paused())
    /// let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    ///
    /// let frame = Schedule {
    ///     Movement().runIf { world in !world.resources.contains(Paused.self) }
    /// }
    /// frame.run(on: &world)
    /// print(world[Position.self, of: ball].x)
    /// // Prints "0.0"
    /// ```
    ///
    /// - Parameter condition: A closure that takes the world and returns whether the system
    ///   runs. It must read only what the system's ``access`` lists.
    /// - Returns: A scheduled system with the condition added.
    @inlinable
    public func runIf(_ condition: @escaping @Sendable (World) -> Bool) -> ScheduledSystem {
        ScheduledSystem(self).runIf(condition)
    }
}

/// A system together with the ordering constraints, sets and conditions a schedule runs it with.
///
/// You rarely create a scheduled system yourself. Calling a modifier such as `after(_:)`,
/// `inSet(_:)` or `runIf(_:)` on a system returns one, and further modifiers add to it:
///
/// ```swift
/// let scoring = Scoring()
///     .after(Movement.self)
///     .runIf { world in !world.resources.contains(Paused.self) }
/// print(scoring.name)
/// // Prints "Scoring"
/// ```
///
/// Create one with ``init(_:)-1iqhv`` when you need a system and scheduled systems in one
/// array, such as for ``Schedule/init(checked:)``.
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
    /// The types the system reads and writes, or `nil` if it must run alone.
    public let access: Access?
    /// A Boolean value indicating whether the system is a ``MainActorSystem``.
    public let runsOnMainActor: Bool

    /// Creates a scheduled system with no constraints, sets or conditions.
    ///
    /// - Parameter system: The system to schedule.
    @inlinable
    public init<S: System>(_ system: S) {
        access = system.access
        name = String(describing: S.self)
        id = nextSystemID.wrappingAdd(1, ordering: .relaxed).newValue
        type = ObjectIdentifier(S.self)
        body = { world in system.run(in: &world) }
        initializer = { world in system.initialize(in: &world) }
        runsOnMainActor = false
    }

    /// Creates a scheduled main-actor system with no constraints, sets or conditions.
    ///
    /// - Parameter system: The main-actor system to schedule.
    @inlinable
    public init<S: MainActorSystem>(_ system: S) {
        access = system.access
        name = String(describing: S.self)
        id = nextSystemID.wrappingAdd(1, ordering: .relaxed).newValue
        type = ObjectIdentifier(S.self)
        body = { world in
            MainActor.assumeIsolated {
                system.run(in: &world)
            }
        }
        initializer = { world in system.initialize(in: &world) }
        runsOnMainActor = true
    }

    /// The sets the system is in: its type's, then those it joined.
    @inlinable
    var labels: [ObjectIdentifier] { [type] + sets }

    /// Returns this system, also ordered to run after every system in each of the given sets.
    ///
    /// A set is either a system type, standing for every system of that type in the schedule, or
    /// a ``SystemSet``. Sets with no systems in the schedule are ignored, and a set that holds
    /// this system doesn't order it against itself.
    ///
    /// - Parameter sets: The system types and system sets to run after.
    /// - Returns: This scheduled system with the ordering constraint added.
    @inlinable
    public func after<each S: SystemSet>(_ sets: repeat (each S).Type) -> ScheduledSystem {
        var system = self
        for set in repeat each sets {
            system.predecessors.append(ObjectIdentifier(set))
        }
        return system
    }

    /// Returns this system, also ordered to run before every system in each of the given sets.
    ///
    /// - Parameter sets: The system types and system sets to run before.
    /// - Returns: This scheduled system with the ordering constraint added.
    @inlinable
    public func before<each S: SystemSet>(_ sets: repeat (each S).Type) -> ScheduledSystem {
        var system = self
        for set in repeat each sets {
            system.successors.append(ObjectIdentifier(set))
        }
        return system
    }

    /// Returns this system as a member of each of the given system sets, too.
    ///
    /// A system always belongs to the set of its own type. Joining further sets lets ordering
    /// constraints and ``ambiguous(with:)`` that name those sets apply to it.
    ///
    /// - Parameter sets: The system sets to join.
    /// - Returns: This scheduled system in the given sets.
    @inlinable
    public func inSet<each S: SystemSet>(_ sets: repeat (each S).Type) -> ScheduledSystem {
        var system = self
        for set in repeat each sets {
            system.sets.append(ObjectIdentifier(set))
        }
        return system
    }

    /// Returns this system, also free to run in either order with every system in each of the
    /// given sets.
    ///
    /// Use this method for systems whose accesses conflict but whose changes give the same result
    /// in either order, such as two systems that each add to a score. ``Schedule/ambiguities()``
    /// doesn't report the pair:
    ///
    /// ```swift
    /// let frame = Schedule {
    ///     Scoring()
    ///     CountThawed().ambiguous(with: Scoring.self)
    /// }
    /// print(frame.ambiguities().isEmpty)
    /// // Prints "true"
    /// ```
    ///
    /// The systems still run one after another, in the order written.
    ///
    /// - Parameter sets: The system types and system sets either order is right with.
    /// - Returns: This scheduled system with the sets added.
    @inlinable
    public func ambiguous<each S: SystemSet>(with sets: repeat (each S).Type) -> ScheduledSystem {
        var system = self
        for set in repeat each sets {
            system.ambiguousTypes.append(ObjectIdentifier(set))
        }
        return system
    }

    /// Returns this system, also run only when a condition holds.
    ///
    /// The schedule checks the condition against the world at the start of the wave the system
    /// runs in. A system with several conditions runs when all of them hold; they're checked in
    /// the order they were added, stopping at the first that doesn't.
    ///
    /// - Parameter condition: A closure that takes the world and returns whether the system
    ///   runs. It must read only what the system's ``access`` lists.
    /// - Returns: This scheduled system with the condition added.
    @inlinable
    public func runIf(_ condition: @escaping @Sendable (World) -> Bool) -> ScheduledSystem {
        var system = self
        system.conditions.append(condition)
        return system
    }

    /// Returns a Boolean value indicating whether every condition of the system holds for a
    /// world.
    ///
    /// - Parameter world: The world to check the conditions against.
    /// - Returns: `true` if the system has no conditions or all of them hold; otherwise, `false`.
    @inlinable
    public func shouldRun(in world: World) -> Bool {
        conditions.allSatisfy { $0(world) }
    }

    /// Prepares a world for the system before the system first runs on it.
    ///
    /// See ``System/initialize(in:)``.
    ///
    /// - Parameter world: The world the system is about to run on.
    @inlinable
    public func initialize(in world: inout World) {
        initializer(&world)
    }

    /// Runs the system once on a world, whether or not its conditions hold.
    ///
    /// - Parameter world: The world to read and change.
    /// - Precondition: A main-actor system is run on the main actor.
    @inlinable
    public func run(in world: inout World) {
        body(&world)
    }
}

/// The source of ``ScheduledSystem`` identifiers.
@usableFromInline
let nextSystemID = Atomic<UInt64>(0)

/// A system that ends the current event update, dropping events old enough that every reader
/// has had its chance to read them.
///
/// A world keeps each event for the rest of the update it was sent in and all of the next one,
/// so a reader sees it whichever order the sender and reader run in. Put `UpdateEvents` first in
/// the schedule that runs once per frame or step:
///
/// ```swift
/// var world = World()
/// let knight = world.spawn(Position(x: 0, y: -1), Health(current: 30))
///
/// let frame = Schedule {
///     UpdateEvents()
///     Combat()
///     ApplyDamage().after(Combat.self)
/// }
/// frame.run(on: &world)
/// print(world[Health.self, of: knight].current)
/// // Prints "20"
/// ```
///
/// Running this system calls ``/WorldModule/World/updateEvents()``.
public struct UpdateEvents: System {
    /// Creates the system.
    public init() {}

    public func run(in world: inout World) {
        world.updateEvents()
    }
}
