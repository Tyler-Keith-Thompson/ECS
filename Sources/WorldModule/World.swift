/// A collection of entities, the components they hold, and resources.
///
/// A world is where the state of your game or simulation lives. An *entity* is one thing in it,
/// such as a ball, a player or a particle, and you refer to it by its handle, an ``Entity``. An
/// entity has no data of its own; instead it holds *components*, plain values that conform to
/// ``Component``, at most one of each type. A *resource* is a value the world holds once, outside
/// any entity, such as a clock or a score; you reach resources through ``resources``.
///
/// Create a world, spawn an entity with its components, and read or change a component through
/// the entity's handle:
///
/// ```swift
/// var world = World()
/// let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
///
/// world[Position.self, of: ball].x = 5
/// print(world[Position.self, of: ball])
/// // Prints "Position(x: 5.0, y: 0.0)"
/// ```
///
/// You can give an entity more components with `insert(_:into:)`, take them away with
/// `remove(_:from:)`, and remove the entity and everything it holds with ``despawn(_:)``.
///
/// ### Working with Many Entities
///
/// Most work in a game touches every entity that holds some set of component types. Use
/// `query(_:)` to read those entities, and `update(_:reading:where:body:)` to change one
/// component of each in place while reading others. The following example moves every entity
/// that holds both a position and a velocity, then reads back the positions:
///
/// ```swift
/// var world = World()
/// world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
/// world.spawn(Position(x: 10, y: 0), Velocity(dx: 0, dy: 2))
/// world.spawn(Position(x: 99, y: 99))  // No velocity, so it doesn't move.
///
/// world.update(Position.self, reading: Velocity.self) { position, row in
///     position.x += row.components.dx
///     position.y += row.components.dy
/// }
///
/// var coordinates: [(Double, Double)] = []
/// for (_, position) in world.query(Position.self) {
///     coordinates.append((position.x, position.y))
/// }
/// print(coordinates)
/// // Prints "[(1.0, 0.0), (10.0, 2.0), (99.0, 99.0)]"
/// ```
///
/// While an update or a query is running, the world can't be changed in other ways. To spawn,
/// despawn or restructure entities from inside one, record the changes in ``Commands`` and
/// ``apply(_:)`` them afterward.
///
/// ### Value Semantics
///
/// A world is a value, like an array or a dictionary: a copy is independent of the original.
/// Copying is cheap, because each component type's storage is shared between copies until one of
/// them writes to it, and then only that type's storage is copied. This makes it easy to keep an
/// earlier state, for undo or for comparing two steps of a simulation:
///
/// ```swift
/// var world = World()
/// let hero = world.spawn(Health(current: 10))
///
/// let saved = world
/// world[Health.self, of: hero].current = 0
///
/// print(saved[Health.self, of: hero].current)
/// // Prints "10"
/// ```
///
/// ### Stale Entities and Checked Spellings
///
/// Despawning an entity makes every copy of its handle *stale*. A world can reuse the slot the
/// entity occupied, but a stale handle never names the new occupant. Use ``contains(_:)`` to test
/// whether a handle is still live.
///
/// Operations that take an entity trap when it is stale, in the same way an array subscript traps
/// when its index is out of range. Each has a `checked` spelling that throws instead, for entities
/// whose liveness you can't be sure of:
///
/// ```swift
/// var world = World()
/// let spark = world.spawn(Position(x: 0, y: 0))
/// world.despawn(spark)
///
/// do {
///     try world.despawn(checked: spark)
/// } catch {
///     print(error)
///     // Prints "StaleEntity()"
/// }
/// ```
///
/// ### Storage
///
/// The components of each type are stored in a sparse set: a dense array of components with a
/// sparse array from entity slot to position. Reading, adding, replacing and removing one
/// component are O(1), and visiting every component of a type walks contiguous memory.
@frozen
public struct World: Sendable {
    /// The generation of each slot's current or next entity.
    @usableFromInline var generations: [UInt32] = []
    /// Whether each slot holds a live entity.
    @usableFromInline var isLive: [Bool] = []
    /// Vacated slots, the most recently vacated last.
    @usableFromInline var vacant: [UInt32] = []
    /// One column per component type ever stored, in the order the types were first stored.
    @usableFromInline var columns: ContiguousArray<AnyColumn> = []
    @usableFromInline var columnPositions = ColumnTable()
    /// The component hooks and the hook calls waiting to run.
    @usableFromInline var hooks = Hooks()
    /// The owning groups, each column knowing its group by position here.
    @usableFromInline var groups: [OwningGroup] = []
    /// The indexes of components by value (``index(_:)``), by component type.
    @usableFromInline var valueIndexes: [ObjectIdentifier: any AnyValueIndex] = [:]
    /// The observers of entity events.
    @usableFromInline var observers = Observers()
    /// Each relation's sources by target, in the order the relations were first stored.
    @usableFromInline var relationIndexes: [RelationIndex] = []
    /// The cached queries' entities (``cache(_:)``).
    @usableFromInline var caches: [QueryCache] = []
    /// Whether adding and removing components updates the caches, or drops the ones they touch:
    /// false in a part split off for a concurrent change.
    @usableFromInline var refreshesCaches = true
    /// The parts split off with ``split(writing:)`` and not yet merged back.
    @usableFromInline var splitParts = 0
    /// Counts changes to which entities are live.
    @usableFromInline var structureVersion: UInt64 = 0
    /// The component types whose entities queries skip unless they mention them.
    @usableFromInline var disablingComponents: [ObjectIdentifier] = [ObjectIdentifier(Disabled.self), ObjectIdentifier(Prefab.self)]
    /// Command buffers queued with ``queue(_:)``, in the order they were queued.
    @usableFromInline var queuedCommands: [Commands] = []

    /// The world's resources: values it holds once, outside any entity.
    ///
    /// Use resources for state that belongs to the whole world rather than to one entity, such as
    /// the elapsed time or a score:
    ///
    /// ```swift
    /// struct Score: Resource { var points: Int }
    ///
    /// var world = World()
    /// world.resources.insert(Score(points: 0))
    /// world.resources[Score.self].points += 10
    ///
    /// print(world.resources[Score.self].points)
    /// // Prints "10"
    /// ```
    public var resources = Resources()

    /// The tick the world stamps on every component it adds or changes.
    ///
    /// The tick starts at 1 and moves forward only through ``advanceChangeTick()``, which a
    /// schedule calls before each system it runs. Filters such as
    /// ``QueryFilter/changed(_:since:)-swift.type.method`` compare the ticks stamped on
    /// components with an earlier tick to find what changed since then.
    public var changeTick: ChangeTick { storedChangeTick }
    @usableFromInline var storedChangeTick = ChangeTick(1)

    /// The change tick at which the running system last ran.
    ///
    /// Filters such as ``QueryFilter/changed(_:since:)-swift.type.method`` compare against this
    /// tick when you give them none, so a system sees what changed since its previous run. A
    /// schedule sets it around each system it runs, to ``ChangeTick/zero`` for a system that has
    /// not run before, and restores the earlier value when it finishes; set it yourself only when
    /// you run systems without one. It is ``ChangeTick/zero`` in a new world.
    public var lastRun = ChangeTick.zero

    /// Starts a new change tick, so components added or changed from now on are newer than every
    /// earlier tick.
    ///
    /// Use this method to mark a point in the world's history. Afterward, a filter such as
    /// ``QueryFilter/changed(_:since:)-swift.type.method`` with the earlier tick finds exactly
    /// the components changed since that point. The following example changes one entity's
    /// health after a checkpoint and then finds it:
    ///
    /// ```swift
    /// var world = World()
    /// world.spawn(Health(current: 10))
    /// let hero = world.spawn(Health(current: 10))
    ///
    /// let checkpoint = world.changeTick
    /// world.advanceChangeTick()
    /// world[Health.self, of: hero].current -= 1
    ///
    /// let changed = world.query(Health.self).changed(Health.self, since: checkpoint)
    /// print(changed.map(\.entity) == [hero])
    /// // Prints "true"
    /// ```
    ///
    /// A schedule calls this method before each system it runs.
    ///
    /// - Returns: The new tick.
    /// - Complexity: O(1), plus the cost of refreshing the world's value indexes, if it has any.
    @inlinable
    @discardableResult
    public mutating func advanceChangeTick() -> ChangeTick {
        storedChangeTick = ChangeTick(storedChangeTick.value + 1)
        if !valueIndexes.isEmpty {
            refreshValueIndexes()
        }
        return storedChangeTick
    }

    /// Creates an empty world, with no entities or resources.
    @inlinable
    public init() {}

    // MARK: Entities

    /// The number of live entities in the world.
    ///
    /// - Complexity: O(1).
    @inlinable
    public var count: Int { generations.count - vacant.count }

    /// A Boolean value indicating whether the world has no live entities.
    ///
    /// - Complexity: O(1).
    @inlinable
    public var isEmpty: Bool { count == 0 }

    /// The live entities in the world, in slot order.
    ///
    /// The view is computed lazily as you iterate it. It includes every live entity, even ones
    /// that hold no components or that queries skip, such as ``Disabled`` entities:
    ///
    /// ```swift
    /// var world = World()
    /// let first = world.spawn(Position(x: 0, y: 0))
    /// let second = world.spawn()
    ///
    /// print(Array(world.entities) == [first, second])
    /// // Prints "true"
    /// ```
    @inlinable
    public var entities: EntitiesView { EntitiesView(generations: generations, isLive: isLive) }

    /// Returns a Boolean value indicating whether the given entity is live in this world.
    ///
    /// An entity is live from the moment it is spawned until it is despawned:
    ///
    /// ```swift
    /// var world = World()
    /// let spark = world.spawn(Position(x: 0, y: 0))
    /// print(world.contains(spark))
    /// // Prints "true"
    ///
    /// world.despawn(spark)
    /// print(world.contains(spark))
    /// // Prints "false"
    /// ```
    ///
    /// - Parameter entity: The entity to look for.
    /// - Returns: `true` if `entity` is live in this world; otherwise, `false`.
    /// - Complexity: O(1).
    @inlinable
    public func contains(_ entity: Entity) -> Bool {
        let slot = Int(entity.index)
        return slot < generations.count && isLive[slot] && generations[slot] == entity.generation
    }

    /// Creates an entity holding the given components and returns its handle.
    ///
    /// Pass any number of components, or ``Bundle`` values that group components together. Each
    /// component is a bundle of itself, so the following example spawns an entity holding both a
    /// position and a velocity:
    ///
    /// ```swift
    /// var world = World()
    /// let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    ///
    /// print(world.contains(Velocity.self, in: ball))
    /// // Prints "true"
    /// ```
    ///
    /// When the bundles hold two components of the same type, the later one is kept. Components
    /// that the spawned components require (``Component/required-u15k``) are added too, unless
    /// the bundles already include one of the same type.
    ///
    /// The new entity may reuse the slot of a despawned entity, the most recently vacated first,
    /// with a generation one higher than the slot's last entity, so handles to the despawned
    /// entity stay stale.
    ///
    /// Spawning one, two or three components has overloads specialized for speed.
    ///
    /// - Parameter bundles: The components and bundles the new entity holds.
    /// - Returns: The handle of the new entity.
    /// - Complexity: O(*k*) amortized, where *k* is the number of components.
    /// - Precondition: Fewer than `UInt32.max` slots are in use.
    @inlinable
    @discardableResult
    public mutating func spawn<each B: Bundle>(_ bundles: repeat each B) -> Entity {
        let entity = makeEntity()
        for bundle in repeat each bundles {
            bundle.insert(into: entity, in: &self)
        }
        for bundle in repeat each bundles {
            bundle._insertRequired(into: entity, in: &self)
        }
        endOperation()
        return entity
    }

    /// Creates an entity holding the components of a bundle and returns its handle.
    ///
    /// This overload behaves like the variadic ``spawn(_:)-2slwa``.
    ///
    /// - Parameter bundle: The components the new entity holds.
    /// - Returns: The handle of the new entity.
    /// - Complexity: O(*k*) amortized, where *k* is the number of components.
    @inlinable
    @discardableResult
    public mutating func spawn<B: Bundle>(_ bundle: B) -> Entity {
        let entity = makeEntity()
        bundle.insert(into: entity, in: &self)
        bundle._insertRequired(into: entity, in: &self)
        endOperation()
        return entity
    }

    /// Creates an entity holding one component and returns its handle.
    ///
    /// This overload behaves like the variadic ``spawn(_:)-2slwa``.
    ///
    /// - Parameter a: The component the new entity holds.
    /// - Returns: The handle of the new entity.
    /// - Complexity: O(1) amortized.
    @inlinable
    @discardableResult
    public mutating func spawn<A: Component>(_ a: A) -> Entity {
        let entity = makeEntity()
        store(a, for: entity)
        a._insertRequired(into: entity, in: &self)
        endOperation()
        return entity
    }

    /// Creates an entity holding two components and returns its handle.
    ///
    /// This overload behaves like the variadic ``spawn(_:)-2slwa``.
    ///
    /// - Parameters:
    ///   - a: The first component the new entity holds.
    ///   - b: The second component the new entity holds.
    /// - Returns: The handle of the new entity.
    /// - Complexity: O(1) amortized.
    @inlinable
    @discardableResult
    public mutating func spawn<A: Component, B: Component>(_ a: A, _ b: B) -> Entity {
        let entity = makeEntity()
        store(a, for: entity)
        store(b, for: entity)
        a._insertRequired(into: entity, in: &self)
        b._insertRequired(into: entity, in: &self)
        endOperation()
        return entity
    }

    /// Creates an entity holding three components and returns its handle.
    ///
    /// This overload behaves like the variadic ``spawn(_:)-2slwa``.
    ///
    /// - Parameters:
    ///   - a: The first component the new entity holds.
    ///   - b: The second component the new entity holds.
    ///   - c: The third component the new entity holds.
    /// - Returns: The handle of the new entity.
    /// - Complexity: O(1) amortized.
    @inlinable
    @discardableResult
    public mutating func spawn<A: Component, B: Component, C: Component>(_ a: A, _ b: B, _ c: C) -> Entity {
        let entity = makeEntity()
        store(a, for: entity)
        store(b, for: entity)
        store(c, for: entity)
        a._insertRequired(into: entity, in: &self)
        b._insertRequired(into: entity, in: &self)
        c._insertRequired(into: entity, in: &self)
        endOperation()
        return entity
    }

    /// Removes an entity, its descendants, and every component they hold from the world.
    ///
    /// Despawning an entity also detaches it from its parent, and despawns the entities whose
    /// relations to it say to despawn with their target (``CleanupAction``). Every copy of the
    /// handles of the despawned entities is stale afterward:
    ///
    /// ```swift
    /// var world = World()
    /// let ship = world.spawn(Position(x: 0, y: 0))
    /// let turret = world.spawn(Position(x: 1, y: 0))
    /// try world.addChild(turret, to: ship)
    ///
    /// world.despawn(ship)
    /// print(world.contains(turret))
    /// // Prints "false"
    /// ```
    ///
    /// - Parameter entity: The entity to despawn.
    /// - Complexity: O(*n*·*t*), where *n* is the number of entities despawned and *t* is the
    ///   number of component types the world has stored.
    /// - Precondition: `entity` is live. The checked spelling, ``despawn(checked:)``, throws
    ///   instead.
    @inlinable
    public mutating func despawn(_ entity: Entity) {
        precondition(contains(entity), "Despawning stale entity \(entity)")
        destroyCascading(entity)
        endOperation()
    }

    /// Removes an entity, its descendants, and every component they hold from the world, throwing
    /// an error if the entity isn't live.
    ///
    /// Use this method instead of ``despawn(_:)`` when the entity may already have been
    /// despawned:
    ///
    /// ```swift
    /// var world = World()
    /// let spark = world.spawn(Position(x: 0, y: 0))
    /// try world.despawn(checked: spark)
    ///
    /// let despawnedAgain = (try? world.despawn(checked: spark)) != nil
    /// print(despawnedAgain)
    /// // Prints "false"
    /// ```
    ///
    /// - Parameter entity: The entity to despawn.
    /// - Throws: ``StaleEntity`` if `entity` isn't live. The world is unchanged.
    /// - Complexity: O(*n*·*t*), where *n* is the number of entities despawned and *t* is the
    ///   number of component types the world has stored.
    @inlinable
    public mutating func despawn(checked entity: Entity) throws(StaleEntity) {
        guard contains(entity) else { throw StaleEntity() }
        destroyCascading(entity)
        endOperation()
    }

    // MARK: Components

    /// Returns a Boolean value indicating whether an entity holds a component of the given type.
    ///
    /// ```swift
    /// var world = World()
    /// let ball = world.spawn(Position(x: 0, y: 0))
    ///
    /// print(world.contains(Position.self, in: ball))
    /// // Prints "true"
    /// print(world.contains(Velocity.self, in: ball))
    /// // Prints "false"
    /// ```
    ///
    /// - Parameters:
    ///   - type: The component type to look for.
    ///   - entity: The entity to look in.
    /// - Returns: `true` if `entity` is live and holds a component of type `type`; otherwise,
    ///   `false`.
    /// - Complexity: O(1).
    @inlinable
    public func contains<C: Component>(_ type: C.Type, in entity: Entity) -> Bool {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return false }
        return unretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { $0.index.position(of: entity) != nil }
    }

    /// Accesses the component of the given type that an entity holds.
    ///
    /// Use this subscript to read one component of one entity, or to change it in place:
    ///
    /// ```swift
    /// var world = World()
    /// let hero = world.spawn(Health(current: 100))
    ///
    /// world[Health.self, of: hero].current -= 10
    /// print(world[Health.self, of: hero].current)
    /// // Prints "90"
    /// ```
    ///
    /// Writing through the subscript marks the component changed at the current ``changeTick``.
    /// To give an entity a component it doesn't hold yet, use `insert(_:into:)`.
    ///
    /// - Parameters:
    ///   - type: The type of the component to access.
    ///   - entity: The entity that holds the component.
    /// - Complexity: O(1), plus a copy of the storage of `type` on the first write after the
    ///   world was copied.
    /// - Precondition: `entity` is live and holds a component of type `type`. The checked
    ///   spelling, ``subscript(checked:of:)``, throws instead.
    @inlinable
    public subscript<C: Component>(_ type: C.Type, of entity: Entity) -> C {
        get {
            precondition(contains(entity), "Reading a \(C.self) of stale entity \(entity)")
            guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else {
                preconditionFailure("Entity \(entity) holds no \(C.self)")
            }
            return unretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { column in
                guard let position = column.index.position(of: entity) else {
                    preconditionFailure("Entity \(entity) holds no \(C.self)")
                }
                return column.values[position]
            }
        }
        _modify {
            precondition(contains(entity), "Writing a \(C.self) of stale entity \(entity)")
            guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)),
                  let position = columns[slot].index.position(of: entity) else {
                preconditionFailure("Entity \(entity) holds no \(C.self)")
            }
            // Moved out while it is written: yielding storage inside the column would retain the
            // column for the duration.
            let column = uniqueUnretainedColumn(at: slot, of: C.self)
            let tick = changeTick
            column._withUnsafeGuaranteedRef { $0.index.ticks[position].changed = tick }
            var values: [C] = []
            column._withUnsafeGuaranteedRef { swap(&values, &$0.values) }
            defer { column._withUnsafeGuaranteedRef { swap(&values, &$0.values) } }
            yield &values[position]
        }
    }

    /// Reads the component of the given type that an entity holds, throwing an error if it holds
    /// none.
    ///
    /// Use this subscript when the entity may not hold the component, or may no longer be live.
    /// Write `try?` to get `nil` instead of an error:
    ///
    /// ```swift
    /// var world = World()
    /// let ball = world.spawn(Position(x: 0, y: 0))
    ///
    /// let velocity = try? world[checked: Velocity.self, of: ball]
    /// print(velocity == nil)
    /// // Prints "true"
    /// ```
    ///
    /// - Parameters:
    ///   - type: The type of the component to read.
    ///   - entity: The entity that holds the component.
    /// - Throws: ``MissingComponent`` if `entity` is stale or holds no component of type `type`.
    /// - Complexity: O(1).
    @inlinable
    public subscript<C: Component>(checked type: C.Type, of entity: Entity) -> C {
        get throws(MissingComponent) {
            guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { throw MissingComponent() }
            let component: C? = unretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { column in
                column.index.position(of: entity).map { column.values[$0] }
            }
            guard let component else { throw MissingComponent() }
            return component
        }
    }

    /// Accesses the component of the given type that an entity holds, or `nil` if it holds none.
    ///
    /// Use this subscript for a component an entity may or may not hold. Reading it gives `nil`
    /// when the entity holds none; assigning `nil` removes the component, and assigning a value
    /// to an entity that holds none inserts it:
    ///
    /// ```swift
    /// var world = World()
    /// let ship = world.spawn(Position(x: 0, y: 0))
    ///
    /// print(world[Velocity?.self, of: ship] == nil)
    /// // Prints "true"
    ///
    /// world[Velocity?.self, of: ship] = Velocity(dx: 1, dy: 0)
    /// world[Velocity?.self, of: ship]?.dx += 1
    /// print(world[Velocity.self, of: ship].dx)
    /// // Prints "2.0"
    ///
    /// world[Velocity?.self, of: ship] = nil
    /// print(world.contains(Velocity.self, in: ship))
    /// // Prints "false"
    /// ```
    ///
    /// Writing to a component the entity holds changes it in place and marks it changed at the
    /// current ``changeTick``, as the plain subscript does. Inserting runs the component's insert
    /// hooks and adds the components it requires, as `insert(_:into:)` does, and removing runs
    /// its remove hooks, as `remove(_:from:)` does.
    ///
    /// - Parameters:
    ///   - type: The optional type of the component to access.
    ///   - entity: The entity that holds the component.
    /// - Complexity: O(1), plus a copy of the storage of the component type on the first write
    ///   after the world was copied.
    /// - Precondition: `entity` is live.
    @inlinable
    public subscript<C: Component>(_ type: C?.Type, of entity: Entity) -> C? {
        get {
            precondition(contains(entity), "Reading a \(C.self) of stale entity \(entity)")
            return try? self[checked: C.self, of: entity]
        }
        _modify {
            precondition(contains(entity), "Writing a \(C.self) of stale entity \(entity)")
            let held = try? self[checked: C.self, of: entity]
            var component = held
            yield &component
            switch (held, component) {
            case (_?, let written?): self[C.self, of: entity] = written
            case (nil, let inserted?): insert(inserted, into: entity)
            case (_?, nil): remove(C.self, from: entity)
            case (nil, nil): break
            }
        }
    }

    /// Adds the given components to an entity, replacing any it holds of the same types.
    ///
    /// Use this method to give an existing entity more components, or to replace a component
    /// wholesale. Pass any number of components or ``Bundle`` values:
    ///
    /// ```swift
    /// var world = World()
    /// let ball = world.spawn(Position(x: 0, y: 0))
    ///
    /// world.insert(Velocity(dx: 1, dy: 0), Position(x: 5, y: 5), into: ball)
    /// print(world[Position.self, of: ball])
    /// // Prints "Position(x: 5.0, y: 5.0)"
    /// ```
    ///
    /// A component the entity didn't hold is marked added and changed at the current
    /// ``changeTick``; a replaced one is marked changed. Components that the inserted components
    /// require (``Component/required-u15k``) are added too, unless the entity already holds one of
    /// the same type.
    ///
    /// Inserting one, two or three components has overloads specialized for speed.
    ///
    /// - Parameters:
    ///   - bundles: The components and bundles to add.
    ///   - entity: The entity to add them to.
    /// - Complexity: O(*k*) amortized, where *k* is the number of components.
    /// - Precondition: `entity` is live. The checked spelling, ``insert(_:checkedInto:)``, throws
    ///   instead.
    @inlinable
    public mutating func insert<each B: Bundle>(_ bundles: repeat each B, into entity: Entity) {
        precondition(contains(entity), "Inserting into stale entity \(entity)")
        for bundle in repeat each bundles {
            bundle.insert(into: entity, in: &self)
        }
        for bundle in repeat each bundles {
            bundle._insertRequired(into: entity, in: &self)
        }
        endOperation()
    }

    /// Adds the components of a bundle to an entity, replacing any it holds of the same types.
    ///
    /// This overload behaves like the variadic ``insert(_:into:)-70968``.
    ///
    /// - Parameters:
    ///   - bundle: The components to add.
    ///   - entity: The entity to add them to.
    /// - Complexity: O(*k*) amortized, where *k* is the number of components.
    /// - Precondition: `entity` is live. The checked spelling, ``insert(_:checkedInto:)``, throws
    ///   instead.
    @inlinable
    public mutating func insert<B: Bundle>(_ bundle: B, into entity: Entity) {
        precondition(contains(entity), "Inserting into stale entity \(entity)")
        bundle.insert(into: entity, in: &self)
        bundle._insertRequired(into: entity, in: &self)
        endOperation()
    }

    /// Adds a component to an entity, replacing any it holds of the same type.
    ///
    /// This overload behaves like the variadic ``insert(_:into:)-70968``.
    ///
    /// - Parameters:
    ///   - a: The component to add.
    ///   - entity: The entity to add it to.
    /// - Complexity: O(1) amortized.
    /// - Precondition: `entity` is live. The checked spelling, ``insert(_:checkedInto:)``, throws
    ///   instead.
    @inlinable
    public mutating func insert<A: Component>(_ a: A, into entity: Entity) {
        precondition(contains(entity), "Inserting into stale entity \(entity)")
        store(a, for: entity)
        a._insertRequired(into: entity, in: &self)
        endOperation()
    }

    /// Adds two components to an entity, replacing any it holds of the same types.
    ///
    /// This overload behaves like the variadic ``insert(_:into:)-70968``.
    ///
    /// - Parameters:
    ///   - a: The first component to add.
    ///   - b: The second component to add.
    ///   - entity: The entity to add them to.
    /// - Complexity: O(1) amortized.
    /// - Precondition: `entity` is live. The checked spelling, ``insert(_:checkedInto:)``, throws
    ///   instead.
    @inlinable
    public mutating func insert<A: Component, B: Component>(_ a: A, _ b: B, into entity: Entity) {
        precondition(contains(entity), "Inserting into stale entity \(entity)")
        store(a, for: entity)
        store(b, for: entity)
        a._insertRequired(into: entity, in: &self)
        b._insertRequired(into: entity, in: &self)
        endOperation()
    }

    /// Adds three components to an entity, replacing any it holds of the same types.
    ///
    /// This overload behaves like the variadic ``insert(_:into:)-70968``.
    ///
    /// - Parameters:
    ///   - a: The first component to add.
    ///   - b: The second component to add.
    ///   - c: The third component to add.
    ///   - entity: The entity to add them to.
    /// - Complexity: O(1) amortized.
    /// - Precondition: `entity` is live. The checked spelling, ``insert(_:checkedInto:)``, throws
    ///   instead.
    @inlinable
    public mutating func insert<A: Component, B: Component, C: Component>(_ a: A, _ b: B, _ c: C, into entity: Entity) {
        precondition(contains(entity), "Inserting into stale entity \(entity)")
        store(a, for: entity)
        store(b, for: entity)
        store(c, for: entity)
        a._insertRequired(into: entity, in: &self)
        b._insertRequired(into: entity, in: &self)
        c._insertRequired(into: entity, in: &self)
        endOperation()
    }

    /// Adds the given components to an entity, replacing any it holds of the same types, and
    /// throws an error if the entity isn't live.
    ///
    /// ```swift
    /// var world = World()
    /// let spark = world.spawn(Position(x: 0, y: 0))
    /// world.despawn(spark)
    ///
    /// let inserted = (try? world.insert(Velocity(dx: 1, dy: 0), checkedInto: spark)) != nil
    /// print(inserted)
    /// // Prints "false"
    /// ```
    ///
    /// - Parameters:
    ///   - bundles: The components and bundles to add.
    ///   - entity: The entity to add them to.
    /// - Throws: ``StaleEntity`` if `entity` isn't live. The world is unchanged.
    /// - Complexity: O(*k*) amortized, where *k* is the number of components.
    @inlinable
    public mutating func insert<each B: Bundle>(_ bundles: repeat each B, checkedInto entity: Entity) throws(StaleEntity) {
        guard contains(entity) else { throw StaleEntity() }
        for bundle in repeat each bundles {
            bundle.insert(into: entity, in: &self)
        }
        for bundle in repeat each bundles {
            bundle._insertRequired(into: entity, in: &self)
        }
        endOperation()
    }

    /// Removes and returns the component of the given type that an entity holds.
    ///
    /// The entity stays live and keeps its other components:
    ///
    /// ```swift
    /// var world = World()
    /// let ball = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    ///
    /// if let velocity = world.remove(Velocity.self, from: ball) {
    ///     print(velocity.dx)
    ///     // Prints "1.0"
    /// }
    /// print(world.contains(Velocity.self, in: ball))
    /// // Prints "false"
    /// ```
    ///
    /// To remove every component of a ``Bundle`` at once, pass the bundle's type to
    /// ``remove(_:from:)-9j0yg``.
    ///
    /// - Parameters:
    ///   - type: The type of the component to remove.
    ///   - entity: The entity to remove it from.
    /// - Returns: The component the entity held, or `nil` if it held none of type `type`.
    /// - Complexity: O(1). The last component of the type moves into the vacated position, so the
    ///   storage order of the others changes.
    /// - Precondition: `entity` is live. The checked spelling,
    ///   ``remove(_:checkedFrom:)-2af30``, throws instead.
    @inlinable
    @discardableResult
    public mutating func remove<C: Component>(_ type: C.Type, from entity: Entity) -> C? {
        precondition(contains(entity), "Removing a \(C.self) from stale entity \(entity)")
        defer { endOperation() }
        return discard(C.self, from: entity)
    }

    /// Removes and returns the component of the given type that an entity holds, throwing an
    /// error if the entity isn't live.
    ///
    /// - Parameters:
    ///   - type: The type of the component to remove.
    ///   - entity: The entity to remove it from.
    /// - Returns: The component the entity held, or `nil` if it held none of type `type`.
    /// - Throws: ``StaleEntity`` if `entity` isn't live. The world is unchanged.
    /// - Complexity: O(1).
    @inlinable
    @discardableResult
    public mutating func remove<C: Component>(_ type: C.Type, checkedFrom entity: Entity) throws(StaleEntity) -> C? {
        guard contains(entity) else { throw StaleEntity() }
        defer { endOperation() }
        return discard(C.self, from: entity)
    }

    /// Returns the number of entities that hold a component of the given type.
    ///
    /// The count includes entities that queries skip, such as ``Disabled`` ones:
    ///
    /// ```swift
    /// var world = World()
    /// world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    /// world.spawn(Position(x: 5, y: 5))
    ///
    /// print(world.count(of: Position.self))
    /// // Prints "2"
    /// print(world.count(of: Velocity.self))
    /// // Prints "1"
    /// ```
    ///
    /// - Parameter type: The component type to count.
    /// - Returns: The number of entities holding a component of type `type`.
    /// - Complexity: O(1).
    @inlinable
    public func count<C: Component>(of type: C.Type) -> Int {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return 0 }
        return unretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { $0.index.dense.count }
    }

    // MARK: Storage

    /// The column at `slot`, without retaining it; valid while this world is not changed.
    @inlinable
    @inline(__always)
    func unretainedColumn<C: Component>(at slot: Int, of type: C.Type) -> Unmanaged<Column<C>> {
        columns.withUnsafeBufferPointer { columns in
            Unmanaged.passUnretained(unsafeDowncast(columns[slot], to: Column<C>.self))
        }
    }

    @inlinable
    func column<C: Component>(of type: C.Type) -> Column<C>? {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return nil }
        return unsafeDowncast(columns[slot], to: Column<C>.self)
    }

    /// The `C` column's contents, empty if the world never stored a `C`.
    @inlinable
    func snapshot<C: Component>(of type: C.Type) -> ColumnSnapshot<C> {
        column(of: C.self)?.snapshot ?? ColumnSnapshot()
    }

    /// The column at `slot`, copied first if another world shares it, without retaining it; valid
    /// while this world is not changed otherwise.
    @inlinable
    @inline(__always)
    mutating func uniqueUnretainedColumn<C: Component>(at slot: Int, of type: C.Type) -> Unmanaged<Column<C>> {
        if !isKnownUniquelyReferenced(&columns[slot]) {
            copyColumn(at: slot)
        }
        let column = unretainedColumn(at: slot, of: C.self)
        column._withUnsafeGuaranteedRef { $0.writeVersion &+= 1 }
        return column
    }

    /// The column at `slot`, copied first if another world shares it.
    @inlinable
    mutating func uniqueColumn<C: Component>(at slot: Int, of type: C.Type) -> Column<C> {
        if !isKnownUniquelyReferenced(&columns[slot]) {
            copyColumn(at: slot)
        }
        let column = unsafeDowncast(columns[slot], to: Column<C>.self)
        column.writeVersion &+= 1
        return column
    }

    @inline(never)
    @usableFromInline
    mutating func copyColumn(at slot: Int) {
        columns[slot] = columns[slot].copy()
    }

    /// The slot of the `C` column, adding an empty column if the world has none.
    @inlinable
    mutating func columnSlot<C: Component>(of type: C.Type) -> Int {
        if let slot = columnPositions.position(of: ObjectIdentifier(C.self)) { return slot }
        columns.append(Column<C>())
        columnPositions.insert(ObjectIdentifier(C.self), at: columns.count - 1)
        return columns.count - 1
    }

    @inlinable
    mutating func store<C: Component>(_ component: C, for entity: Entity) {
        let tick = changeTick
        var isRelation = false
        var isIndexed = false
        let slot = columnSlot(of: C.self)
        let group = uniqueUnretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { column in
            isRelation = column.isRelation
            isIndexed = column.isIndexed
            if let position = column.index.position(of: entity) {
                column.values[position] = component
                column.index.ticks[position].changed = tick
                return -2
            } else {
                _ = column.index.append(entity, at: tick)
                column.values.append(component)
                return column.group
            }
        }
        let added = group != -2
        if group >= 0 {
            joinGroup(group, entity)
        }
        if added, !caches.isEmpty {
            refreshCaches(ObjectIdentifier(C.self), entity)
        }
        if isRelation {
            reindexTargets(C.self, of: entity)
        }
        if isIndexed {
            reindexValue(C.self, of: entity, stored: component, slot: slot)
        }
        if !hooks.isEmpty {
            fireInsertHooks(C.self, for: entity, added: added)
        }
    }

    /// Runs the hook calls the operation that is ending fired.
    @inlinable
    mutating func endOperation() {
        if !hooks.pending.isEmpty {
            runPendingHooks()
        }
    }

    @inlinable
    mutating func discard<C: Component>(_ type: C.Type, from entity: Entity) -> C? {
        guard let slot = columnPositions.position(of: ObjectIdentifier(C.self)) else { return nil }
        let group = unretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { $0.group }
        if group >= 0 {
            leaveGroup(group, entity)
        }
        guard let position = unretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef({ $0.index.position(of: entity) }) else {
            return nil
        }
        var isRelation = false
        var isIndexed = false
        let component = uniqueUnretainedColumn(at: slot, of: C.self)._withUnsafeGuaranteedRef { column in
            isRelation = column.isRelation
            isIndexed = column.isIndexed
            let component = column.values[position]
            column.swapRemove(at: position)
            return component
        }
        if !caches.isEmpty {
            refreshCaches(ObjectIdentifier(C.self), entity)
        }
        if isRelation {
            reindexTargets(C.self, of: entity)
        }
        if isIndexed {
            reindexValue(C.self, of: entity, stored: nil, slot: slot)
        }
        if !hooks.isEmpty {
            fireRemoveHooks(component, of: entity)
        }
        return component
    }

    @inlinable
    mutating func makeEntity() -> Entity {
        structureVersion &+= 1
        if let slot = vacant.popLast() {
            isLive[Int(slot)] = true
            return Entity(index: slot, generation: generations[Int(slot)])
        }
        precondition(generations.count < Int(UInt32.max), "A world holds at most \(UInt32.max) slots")
        generations.append(0)
        isLive.append(true)
        return Entity(index: UInt32(generations.count - 1), generation: 0)
    }

    /// Destroys `entity` and the sources whose relations despawn with it, one at a time rather
    /// than recursively.
    @inlinable
    mutating func destroyCascading(_ entity: Entity) {
        guard !relationIndexes.isEmpty || !observers.byEntity.isEmpty || !valueIndexes.isEmpty else {
            destroy(entity)
            return
        }
        var pending = [entity]
        destroyPending(&pending)
    }

    /// Destroys the entities of `pending`, last first, and the sources whose relations despawn
    /// with them.
    @usableFromInline
    @inline(never)
    mutating func destroyPending(_ pending: inout [Entity]) {
        while let next = pending.popLast() {
            guard contains(next) else { continue }
            if !relationIndexes.isEmpty {
                releaseRelations(of: next, cascade: &pending)
            }
            if !observers.byEntity.isEmpty {
                forgetObservers(of: next)
            }
            if !valueIndexes.isEmpty {
                leaveValueIndexes(next)
            }
            destroy(next)
        }
    }

    /// Destroys `entity` and every component it holds, after its relations are released.
    @usableFromInline
    mutating func destroy(_ entity: Entity) {
        structureVersion &+= 1
        if !groups.isEmpty {
            leaveGroups(entity)
        }
        if !caches.isEmpty {
            leaveCaches(entity)
        }
        if !hooks.isEmpty {
            fireDespawnHooks(for: entity)
        }
        for slot in columns.indices {
            let held = columns.withUnsafeBufferPointer { columns in
                Unmanaged.passUnretained(columns[slot])._withUnsafeGuaranteedRef { $0.index.position(of: entity) }
            }
            guard let position = held else { continue }
            if !isKnownUniquelyReferenced(&columns[slot]) {
                copyColumn(at: slot)
            }
            columns.withUnsafeBufferPointer { columns in
                Unmanaged.passUnretained(columns[slot])._withUnsafeGuaranteedRef { $0.swapRemove($0, position) }
            }
        }
        let slot = Int(entity.index)
        isLive[slot] = false
        generations[slot] = generations[slot] == Entity.pendingGeneration - 1 ? 0 : generations[slot] + 1
        vacant.append(entity.index)
    }
}

/// A sequence of the live entities of a world, in slot order.
///
/// You get an entities view from a world's ``World/entities`` property. The view holds a snapshot
/// of which entities were live when you read the property, and produces their handles lazily as
/// you iterate it:
///
/// ```swift
/// var world = World()
/// world.spawn(Position(x: 0, y: 0))
/// world.spawn(Health(current: 10))
///
/// let handles = world.entities.map(\.description)
/// print(handles)
/// // Prints "["0:0", "1:0"]"
/// ```
@frozen
public struct EntitiesView: Sequence, Sendable {
    @usableFromInline let generations: [UInt32]
    @usableFromInline let isLive: [Bool]

    @inlinable
    init(generations: [UInt32], isLive: [Bool]) {
        self.generations = generations
        self.isLive = isLive
    }

    /// An iterator over the live entities of a world, in slot order.
    @frozen
    public struct Iterator: IteratorProtocol {
        @usableFromInline let generations: [UInt32]
        @usableFromInline let isLive: [Bool]
        @usableFromInline var slot = 0

        @inlinable
        init(generations: [UInt32], isLive: [Bool]) {
            self.generations = generations
            self.isLive = isLive
        }

        /// Advances to the next live entity and returns it, or `nil` if there are no more.
        @inlinable
        public mutating func next() -> Entity? {
            while slot < isLive.count {
                defer { slot += 1 }
                if isLive[slot] { return Entity(index: UInt32(slot), generation: generations[slot]) }
            }
            return nil
        }
    }

    /// Returns an iterator over the live entities.
    @inlinable
    public func makeIterator() -> Iterator { Iterator(generations: generations, isLive: isLive) }
}
