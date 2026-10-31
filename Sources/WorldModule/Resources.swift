/// The values a world holds once, outside any entity, keyed by their type.
///
/// ```swift
/// world.resources.insert(Time(elapsed: .zero))
/// world.resources[Time.self].elapsed += .milliseconds(16)
/// ```
@frozen
public struct Resources: Sendable {
    @usableFromInline var storage: [ObjectIdentifier: any Resource] = [:]
    #if DEBUG
    /// The resource types a system with a declared access may read and write while it runs, in
    /// debug builds; nil when any may be.
    @usableFromInline var permitted: PermittedResources?
    #endif

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
        #if DEBUG
        checkAccess(to: R.self, writing: false)
        #endif
        return storage[ObjectIdentifier(R.self)] != nil
    }

    /// Stores `resource`, replacing any `R`.
    @inlinable
    public mutating func insert<R: Resource>(_ resource: R) {
        #if DEBUG
        checkAccess(to: R.self, writing: true)
        #endif
        storage[ObjectIdentifier(R.self)] = resource
    }

    /// Takes the `R` away.
    ///
    /// - Returns: The `R` there was, or `nil` if there was none.
    @inlinable
    @discardableResult
    public mutating func remove<R: Resource>(_ type: R.Type) -> R? {
        #if DEBUG
        checkAccess(to: R.self, writing: true)
        #endif
        return storage.removeValue(forKey: ObjectIdentifier(R.self)).map { $0 as! R }
    }

    /// The `R`, which can be changed in place.
    ///
    /// - Precondition: There is an `R`. Use ``subscript(checked:)`` to throw instead.
    @inlinable
    public subscript<R: Resource>(_ type: R.Type) -> R {
        get {
            #if DEBUG
            checkAccess(to: R.self, writing: false)
            #endif
            guard let resource = storage[ObjectIdentifier(R.self)] else {
                preconditionFailure("No \(R.self) resource")
            }
            return resource as! R
        }
        _modify {
            #if DEBUG
            checkAccess(to: R.self, writing: true)
            #endif
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
            #if DEBUG
            checkAccess(to: R.self, writing: false)
            #endif
            guard let resource = storage[ObjectIdentifier(R.self)] else { throw MissingResource() }
            return resource as! R
        }
    }

    #if DEBUG
    /// Traps when a system running with a declared access reaches `R` beyond it.
    @inlinable
    func checkAccess<R: Resource>(to type: R.Type, writing: Bool) {
        guard let permitted else { return }
        let key = ObjectIdentifier(R.self)
        if writing {
            precondition(permitted.writes.contains(key), "A system wrote the resource \(R.self), which its access does not list as written")
        } else {
            precondition(permitted.reads.contains(key) || permitted.writes.contains(key), "A system read the resource \(R.self), which its access does not list")
        }
    }
    #endif
}

#if DEBUG
/// The resource types a system may read and write.
@usableFromInline
struct PermittedResources: Sendable {
    @usableFromInline let reads: Set<ObjectIdentifier>
    @usableFromInline let writes: Set<ObjectIdentifier>

    @inlinable
    init(reads: Set<ObjectIdentifier>, writes: Set<ObjectIdentifier>) {
        self.reads = reads
        self.writes = writes
    }
}
#endif
