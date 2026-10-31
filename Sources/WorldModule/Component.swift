/// A type that can be stored as a component of an entity.
///
/// A component is one piece of an entity's state, such as its position, its velocity or its
/// health. Components are plain value types; the behavior that acts on them belongs to the code
/// that queries and updates them. An entity holds at most one component of each type.
///
/// To make a type a component, declare its conformance. There are no requirements to implement:
///
/// ```swift
/// struct Lifetime: Component { var remaining: Double }
///
/// var world = World()
/// let spark = world.spawn(Position(x: 0, y: 0), Lifetime(remaining: 0.5))
///
/// world[Lifetime.self, of: spark].remaining -= 0.25
/// print(world[Lifetime.self, of: spark].remaining)
/// // Prints "0.25"
/// ```
///
/// Every component is a ``Bundle`` of itself, so you can pass one anywhere a bundle is expected,
/// and a ``QueryTerm`` that matches the entities holding it.
///
/// ### Requiring Other Components
///
/// A component can require others. Spawning an entity with the component, or inserting the
/// component into an entity, also inserts each required component the entity doesn't hold, and
/// whatever those components require in turn. List the required components in ``required-u15k``:
///
/// ```swift
/// struct Player: Component {
///     static var required: some Bundle {
///         Position(x: 0, y: 0)
///         Health(current: 100)
///     }
/// }
///
/// var world = World()
/// let player = world.spawn(Player(), Health(current: 50))
///
/// print(world[Position.self, of: player])
/// // Prints "Position(x: 0.0, y: 0.0)"
/// print(world[Health.self, of: player].current)
/// // Prints "50"
/// ```
///
/// A component given explicitly, like the health in the example above, is kept: required
/// components fill in only the types the entity doesn't already hold.
public protocol Component: Bundle, QueryTerm where Body == Never, Value == Self {
    /// The type of the bundle of components that an entity holding this component also holds.
    associatedtype Required: Bundle = TupleBundle< >

    /// The components that an entity holding this component also holds.
    ///
    /// Inserting this component inserts each required component of a type the entity doesn't
    /// hold. Required components are inserted after every component inserted along with this
    /// one, so a component given explicitly is kept. The default is no components.
    @BundleBuilder static var required: Required { get }
}

extension Component where Required == TupleBundle< > {
    /// No components: by default, a component requires no others.
    @inlinable
    public static var required: TupleBundle< > { TupleBundle() }

    @_documentation(visibility: internal)
    @inlinable
    public static var _hasRequirements: Bool { false }
}

/// A type that a world can hold a single value of, outside any entity.
///
/// Use a resource for state that belongs to the whole world rather than to one entity: a clock, a
/// random number generator, the input of the current frame, a score. A world holds at most one
/// resource of each type, in its ``World/resources``:
///
/// ```swift
/// struct Time: Resource { var elapsed: Duration }
///
/// var world = World()
/// world.resources.insert(Time(elapsed: .zero))
/// world.resources[Time.self].elapsed += .milliseconds(16)
///
/// print(world.resources[Time.self].elapsed)
/// // Prints "0.016 seconds"
/// ```
public protocol Resource: Sendable {}
