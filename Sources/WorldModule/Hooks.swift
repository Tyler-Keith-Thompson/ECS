/// The hooks a world runs when components of a type are added, inserted or removed.
@usableFromInline
struct ComponentHooks: Sendable {
    @usableFromInline var onAdd: [@Sendable (inout World, Entity) -> Void] = []
    @usableFromInline var onInsert: [@Sendable (inout World, Entity) -> Void] = []
    @usableFromInline var onRemove: [@Sendable (inout World, Entity, any Component) -> Void] = []
    /// Reads the entity's component of the hooks' type, for removal hooks run by a despawn.
    @usableFromInline let read: @Sendable (World, Entity) -> (any Component)?
    /// Whether removals of the type are recorded as `RemovedComponent` events
    /// (``World/trackRemovals(of:)``), which removing the type's hooks leaves in place.
    @usableFromInline var tracksRemovals = false
    /// Records that the entity lost its component of the hooks' type.
    @usableFromInline let recordRemoval: @Sendable (inout World, Entity) -> Void

    @inlinable
    init<C: Component>(_ type: C.Type) {
        read = { world, entity in try? world[checked: C.self, of: entity] }
        recordRemoval = { world, entity in world.send(RemovedComponent<C>(entity: entity)) }
    }

    /// Whether losing a component of the type has anything to run.
    @inlinable
    var hasRemovalWork: Bool { tracksRemovals || !onRemove.isEmpty }
}

/// Every hook of a world, and the hook calls waiting for the operation that fired them to end.
@usableFromInline
struct Hooks: Sendable {
    @usableFromInline var byType: [ObjectIdentifier: ComponentHooks] = [:]
    /// The hooked types in the order their first hook was registered.
    @usableFromInline var order: [ObjectIdentifier] = []
    /// Hook calls fired and not yet run, in the order they were fired.
    @usableFromInline var pending: [@Sendable (inout World) -> Void] = []
    /// Whether the world is running pending calls, so operations made by hooks leave the calls
    /// they fire to that loop.
    @usableFromInline var isRunning = false

    @usableFromInline
    init() {}

    @inlinable
    var isEmpty: Bool { byType.isEmpty }

    /// Records `C` as hooked, with no hooks yet if it had none.
    @inlinable
    mutating func register<C: Component>(_ type: C.Type) {
        guard byType[ObjectIdentifier(C.self)] == nil else { return }
        byType[ObjectIdentifier(C.self)] = ComponentHooks(C.self)
        order.append(ObjectIdentifier(C.self))
    }
}

extension World {
    // MARK: Hooks

    /// Registers a closure to run whenever an entity gains a component of the given type.
    ///
    /// Use hooks to keep data outside the components in step with them, such as an index of
    /// entities by name. An *add hook* runs when an entity that didn't hold a `C` gets one, by
    /// spawning, inserting or applying a command. Replacing a `C` the entity already holds
    /// doesn't run it; see ``onInsert(_:perform:)`` for a hook that runs then too.
    ///
    /// The following example records each named entity in a resource as it's spawned:
    ///
    /// ```swift
    /// struct NameDirectory: Resource { var entities: [String: Entity] = [:] }
    ///
    /// var world = World()
    /// world.resources.insert(NameDirectory())
    /// world.onAdd(Name.self) { world, entity in
    ///     let name = world[Name.self, of: entity].value
    ///     world.resources[NameDirectory.self].entities[name] = entity
    /// }
    ///
    /// let hero = world.spawn(Name(value: "Hero"))
    /// print(world.resources[NameDirectory.self].entities["Hero"] == hero)
    /// // Prints "true"
    /// ```
    ///
    /// A hook runs after the world operation that fired it has finished, so it sees every
    /// component a spawn or bundle insert gave. Hooks run in the order they were fired. A change
    /// that a hook makes fires hooks of its own, which run after the hooks already waiting.
    ///
    /// - Note: Changes made in place, through the world's subscript or an update, run no hooks.
    ///   Find those with change detection instead.
    ///
    /// - Parameters:
    ///   - type: The component type to watch.
    ///   - hook: The closure to run, given the world and the entity that gained a `C`.
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func onAdd<C: Component>(_ type: C.Type, perform hook: @escaping @Sendable (inout World, Entity) -> Void) {
        hooks.register(C.self)
        hooks.byType[ObjectIdentifier(C.self)]!.onAdd.append(hook)
    }

    /// Registers a closure to run whenever an entity is given a component of the given type,
    /// whether it's new or replaces one the entity held.
    ///
    /// Insert hooks run at the same point add hooks do (see `onAdd(_:perform:)`). For a new
    /// component, the add hooks run first.
    ///
    /// The following example counts every insert of a `Health` component, and shows that a
    /// change made in place doesn't run the hook:
    ///
    /// ```swift
    /// struct HealthWrites: Resource { var count = 0 }
    ///
    /// var world = World()
    /// world.resources.insert(HealthWrites())
    /// world.onInsert(Health.self) { world, _ in
    ///     world.resources[HealthWrites.self].count += 1
    /// }
    ///
    /// let knight = world.spawn(Health(current: 10))
    /// world.insert(Health(current: 8), into: knight)
    /// world[Health.self, of: knight].current -= 1
    /// print(world.resources[HealthWrites.self].count)
    /// // Prints "2"
    /// ```
    ///
    /// - Parameters:
    ///   - type: The component type to watch.
    ///   - hook: The closure to run, given the world and the entity that was given a `C`.
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func onInsert<C: Component>(_ type: C.Type, perform hook: @escaping @Sendable (inout World, Entity) -> Void) {
        hooks.register(C.self)
        hooks.byType[ObjectIdentifier(C.self)]!.onInsert.append(hook)
    }

    /// Registers a closure to run whenever an entity loses a component of the given type.
    ///
    /// A *remove hook* runs when an entity loses its `C` by removing it, removing a bundle that
    /// holds it, or being despawned. The hook receives the removed component, since it's gone
    /// from the entity by the time the hook runs; after a despawn, the entity is no longer live.
    /// Remove hooks run at the same point add hooks do (see `onAdd(_:perform:)`).
    ///
    /// The following example keeps a directory of named entities in step as they're despawned:
    ///
    /// ```swift
    /// var world = World()
    /// world.resources.insert(NameDirectory())
    /// world.onAdd(Name.self) { world, entity in
    ///     let name = world[Name.self, of: entity].value
    ///     world.resources[NameDirectory.self].entities[name] = entity
    /// }
    /// world.onRemove(Name.self) { world, _, name in
    ///     world.resources[NameDirectory.self].entities[name.value] = nil
    /// }
    ///
    /// let villain = world.spawn(Name(value: "Villain"))
    /// world.despawn(villain)
    /// print(world.resources[NameDirectory.self].entities.isEmpty)
    /// // Prints "true"
    /// ```
    ///
    /// - Parameters:
    ///   - type: The component type to watch.
    ///   - hook: The closure to run, given the world, the entity that lost its `C` and the
    ///     component it lost.
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func onRemove<C: Component>(_ type: C.Type, perform hook: @escaping @Sendable (inout World, Entity, C) -> Void) {
        hooks.register(C.self)
        hooks.byType[ObjectIdentifier(C.self)]!.onRemove.append { world, entity, component in
            hook(&world, entity, component as! C)
        }
    }

    /// Removes every hook registered for a component type.
    ///
    /// This removes the add, insert and remove hooks of `C`. A record of the removals of `C`
    /// (``trackRemovals(of:)``) isn't a hook, and keeps recording.
    ///
    /// - Parameter type: The component type whose hooks to remove.
    /// - Complexity: O(*h*), where *h* is the number of hooked component types.
    @inlinable
    public mutating func removeHooks<C: Component>(of type: C.Type) {
        guard let removed = hooks.byType.removeValue(forKey: ObjectIdentifier(C.self)) else { return }
        guard removed.tracksRemovals else {
            hooks.order.removeAll { $0 == ObjectIdentifier(C.self) }
            return
        }
        var tracking = ComponentHooks(C.self)
        tracking.tracksRemovals = true
        hooks.byType[ObjectIdentifier(C.self)] = tracking
    }

    /// Queues the hooks for `entity` having been given a `C`, new when `added`.
    @usableFromInline
    @inline(never)
    mutating func fireInsertHooks<C: Component>(_ type: C.Type, for entity: Entity, added: Bool) {
        guard let typeHooks = hooks.byType[ObjectIdentifier(C.self)] else { return }
        if added {
            for hook in typeHooks.onAdd {
                hooks.pending.append { world in hook(&world, entity) }
            }
        }
        for hook in typeHooks.onInsert {
            hooks.pending.append { world in hook(&world, entity) }
        }
    }

    /// Queues the hooks for `entity` having lost `component`.
    @usableFromInline
    @inline(never)
    mutating func fireRemoveHooks<C: Component>(_ component: C, of entity: Entity) {
        guard let typeHooks = hooks.byType[ObjectIdentifier(C.self)] else { return }
        if typeHooks.tracksRemovals {
            let record = typeHooks.recordRemoval
            hooks.pending.append { world in record(&world, entity) }
        }
        for hook in typeHooks.onRemove {
            hooks.pending.append { world in hook(&world, entity, component) }
        }
    }

    /// Queues the removal hooks for every hooked component `entity` holds, before it is
    /// despawned.
    @usableFromInline
    @inline(never)
    mutating func fireDespawnHooks(for entity: Entity) {
        for type in hooks.order {
            guard let typeHooks = hooks.byType[type], typeHooks.hasRemovalWork,
                  let component = typeHooks.read(self, entity) else { continue }
            if typeHooks.tracksRemovals {
                let record = typeHooks.recordRemoval
                hooks.pending.append { world in record(&world, entity) }
            }
            for hook in typeHooks.onRemove {
                hooks.pending.append { world in hook(&world, entity, component) }
            }
        }
    }

    /// Runs the queued hook calls, unless the world is already running them.
    @usableFromInline
    @inline(never)
    mutating func runPendingHooks() {
        guard !hooks.isRunning else { return }
        hooks.isRunning = true
        var next = 0
        while next < hooks.pending.count {
            let call = hooks.pending[next]
            next += 1
            call(&self)
        }
        hooks.pending.removeAll()
        hooks.isRunning = false
    }
}
