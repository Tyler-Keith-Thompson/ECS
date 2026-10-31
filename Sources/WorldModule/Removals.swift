/// The event a world sends when an entity loses a `C`, by removal or despawn, once
/// ``World/trackRemovals(of:)`` has started recording them.
@frozen
public struct RemovedComponent<C: Component>: Event, Hashable {
    /// The entity that lost its `C`; no longer live if it was despawned.
    public let entity: Entity

    @inlinable
    public init(entity: Entity) {
        self.entity = entity
    }
}

extension World {
    /// Starts recording every entity that loses a `C` from now on, as a ``RemovedComponent``
    /// event; does nothing if they are already recorded.
    ///
    /// The record is an ``Events`` resource read with ``removed(_:by:)``, kept as events are: an
    /// ``updateEvents()`` drops the removals from before the previous one. Removing the hooks of
    /// `C` (``removeHooks(of:)``) stops the record.
    ///
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func trackRemovals<C: Component>(of type: C.Type) {
        guard !resources.contains(Events<RemovedComponent<C>>.self) else { return }
        resources.insert(Events<RemovedComponent<C>>())
        onRemove(C.self) { world, entity, _ in
            world.send(RemovedComponent<C>(entity: entity))
        }
    }

    /// The entities that lost a `C` since a reader of type `Reader` last asked, oldest first,
    /// starting the record (``trackRemovals(of:)``) if it has not started.
    ///
    /// An entity appears once per removal: removed, inserted and removed again, it appears twice.
    ///
    /// ```swift
    /// for entity in world.removed(Health.self, by: Healthbars.self) {
    ///     world.resources[HealthbarIndex.self].remove(entity)
    /// }
    /// ```
    ///
    /// - Complexity: O(*r*) for *r* removals returned.
    @inlinable
    public mutating func removed<C: Component, Reader>(_ type: C.Type, by reader: Reader.Type) -> [Entity] {
        trackRemovals(of: C.self)
        return readEvents(RemovedComponent<C>.self, by: Reader.self).map { $0.entity }
    }
}
