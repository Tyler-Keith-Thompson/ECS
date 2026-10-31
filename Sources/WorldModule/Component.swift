/// A piece of an entity's state.
///
/// An entity holds at most one component of each type. Components are plain values; behavior
/// belongs to the code that queries and updates them.
///
/// Every component is a ``Bundle`` of itself, and a ``QueryTerm`` matching the entities that hold
/// it.
///
/// ```swift
/// struct Position: Component { var x: Double, y: Double }
/// ```
///
/// A component can require others: spawning or inserting it also inserts each required component
/// the entity does not hold, and what those require in turn.
///
/// ```swift
/// struct Player: Component {
///     static var required: some Bundle {
///         Position(x: 0, y: 0)
///         Health(current: 100)
///     }
/// }
///
/// let player = world.spawn(Player(), Health(current: 50))  // Position(x: 0, y: 0), Health(current: 50)
/// ```
public protocol Component: Bundle, QueryTerm where Body == Never, Value == Self {
    /// The bundle of components an entity holding this one also holds.
    associatedtype Required: Bundle = TupleBundle< >

    /// The components an entity holding this one also holds: inserting this component inserts
    /// each of them the entity does not hold, after every component inserted with it, so a
    /// component given explicitly is kept. None, by default.
    @BundleBuilder static var required: Required { get }
}

extension Component where Required == TupleBundle< > {
    /// No components.
    @inlinable
    public static var required: TupleBundle< > { TupleBundle() }

    @_documentation(visibility: internal)
    @inlinable
    public static var _hasRequirements: Bool { false }
}

/// A value a ``World`` holds once, outside any entity: a clock, a random number generator, the
/// input of the current frame.
///
/// ```swift
/// struct Time: Resource { var elapsed: Duration }
/// ```
public protocol Resource: Sendable {}
