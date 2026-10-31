/// The event a world sends when an entity loses a component of type `C`.
///
/// A world sends these events only for the component types whose removals it records; start
/// recording with ``World/trackRemovals(of:)``. The usual way to read them is
/// ``World/removed(_:by:)``, which starts the recording for you. The events are kept as any
/// other ``Event`` is, and read the same way:
///
/// ```swift
/// enum CleanupReader {}
///
/// var world = World()
/// world.trackRemovals(of: Health.self)
/// let knight = world.spawn(Health(current: 10))
/// world.despawn(knight)
///
/// let losses = world.readEvents(RemovedComponent<Health>.self, by: CleanupReader.self)
/// print(losses.map(\.entity) == [knight])
/// // Prints "true"
/// ```
@frozen
public struct RemovedComponent<C: Component>: Event, Hashable {
    /// The entity that lost its component, which is no longer live if it was despawned.
    public let entity: Entity

    /// Creates the event for an entity that lost its component.
    ///
    /// - Parameter entity: The entity that lost its component.
    @inlinable
    public init(entity: Entity) {
        self.entity = entity
    }
}

extension World {
    /// Starts recording every entity that loses a component of the given type.
    ///
    /// From now on, each removal or despawn that takes a `C` from an entity sends a
    /// ``RemovedComponent`` event. Read the record with ``removed(_:by:)``. It's kept as events
    /// are, so each ``updateEvents()`` drops the removals from before the previous one. Calling
    /// this method again for the same type does nothing.
    ///
    /// The record isn't one of the type's hooks: removing the hooks of `C`
    /// (``removeHooks(of:)``) leaves it in place.
    ///
    /// - Parameter type: The component type whose removals to record.
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func trackRemovals<C: Component>(of type: C.Type) {
        hooks.register(C.self)
        guard !hooks.byType[ObjectIdentifier(C.self)]!.tracksRemovals else { return }
        hooks.byType[ObjectIdentifier(C.self)]!.tracksRemovals = true
        if !resources.contains(Events<RemovedComponent<C>>.self) {
            resources.insert(Events<RemovedComponent<C>>())
        }
    }

    /// Returns the entities that lost a component of the given type since a reader last asked,
    /// oldest first.
    ///
    /// Use this method to clean up after components that are gone, such as removing an
    /// entity's health bar when it loses its `Health`. The first call for a type starts recording
    /// its removals (``trackRemovals(of:)``), so removals made before it aren't reported. Each
    /// reader type has its own place in the record, as with ``readEvents(_:by:)``.
    ///
    /// ```swift
    /// enum HealthbarReader {}
    ///
    /// var world = World()
    /// _ = world.removed(Health.self, by: HealthbarReader.self)
    ///
    /// let knight = world.spawn(Health(current: 10))
    /// let archer = world.spawn(Health(current: 6))
    /// world.remove(Health.self, from: archer)
    /// world.despawn(knight)
    ///
    /// let lost = world.removed(Health.self, by: HealthbarReader.self)
    /// print(lost == [archer, knight])
    /// // Prints "true"
    /// ```
    ///
    /// An entity appears once per removal: an entity whose `C` is removed, inserted and removed
    /// again appears twice.
    ///
    /// - Parameters:
    ///   - type: The component type whose removals to report.
    ///   - reader: The type that identifies the reader.
    /// - Returns: The entities that lost a `C` since `reader` last asked.
    /// - Complexity: O(*r*), where *r* is the number of removals returned.
    @inlinable
    public mutating func removed<C: Component, Reader>(_ type: C.Type, by reader: Reader.Type) -> [Entity] {
        trackRemovals(of: C.self)
        return readEvents(RemovedComponent<C>.self, by: Reader.self).map { $0.entity }
    }
}
