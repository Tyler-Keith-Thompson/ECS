import Dispatch

/// A description of the component and resource types that a change to a world reads and writes.
///
/// Two changes *conflict* when one writes a type the other reads or writes. Changes that don't
/// conflict can run at the same time, with ``World/runConcurrently(_:)`` or in a schedule.
///
/// Build an access by chaining the types a change reads and writes:
///
/// ```swift
/// let movement = Access.reads(Velocity.self).writes(Position.self)
/// let scoring = Access.reads(Health.self).writes(resources: Score.self)
/// let healing = Access.writes(Health.self)
///
/// print(movement.conflicts(with: scoring))
/// // Prints "false"
/// print(scoring.conflicts(with: healing))
/// // Prints "true"
/// ```
///
/// Writing a type includes changing, inserting and removing it. Reading and writing events are
/// described with ``sends(_:)-swift.type.method`` and ``readsEvents(_:by:)-swift.type.method``.
public struct Access: Sendable {
    @usableFromInline var componentReads: Set<ObjectIdentifier> = []
    /// Each written component type, with what stores its column in a world.
    @usableFromInline var componentWrites: [ObjectIdentifier: @Sendable (inout World) -> Void] = [:]
    @usableFromInline var resourceReads: Set<ObjectIdentifier> = []
    @usableFromInline var resourceWrites: Set<ObjectIdentifier> = []

    /// Creates an access that reads and writes nothing.
    @inlinable
    public init() {}

    /// Returns an access that reads the given component types.
    ///
    /// - Parameter types: The component types to read.
    @inlinable
    public static func reads<each C: Component>(_ types: repeat (each C).Type) -> Access {
        Access().reads(repeat each types)
    }

    /// Returns an access that writes the given component types: changes, inserts and removes
    /// them.
    ///
    /// - Parameter types: The component types to write.
    @inlinable
    public static func writes<each C: Component>(_ types: repeat (each C).Type) -> Access {
        Access().writes(repeat each types)
    }

    /// Returns an access that reads the given resource types.
    ///
    /// - Parameter types: The resource types to read.
    @inlinable
    public static func reads<each R: Resource>(resources types: repeat (each R).Type) -> Access {
        Access().reads(resources: repeat each types)
    }

    /// Returns an access that writes the given resource types: changes, inserts and removes them.
    ///
    /// - Parameter types: The resource types to write.
    @inlinable
    public static func writes<each R: Resource>(resources types: repeat (each R).Type) -> Access {
        Access().writes(resources: repeat each types)
    }

    /// Returns an access that sends events of the given type.
    ///
    /// - Parameter type: The type of the events to send.
    @inlinable
    public static func sends<E: Event>(_ type: E.Type) -> Access {
        Access().sends(E.self)
    }

    /// Returns an access that reads events of the given type with ``World/readEvents(_:by:)``.
    ///
    /// - Parameters:
    ///   - type: The type of the events to read.
    ///   - reader: The reader type whose position in the events is kept.
    @inlinable
    public static func readsEvents<E: Event, Reader>(_ type: E.Type, by reader: Reader.Type) -> Access {
        Access().readsEvents(E.self, by: Reader.self)
    }

    /// Returns this access, also reading the given component types.
    ///
    /// - Parameter types: The component types to read.
    @inlinable
    public func reads<each C: Component>(_ types: repeat (each C).Type) -> Access {
        var access = self
        for type in repeat each types {
            access.componentReads.insert(ObjectIdentifier(type))
        }
        return access
    }

    /// Returns this access, also writing the given component types.
    ///
    /// Writing a component type includes changing, inserting and removing it, and so writing the
    /// ``RemovedComponent`` events of the type.
    ///
    /// - Parameter types: The component types to write.
    @inlinable
    public func writes<each C: Component>(_ types: repeat (each C).Type) -> Access {
        var access = self
        for type in repeat each types {
            access.insertWrite(of: type)
        }
        return access
    }

    @inlinable
    mutating func insertWrite<C: Component>(of type: C.Type) {
        componentWrites[ObjectIdentifier(C.self)] = Self.storer(of: C.self)
        resourceWrites.insert(ObjectIdentifier(Events<RemovedComponent<C>>.self))
    }

    @inlinable
    static func storer<C: Component>(of type: C.Type) -> @Sendable (inout World) -> Void {
        { world in _ = world.columnSlot(of: C.self) }
    }

    /// Returns this access, also reading the given resource types.
    ///
    /// - Parameter types: The resource types to read.
    @inlinable
    public func reads<each R: Resource>(resources types: repeat (each R).Type) -> Access {
        var access = self
        for type in repeat each types {
            access.resourceReads.insert(ObjectIdentifier(type))
        }
        return access
    }

    /// Returns this access, also writing the given resource types.
    ///
    /// - Parameter types: The resource types to write.
    @inlinable
    public func writes<each R: Resource>(resources types: repeat (each R).Type) -> Access {
        var access = self
        for type in repeat each types {
            access.resourceWrites.insert(ObjectIdentifier(type))
        }
        return access
    }

    /// Returns this access, also sending events of the given type.
    ///
    /// - Parameter type: The type of the events to send.
    @inlinable
    public func sends<E: Event>(_ type: E.Type) -> Access {
        writes(resources: Events<E>.self)
    }

    /// Returns this access, also reading events of the given type with
    /// ``World/readEvents(_:by:)``.
    ///
    /// - Parameters:
    ///   - type: The type of the events to read.
    ///   - reader: The reader type whose position in the events is kept.
    @inlinable
    public func readsEvents<E: Event, Reader>(_ type: E.Type, by reader: Reader.Type) -> Access {
        reads(resources: Events<E>.self).writes(resources: EventCursor<E, Reader>.self)
    }

    /// Returns this access, also reading and writing everything another access does.
    ///
    /// - Parameter other: The access to combine with this one.
    /// - Returns: An access that reads and writes the types of both.
    /// - Complexity: O(*t*), where *t* is the number of types in `other`.
    @inlinable
    public func merging(_ other: Access) -> Access {
        var access = self
        access.componentReads.formUnion(other.componentReads)
        access.componentWrites.merge(other.componentWrites) { first, _ in first }
        access.resourceReads.formUnion(other.resourceReads)
        access.resourceWrites.formUnion(other.resourceWrites)
        return access
    }

    /// Returns a Boolean value indicating whether this access and another can't run at the same
    /// time.
    ///
    /// Two accesses conflict when one writes a component or resource type that the other reads
    /// or writes. Two accesses that only read a type don't conflict.
    ///
    /// - Parameter other: The access to compare with.
    /// - Returns: `true` if the accesses conflict; otherwise, `false`.
    /// - Complexity: O(*t*), where *t* is the number of types in the two accesses.
    @inlinable
    public func conflicts(with other: Access) -> Bool {
        func writes(_ writer: Access, touch reader: Access) -> Bool {
            writer.componentWrites.keys.contains { reader.componentReads.contains($0) || reader.componentWrites[$0] != nil }
                || writer.resourceWrites.contains { reader.resourceReads.contains($0) || reader.resourceWrites.contains($0) }
        }
        return writes(self, touch: other) || writes(other, touch: self)
    }
}

/// A change to a world, paired with the access that describes what it reads and writes.
///
/// You pass concurrent changes to ``World/runConcurrently(_:)``, which runs changes whose
/// accesses don't conflict at the same time.
public struct ConcurrentChange: Sendable {
    /// The component and resource types the change reads and writes.
    public let access: Access
    /// The closure that makes the change.
    public let body: @Sendable (inout World) -> Void

    /// Creates a change from a closure and the access that describes it.
    ///
    /// - Parameters:
    ///   - access: The component and resource types `body` reads and writes.
    ///   - body: A closure that changes the world, reading and writing only what `access` lists.
    @inlinable
    public init(access: Access, body: @escaping @Sendable (inout World) -> Void) {
        self.access = access
        self.body = body
    }
}

extension World {
    /// Runs changes at the same time, each on its own copy of the world, and keeps what each one
    /// wrote.
    ///
    /// Use this method to spread independent work across the processor's cores. Each change reads
    /// the world as it was before any of them ran, and writes only the types its access lists, so
    /// the result is the same as running the changes one after another in any order:
    ///
    /// ```swift
    /// var world = World()
    /// let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Health(current: 10))
    ///
    /// world.runConcurrently([
    ///     ConcurrentChange(access: .reads(Velocity.self).writes(Position.self)) { world in
    ///         world.update(Position.self, reading: Velocity.self) { position, row in
    ///             position.x += row.components.dx
    ///         }
    ///     },
    ///     ConcurrentChange(access: .writes(Health.self)) { world in
    ///         world.update(Health.self) { health, _ in health.current -= 1 }
    ///     },
    /// ])
    ///
    /// print(world[Position.self, of: ball].x, world[Health.self, of: ball].current)
    /// // Prints "1.0 9"
    /// ```
    ///
    /// A change sees the components and resources that other changes write as missing, so its
    /// access must list everything it reads. Command buffers a change queues with ``queue(_:)``
    /// are queued in this world in the order of `changes`.
    ///
    /// - Important: A change must write only the component and resource types its access lists,
    ///   and must not spawn or despawn entities. It writes relations through their ``Targets``
    ///   components, and the hierarchy through `Targets<ChildOf>`.
    ///
    /// - Parameter changes: The changes to run.
    /// - Complexity: O(*c*·*t*), besides the cost of the changes themselves, where *c* is the
    ///   number of changes and *t* is the number of component types the world has stored.
    /// - Precondition: No two accesses conflict, and each change writes only what its access
    ///   lists and spawns and despawns nothing; a change that breaks this traps. In debug builds,
    ///   a change that reads a component or resource type its access doesn't list traps too. Any
    ///   change may read ``Disabled`` and ``Prefab``.
    public mutating func runConcurrently(_ changes: [ConcurrentChange]) {
        for first in changes.indices {
            for second in changes.indices where second > first {
                precondition(!changes[first].access.conflicts(with: changes[second].access), "Concurrent changes \(first) and \(second) conflict")
            }
        }
        for change in changes {
            for store in change.access.componentWrites.values {
                store(&self)
            }
        }
        // Move what each change writes out of the world, so its copy holds the only reference
        // and writing it copies nothing.
        var writtenSlots: [[Int]] = []
        var movedColumns: [[AnyColumn]] = []
        var movedResources: [[ObjectIdentifier: any Resource]] = []
        for change in changes {
            let slots = change.access.componentWrites.keys.map { columnPositions.position(of: $0)! }.sorted()
            writtenSlots.append(slots)
            movedColumns.append(slots.map { slot in
                let column = columns[slot]
                columns[slot] = column.makeEmpty()
                return column
            })
            var resourcesMoved: [ObjectIdentifier: any Resource] = [:]
            for key in change.access.resourceWrites {
                resourcesMoved[key] = resources.storage.removeValue(forKey: key)
            }
            movedResources.append(resourcesMoved)
        }
        var base = self
        base.refreshesCaches = false
        var copies: [World] = []
        for index in changes.indices {
            var copy = base
            copy.restrictAccess(to: changes[index].access)
            for (slot, column) in zip(writtenSlots[index], movedColumns[index]) {
                copy.columns[slot] = column
            }
            for (key, resource) in movedResources[index] {
                copy.resources.storage[key] = resource
            }
            copies.append(copy)
        }
        movedColumns = []
        movedResources = []

        copies.withUnsafeMutableBufferPointer { copies in
            let worlds = UncheckedWorlds(worlds: copies)
            DispatchQueue.concurrentPerform(iterations: changes.count) { index in
                changes[index].body(&worlds.worlds[index])
            }
        }

        for index in changes.indices {
            let copy = copies[index]
            precondition(
                copy.structureVersion == base.structureVersion && copy.columns.count == base.columns.count,
                "Concurrent change \(index) spawned, despawned or stored a new component type"
            )
            let written = Set(writtenSlots[index])
            for slot in copy.columns.indices where !written.contains(slot) {
                precondition(copy.columns[slot] === base.columns[slot], "Concurrent change \(index) wrote a component type its access does not list")
            }
            for slot in writtenSlots[index] {
                columns[slot] = copy.columns[slot]
            }
            takeRelationIndexes(of: changes[index].access.componentWrites.keys, from: copy)
            for key in changes[index].access.resourceWrites {
                resources.storage[key] = copy.resources.storage[key]
            }
            queuedCommands += copy.queuedCommands[base.queuedCommands.count...]
            markCachesStale(droppedBy: copy)
        }
        rebuildStaleCaches()
    }
}

/// The copies of a world that concurrent changes write, one each.
///
/// Unchecked: each change writes only its own element.
struct UncheckedWorlds: @unchecked Sendable {
    let worlds: UnsafeMutableBufferPointer<World>
}

extension World {
    /// A copy of this world holding the only reference to every column and resource `access`
    /// writes, which this world gives up (holding empty ones) until ``merge(writing:from:)``.
    ///
    /// Writing the copy copies no storage, and reading this world meanwhile does not keep the
    /// written storage shared.
    @inlinable
    package mutating func split(writing access: Access) -> World {
        for store in access.componentWrites.values {
            store(&self)
        }
        var part = self
        for type in access.componentWrites.keys {
            let slot = columnPositions.position(of: type)!
            columns[slot] = columns[slot].makeEmpty()
        }
        for key in access.resourceWrites {
            resources.storage.removeValue(forKey: key)
        }
        // `part` shares the columns array; dropping the written columns from this world's copy
        // of it left `part` the only holder.
        part.queuedCommands = []
        part.refreshesCaches = false
        splitParts += 1
        return part
    }

    /// Takes back the columns and resources `access` writes from `part`, a world returned by
    /// ``split(writing:)``.
    @inlinable
    package mutating func merge(writing access: Access, from part: World) {
        for type in access.componentWrites.keys {
            let slot = columnPositions.position(of: type)!
            columns[slot] = part.columns[slot]
        }
        takeRelationIndexes(of: access.componentWrites.keys, from: part)
        for key in access.resourceWrites {
            resources.storage[key] = part.resources.storage[key]
        }
        queuedCommands += part.queuedCommands
        splitParts = max(splitParts - 1, 0)
        markCachesStale(droppedBy: part)
        rebuildStaleCaches()
    }
}

extension World {
    /// In debug builds, makes reaching a component or resource type `access` does not list trap,
    /// until called again with nil; in release builds, does nothing.
    ///
    /// A component type is reached by any read, write or lookup of its storage; the types that
    /// skip entities by default (``Disabled``, ``Prefab``) may always be read. A resource type is
    /// read through `contains` and the subscripts, and written through `insert`, `remove` and a
    /// change in place, which need it listed as written.
    package mutating func restrictAccess(to access: Access?) {
        #if DEBUG
        guard let access else {
            columnPositions.permitted = nil
            resources.permitted = nil
            return
        }
        let components = access.componentReads.union(access.componentWrites.keys).union(disablingComponents)
        columnPositions.permitted = Set(components.map { UInt(bitPattern: $0) })
        resources.permitted = PermittedResources(reads: access.resourceReads, writes: access.resourceWrites)
        #endif
    }
}
