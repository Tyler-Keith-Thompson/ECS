import WorldModule

/// Makes a type a system whose access comes from the parameters of its `run` method.
///
/// Attach `@System` to a structure with a method named `run`. The method's parameters are
/// system parameters, values the schedule fetches from the world before each run, and their
/// types state exactly what the system reads and writes. The macro conforms the type to
/// ``System``, writing its ``System/access`` from those types and a ``System/run(in:)`` that
/// fetches the parameters and calls your method.
///
/// The following system moves each entity by its velocity plus whichever of a wind and a
/// current act on it, scaled by the time step:
///
/// ```swift
/// struct Wind: Component { var speed: Double }
/// struct Current: Component { var speed: Double }
///
/// @System
/// struct Drift {
///     func run(
///         _ drifters: Update<Position>.Over<Velocity, AnyOf<Wind, Current>>,
///         _ step: ResourceReader<TimeStep>
///     ) {
///         drifters { position, row in
///             let (velocity, (wind, current)) = row.components
///             let push = (wind?.speed ?? 0) + (current?.speed ?? 0)
///             position.x += (velocity.dx + push) * step.value.seconds
///         }
///     }
/// }
///
/// var world = World()
/// world.resources.insert(TimeStep(seconds: 0.5))
/// let boat = world.spawn(Position(x: 0, y: 0), Velocity(dx: 2, dy: 0), Wind(speed: 4))
/// Schedule { Drift() }.run(on: &world)
/// print(world[Position.self, of: boat].x)
/// // Prints "3.0"
/// ```
///
/// `Drift` writes `Position`, reads `Velocity`, `Wind`, `Current` and the `TimeStep` resource,
/// and nothing else, so a schedule runs it at the same time as any system that doesn't write
/// those types.
///
/// These are the parameter types a `run` method can take:
///
/// - term ``/WorldModule/Query`` and ``/WorldModule/Query/Where``: Reads components.
/// - term ``Update``: Writes components, optionally reading others.
/// - term ``ResourceReader`` and ``ResourceWriter``: Read or write a resource.
/// - term ``EventReader`` and ``EventWriter``: Read or send events.
/// - term ``RemovedComponents``: Lists the entities that lost a component.
/// - term `inout` ``/WorldModule/Commands``: Queues structural changes, which apply at the end of
///   the system's wave and conflict with nothing.
///
/// A `run` method that takes the world instead, as `inout World`, makes a system with no access,
/// which can change anything and so runs alone:
///
/// ```swift
/// @System
/// struct SpawnBall {
///     func run(in world: inout World) {
///         world.spawn(Position(x: 0, y: 100), Velocity(dx: 0, dy: 0))
///     }
/// }
///
/// var world = World()
/// Schedule { SpawnBall() }.run(on: &world)
/// print(world.count)
/// // Prints "1"
/// ```
///
/// Mark the type or its `run` method `@MainActor` to make a ``MainActorSystem`` instead.
///
/// The macro reads only the method's signature. Two parameters whose written types conflict,
/// such as an `Update<Position>` and a `Query<Position>`, are a compile-time error. A conflict the
/// written types hide, such as one type spelled through a type alias, traps when the system is
/// scheduled.
///
/// The code the macro generates refers to `World`, `Access` and `Commands`, so the file must
/// import `ECS`, or both `WorldModule` and `Systems`.
@attached(extension, conformances: System, MainActorSystem, names: named(access), named(run), named(initialize))
public macro System() = #externalMacro(module: "SystemMacros", type: "SystemMacro")
