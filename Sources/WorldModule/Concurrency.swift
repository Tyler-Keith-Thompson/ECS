import Dispatch

/// What a change to a world reads and writes: component types and resource types.
///
/// Changes whose accesses do not conflict can run at the same time with
/// ``World/runConcurrently(_:)``: neither writes a type the other reads or writes.
///
/// ```swift
/// let movement = Access.reads(Velocity.self).writes(Position.self)
/// let scoring = Access.reads(Health.self).writes(resources: Score.self)
/// ```
public struct Access: Sendable {
    @usableFromInline var componentReads: Set<ObjectIdentifier> = []
    /// Each written component type, with what stores its column in a world.
    @usableFromInline var componentWrites: [ObjectIdentifier: @Sendable (inout World) -> Void] = [:]
    @usableFromInline var resourceReads: Set<ObjectIdentifier> = []
    @usableFromInline var resourceWrites: Set<ObjectIdentifier> = []

    /// Reading and writing nothing.
    @inlinable
    public init() {}

    /// Reading the component types `types`.
    @inlinable
    public static func reads<each C: Component>(_ types: repeat (each C).Type) -> Access {
        Access().reads(repeat each types)
    }

    /// Writing the component types `types`: changing, inserting and removing them.
    @inlinable
    public static func writes<each C: Component>(_ types: repeat (each C).Type) -> Access {
        Access().writes(repeat each types)
    }

    /// Reading the resource types `types`.
    @inlinable
    public static func reads<each R: Resource>(resources types: repeat (each R).Type) -> Access {
        Access().reads(resources: repeat each types)
    }

    /// Writing the resource types `types`: changing, inserting and removing them.
    @inlinable
    public static func writes<each R: Resource>(resources types: repeat (each R).Type) -> Access {
        Access().writes(resources: repeat each types)
    }

    /// Sending events of type `E`.
    @inlinable
    public static func sends<E: Event>(_ type: E.Type) -> Access {
        Access().sends(E.self)
    }

    /// Reading events of type `E` with ``World/readEvents(_:by:)`` as `reader`.
    @inlinable
    public static func readsEvents<E: Event, Reader>(_ type: E.Type, by reader: Reader.Type) -> Access {
        Access().readsEvents(E.self, by: Reader.self)
    }

    /// This access, also reading the component types `types`.
    @inlinable
    public func reads<each C: Component>(_ types: repeat (each C).Type) -> Access {
        var access = self
        for type in repeat each types {
            access.componentReads.insert(ObjectIdentifier(type))
        }
        return access
    }

    /// This access, also writing the component types `types`.
    @inlinable
    public func writes<each C: Component>(_ types: repeat (each C).Type) -> Access {
        var access = self
        for type in repeat each types {
            access.componentWrites[ObjectIdentifier(type)] = Self.storer(of: type)
        }
        return access
    }

    @inlinable
    static func storer<C: Component>(of type: C.Type) -> @Sendable (inout World) -> Void {
        { world in _ = world.columnSlot(of: C.self) }
    }

    /// This access, also reading the resource types `types`.
    @inlinable
    public func reads<each R: Resource>(resources types: repeat (each R).Type) -> Access {
        var access = self
        for type in repeat each types {
            access.resourceReads.insert(ObjectIdentifier(type))
        }
        return access
    }

    /// This access, also writing the resource types `types`.
    @inlinable
    public func writes<each R: Resource>(resources types: repeat (each R).Type) -> Access {
        var access = self
        for type in repeat each types {
            access.resourceWrites.insert(ObjectIdentifier(type))
        }
        return access
    }

    /// This access, also sending events of type `E`.
    @inlinable
    public func sends<E: Event>(_ type: E.Type) -> Access {
        writes(resources: Events<E>.self)
    }

    /// This access, also reading events of type `E` with ``World/readEvents(_:by:)`` as
    /// `reader`.
    @inlinable
    public func readsEvents<E: Event, Reader>(_ type: E.Type, by reader: Reader.Type) -> Access {
        reads(resources: Events<E>.self).writes(resources: EventCursor<E, Reader>.self)
    }

    /// This access, also reading and writing everything `other` does.
    ///
    /// - Complexity: O(*t*) for *t* types in `other`.
    @inlinable
    public func merging(_ other: Access) -> Access {
        var access = self
        access.componentReads.formUnion(other.componentReads)
        access.componentWrites.merge(other.componentWrites) { first, _ in first }
        access.resourceReads.formUnion(other.resourceReads)
        access.resourceWrites.formUnion(other.resourceWrites)
        return access
    }

    /// Whether this access and `other` cannot run at the same time: one writes a type the
    /// other reads or writes.
    ///
    /// - Complexity: O(*t*) for *t* types in the two accesses.
    @inlinable
    public func conflicts(with other: Access) -> Bool {
        func writes(_ writer: Access, touch reader: Access) -> Bool {
            writer.componentWrites.keys.contains { reader.componentReads.contains($0) || reader.componentWrites[$0] != nil }
                || writer.resourceWrites.contains { reader.resourceReads.contains($0) || reader.resourceWrites.contains($0) }
        }
        return writes(self, touch: other) || writes(other, touch: self)
    }
}

/// A change to a world and what it reads and writes, for ``World/runConcurrently(_:)``.
public struct ConcurrentChange: Sendable {
    /// What `body` reads and writes.
    public let access: Access
    /// The change.
    public let body: @Sendable (inout World) -> Void

    /// `body`, which reads and writes only what `access` lists.
    @inlinable
    public init(access: Access, body: @escaping @Sendable (inout World) -> Void) {
        self.access = access
        self.body = body
    }
}

extension World {
    /// Runs `changes` at the same time, each on a copy of the world, and keeps what each wrote.
    ///
    /// Each change reads the world as it was before any of them ran, and writes only the types
    /// its access lists, so the result is the same as running them one after another in any
    /// order. A change sees the components and resources other changes write as missing, so it
    /// must declare everything it reads. Command buffers a change queues (``queue(_:)``) are
    /// queued here in the order of `changes`.
    ///
    /// - Complexity: O(*c*·*t*) besides the changes themselves, for *c* changes and *t* stored
    ///   component types.
    /// - Precondition: No two accesses conflict. Each change writes only the component and
    ///   resource types its access lists, and spawns, despawns and changes the hierarchy not at
    ///   all; a change that writes another component type or changes the entities traps.
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
                "Concurrent change \(index) spawned, despawned, changed the hierarchy or stored a new component type"
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
