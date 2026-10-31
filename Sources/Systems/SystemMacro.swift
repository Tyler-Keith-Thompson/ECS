import WorldModule

/// Makes a type a ``System`` from its `run` method.
///
/// A `run` taking the world makes a system that may change anything, so a schedule runs it
/// alone:
///
/// ```swift
/// @System
/// struct LevelLoader {
///     func run(in world: inout World) { … }
/// }
/// ```
///
/// A `run` taking system parameters makes a system whose ``System/access`` comes from the
/// parameters' types, so a schedule runs it alongside every system it does not conflict with:
///
/// ```swift
/// @System
/// struct Movement {
///     func run(
///         _ movers: Update<Position>.Over<Velocity, AnyOf<Wind, Current>>.Where<Without<Frozen>>,
///         _ time: ResourceReader<Time>
///     ) {
///         movers { position, row in
///             let (velocity, (wind, current)) = row.components
///             position.x += (velocity.dx + (wind?.speed ?? 0) + (current?.speed ?? 0)) * time.value.delta
///         }
///     }
/// }
/// ```
///
/// The parameters are ``WorldModule/Query`` (optionally `.Where<…>`), ``Update``,
/// ``ResourceReader``, ``ResourceWriter``, ``EventReader``, ``EventWriter`` and `inout`
/// ``WorldModule/Commands``. The macro reads only the signature, so the access is exact: a
/// parameter reads and writes what its type says. Two parameters that conflict are an error when
/// their written types show it, and a trap when the system is scheduled otherwise.
///
/// The expansion refers to `World`, `Access` and `Commands`, so the file imports `ECS`, or
/// `WorldModule` and `Systems`.
@attached(extension, conformances: System, names: named(access), named(run))
public macro System() = #externalMacro(module: "SystemMacros", type: "SystemMacro")
