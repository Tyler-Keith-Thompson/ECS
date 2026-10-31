/// Marks an entity that queries and updates skip, unless they ask for it.
///
/// A disabled entity keeps its components and stays live: reading it directly, by its handle,
/// still works. A query or update reaches it only when it reads or writes `Disabled`, names it in
/// a filter, or allows it:
///
/// ```swift
/// world.insert(Disabled(), into: enemy)
/// world.query(Position.self).count                     // skips enemy
/// world.query(Position.self).allowing(Disabled.self)   // includes it
/// world.remove(Disabled.self, from: enemy)             // enabled again
/// ```
@frozen
public struct Disabled: Component, Hashable {
    @inlinable
    public init() {}
}

extension World {
    /// Makes queries and updates skip entities holding a `C`, as they skip ``Disabled`` ones,
    /// unless they read or write `C`, name it in a filter, or allow it
    /// (``QueryFilter/allowing(_:)-swift.method``). Registering a type twice changes nothing.
    ///
    /// - Complexity: O(*d*) for *d* disabling types.
    @inlinable
    public mutating func registerDisablingComponent<C: Component>(_ type: C.Type) {
        guard !disablingComponents.contains(ObjectIdentifier(C.self)) else { return }
        disablingComponents.append(ObjectIdentifier(C.self))
    }
}
