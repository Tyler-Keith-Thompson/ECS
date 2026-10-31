/// A collection of resources, holding at most one value of each type.
///
/// Every world has a resources collection, its ``World/resources`` property. You add a resource
/// with ``insert(_:)``, then read and change it in place through its type:
///
/// ```swift
/// struct Gravity: Resource { var acceleration: Double }
///
/// var world = World()
/// world.resources.insert(Gravity(acceleration: -9.8))
/// world.resources[Gravity.self].acceleration *= 0.5
///
/// print(world.resources[Gravity.self].acceleration)
/// // Prints "-4.9"
/// ```
///
/// Reading a resource the collection doesn't hold traps, in the same way that reading an array
/// out of bounds does. Use ``subscript(checked:)`` when the resource may be missing.
@frozen
public struct Resources: Sendable {
    @usableFromInline var storage: [ObjectIdentifier: any Resource] = [:]
    #if DEBUG
    /// The resource types a system with a declared access may read and write while it runs, in
    /// debug builds; nil when any may be.
    @usableFromInline var permitted: PermittedResources?
    #endif

    /// Creates an empty collection of resources.
    @inlinable
    public init() {}

    /// The number of resources in the collection.
    @inlinable
    public var count: Int { storage.count }

    /// A Boolean value indicating whether the collection holds no resources.
    @inlinable
    public var isEmpty: Bool { storage.isEmpty }

    /// Returns a Boolean value indicating whether the collection holds a resource of the given
    /// type.
    ///
    /// - Parameter type: The resource type to look for.
    /// - Returns: `true` if the collection holds a resource of type `type`; otherwise, `false`.
    /// - Complexity: O(1).
    @inlinable
    public func contains<R: Resource>(_ type: R.Type) -> Bool {
        #if DEBUG
        checkAccess(to: R.self, writing: false)
        #endif
        return storage[ObjectIdentifier(R.self)] != nil
    }

    /// Adds a resource to the collection, replacing any of the same type.
    ///
    /// - Parameter resource: The resource to add.
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func insert<R: Resource>(_ resource: R) {
        #if DEBUG
        checkAccess(to: R.self, writing: true)
        #endif
        storage[ObjectIdentifier(R.self)] = resource
    }

    /// Removes and returns the resource of the given type.
    ///
    /// ```swift
    /// var world = World()
    /// world.resources.insert(Gravity(acceleration: -9.8))
    ///
    /// let removed = world.resources.remove(Gravity.self)
    /// print(removed?.acceleration ?? 0, world.resources.isEmpty)
    /// // Prints "-9.8 true"
    /// ```
    ///
    /// - Parameter type: The type of the resource to remove.
    /// - Returns: The resource that was removed, or `nil` if the collection held none of type
    ///   `type`.
    /// - Complexity: O(1).
    @inlinable
    @discardableResult
    public mutating func remove<R: Resource>(_ type: R.Type) -> R? {
        #if DEBUG
        checkAccess(to: R.self, writing: true)
        #endif
        return storage.removeValue(forKey: ObjectIdentifier(R.self)).map { $0 as! R }
    }

    /// Accesses the resource of the given type.
    ///
    /// Use this subscript to read a resource, or to change it in place:
    /// `world.resources[Gravity.self].acceleration = -1.6`.
    ///
    /// - Parameter type: The type of the resource to access.
    /// - Complexity: O(1).
    /// - Precondition: The collection holds a resource of type `type`. The checked spelling,
    ///   ``subscript(checked:)``, throws instead.
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

    /// Reads the resource of the given type, throwing an error if the collection holds none.
    ///
    /// Write `try?` to get `nil` instead of an error:
    ///
    /// ```swift
    /// let world = World()
    /// let gravity = try? world.resources[checked: Gravity.self]
    /// print(gravity == nil)
    /// // Prints "true"
    /// ```
    ///
    /// - Parameter type: The type of the resource to read.
    /// - Throws: ``MissingResource`` if the collection holds no resource of type `type`.
    /// - Complexity: O(1).
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
