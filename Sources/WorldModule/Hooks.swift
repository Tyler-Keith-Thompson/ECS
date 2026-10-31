/// The hooks a world runs when components of a type are added, inserted or removed.
@usableFromInline
struct ComponentHooks: Sendable {
    @usableFromInline var onAdd: [@Sendable (inout World, Entity) -> Void] = []
    @usableFromInline var onInsert: [@Sendable (inout World, Entity) -> Void] = []
    @usableFromInline var onRemove: [@Sendable (inout World, Entity, any Component) -> Void] = []
    /// Reads the entity's component of the hooks' type, for removal hooks run by a despawn.
    @usableFromInline let read: @Sendable (World, Entity) -> (any Component)?

    @inlinable
    init<C: Component>(_ type: C.Type) {
        read = { world, entity in try? world[checked: C.self, of: entity] }
    }
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

    /// Runs `hook` whenever an entity gains a `C` it did not hold: by spawning, inserting or a
    /// command.
    ///
    /// Hooks run after the world operation that fired them has finished, in the order they were
    /// fired, so a hook sees every component a spawn or bundle insert gave. A change a hook makes
    /// fires hooks of its own, which run after the hooks already waiting.
    ///
    /// ```swift
    /// world.onAdd(Name.self) { world, entity in
    ///     world.resources[NameIndex.self].insert(world[Name.self, of: entity], for: entity)
    /// }
    /// ```
    ///
    /// Changes made in place, through the subscript or ``update(_:reading:where:body:)``, run no
    /// hooks; find them with change detection instead.
    ///
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func onAdd<C: Component>(_ type: C.Type, perform hook: @escaping @Sendable (inout World, Entity) -> Void) {
        hooks.register(C.self)
        hooks.byType[ObjectIdentifier(C.self)]!.onAdd.append(hook)
    }

    /// Runs `hook` whenever an entity is given a `C`, whether it is new or replaces one it held.
    ///
    /// Hooks run as ``onAdd(_:perform:)`` describes; for a new component, the add hooks run
    /// first.
    ///
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func onInsert<C: Component>(_ type: C.Type, perform hook: @escaping @Sendable (inout World, Entity) -> Void) {
        hooks.register(C.self)
        hooks.byType[ObjectIdentifier(C.self)]!.onInsert.append(hook)
    }

    /// Runs `hook` with the removed component whenever an entity loses a `C`: by removing it,
    /// removing a bundle that holds it or despawning the entity.
    ///
    /// Hooks run as ``onAdd(_:perform:)`` describes. The component is gone from the entity when
    /// the hook runs, and a despawned entity is no longer live.
    ///
    /// ```swift
    /// world.onRemove(Name.self) { world, entity, name in
    ///     world.resources[NameIndex.self].remove(name, for: entity)
    /// }
    /// ```
    ///
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func onRemove<C: Component>(_ type: C.Type, perform hook: @escaping @Sendable (inout World, Entity, C) -> Void) {
        hooks.register(C.self)
        hooks.byType[ObjectIdentifier(C.self)]!.onRemove.append { world, entity, component in
            hook(&world, entity, component as! C)
        }
    }

    /// Removes every hook registered for `C`.
    ///
    /// - Complexity: O(*h*) for *h* hooked types.
    @inlinable
    public mutating func removeHooks<C: Component>(of type: C.Type) {
        guard hooks.byType.removeValue(forKey: ObjectIdentifier(C.self)) != nil else { return }
        hooks.order.removeAll { $0 == ObjectIdentifier(C.self) }
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
            guard let typeHooks = hooks.byType[type], !typeHooks.onRemove.isEmpty,
                  let component = typeHooks.read(self, entity) else { continue }
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
