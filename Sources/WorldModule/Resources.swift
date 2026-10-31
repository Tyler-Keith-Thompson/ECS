/// The values a world holds once, outside any entity, keyed by their type.
///
/// ```swift
/// world.resources.insert(Time(elapsed: .zero))
/// world.resources[Time.self].elapsed += .milliseconds(16)
/// ```
@frozen
public struct Resources: Sendable {
    @usableFromInline var storage: [ObjectIdentifier: any Resource] = [:]

    /// No resources.
    @inlinable
    public init() {}

    /// The number of resources.
    @inlinable
    public var count: Int { storage.count }

    /// Whether there are no resources.
    @inlinable
    public var isEmpty: Bool { storage.isEmpty }

    /// Whether there is an `R`.
    @inlinable
    public func contains<R: Resource>(_ type: R.Type) -> Bool {
        storage[ObjectIdentifier(R.self)] != nil
    }

    /// Stores `resource`, replacing any `R`.
    @inlinable
    public mutating func insert<R: Resource>(_ resource: R) {
        storage[ObjectIdentifier(R.self)] = resource
    }

    /// Takes the `R` away.
    ///
    /// - Returns: The `R` there was, or `nil` if there was none.
    @inlinable
    @discardableResult
    public mutating func remove<R: Resource>(_ type: R.Type) -> R? {
        storage.removeValue(forKey: ObjectIdentifier(R.self)).map { $0 as! R }
    }

    /// The `R`, which can be changed in place.
    ///
    /// - Precondition: There is an `R`. Use ``subscript(checked:)`` to throw instead.
    @inlinable
    public subscript<R: Resource>(_ type: R.Type) -> R {
        get {
            guard let resource = storage[ObjectIdentifier(R.self)] else {
                preconditionFailure("No \(R.self) resource")
            }
            return resource as! R
        }
        _modify {
            // Moved out while it is written so the write does not copy it.
            guard let stored = storage.removeValue(forKey: ObjectIdentifier(R.self)) else {
                preconditionFailure("No \(R.self) resource")
            }
            var resource = stored as! R
            defer { storage[ObjectIdentifier(R.self)] = resource }
            yield &resource
        }
    }

    /// The `R`.
    ///
    /// - Throws: ``MissingResource`` when there is no `R`.
    @inlinable
    public subscript<R: Resource>(checked type: R.Type) -> R {
        get throws(MissingResource) {
            guard let resource = storage[ObjectIdentifier(R.self)] else { throw MissingResource() }
            return resource as! R
        }
    }
}
