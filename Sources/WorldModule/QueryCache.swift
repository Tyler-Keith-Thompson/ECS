/// The entities meeting a cached query's structural conditions, kept current as components are
/// added and removed.
///
/// The conditions are the query's component terms and the types its filter requires, excludes or
/// skips by default, and the filter's groups of alternatives that name no change ticks. A visit
/// whose own conditions imply these may walk the cached entities instead of a column: every
/// entity it matches is among them.
@usableFromInline
struct QueryCache: Sendable {
    /// Which cache this is, the same in every copy of the world that made it.
    @usableFromInline let identifier: Int
    @usableFromInline let required: [ObjectIdentifier]
    @usableFromInline let excluded: [ObjectIdentifier]
    @usableFromInline let alternatives: [[QueryFilter]]
    /// Every type whose presence decides whether an entity is cached.
    @usableFromInline let types: Set<ObjectIdentifier>
    /// The cached entities.
    @usableFromInline var entities = SparseIndex()
    /// Whether a part merged back changed the entities' components, so `entities` waits to be
    /// rebuilt and no visit uses it.
    @usableFromInline var isStale = false
    /// Hooks run when an entity starts or stops meeting the conditions.
    @usableFromInline var onAdd: [@Sendable (inout World, Entity) -> Void] = []
    @usableFromInline var onRemove: [@Sendable (inout World, Entity) -> Void] = []

    @inlinable
    init(identifier: Int, required: [ObjectIdentifier], excluded: [ObjectIdentifier], alternatives: [[QueryFilter]]) {
        self.identifier = identifier
        self.required = required
        self.excluded = excluded
        self.alternatives = alternatives
        var types = Set(required).union(excluded)
        for group in alternatives {
            for filter in group {
                filter.collectTypes(into: &types)
            }
        }
        self.types = types
    }

    /// Whether `other` caches the same entities.
    @inlinable
    func hasConditions(of other: QueryCache) -> Bool {
        Set(required) == Set(other.required) && Set(excluded) == Set(other.excluded) && alternatives == other.alternatives
    }

    /// Whether every entity a visit with these conditions matches is cached: the visit requires
    /// every type the cache requires, excludes every type it excludes, and has each of its
    /// groups of alternatives.
    @inlinable
    func isImplied(required visitRequired: [ObjectIdentifier], excluded visitExcluded: [ObjectIdentifier], alternatives visitAlternatives: [[QueryFilter]]) -> Bool {
        required.allSatisfy(visitRequired.contains) && excluded.allSatisfy(visitExcluded.contains)
            && alternatives.allSatisfy(visitAlternatives.contains)
    }
}

extension QueryFilter {
    /// Whether the filter names no change tick, in itself or any alternative, so whether it
    /// passes depends only on which types an entity holds.
    @inlinable
    var isStructural: Bool {
        addedSince.isEmpty && changedSince.isEmpty && related.isEmpty && alternatives.allSatisfy { $0.allSatisfy(\.isStructural) }
    }

    /// Adds every type the filter requires or excludes, in itself or any alternative.
    @inlinable
    func collectTypes(into types: inout Set<ObjectIdentifier>) {
        types.formUnion(required)
        types.formUnion(excluded)
        for group in alternatives {
            for filter in group {
                filter.collectTypes(into: &types)
            }
        }
    }
}

extension World {
    // MARK: Cached queries

    /// Keeps a list of the entities that match a query's structure, so that queries and updates
    /// with the same conditions visit only those entities.
    ///
    /// A query normally walks the storage of one of its types and checks every entity there
    /// against the rest of its conditions. When few of those entities match, most of that walk is
    /// wasted. A cached query keeps the matching entities in a list of their own, kept current as
    /// you spawn, insert, remove and despawn, so a visit can walk that list instead.
    ///
    /// Use a cache for a query you run often whose conditions exclude most of the entities it
    /// would otherwise walk, such as the few entities that are awake among many asleep:
    ///
    /// ```swift
    /// struct Asleep: Component {}
    /// ```
    ///
    /// ```swift
    /// var world = World()
    /// let awake = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
    /// let sleeper = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Asleep())
    ///
    /// world.cache(Query(Position.self, Velocity.self).without(Asleep.self))
    ///
    /// world.update(Position.self, reading: Velocity.self, where: .without(Asleep.self)) { position, row in
    ///     position.x += row.components.dx
    /// }
    /// print(world[Position.self, of: awake].x, world[Position.self, of: sleeper].x)
    /// // Prints "1.0 0.0"
    /// ```
    ///
    /// The cache holds the entities that hold every component term of `query` and every type its
    /// filter requires, hold none of the types it excludes or skips by default (such as
    /// ``Disabled``), and pass its groups of alternatives that name no change ticks. A query or
    /// update uses the cache when its own conditions imply the cache's: it requires every type the
    /// cache requires, excludes every type the cache excludes, and has the same groups of
    /// alternatives. It walks the cache only when the cache is smaller than the storage it would
    /// otherwise walk. A cache never changes which entities a visit finds, only how it finds them.
    ///
    /// ``AnyOf`` terms, change-tick filters and relation filters don't narrow the cache; a visit
    /// still checks them for each cached entity. Caching the same conditions twice keeps one
    /// cache. A copy of the world keeps its caches; a snapshot doesn't.
    ///
    /// - Parameter query: The query whose matching entities to keep.
    /// - Complexity: O(*n*·*t*) for *n* entities in the smallest required type, or every live
    ///   entity when the query requires none, and *t* conditions. Each cache adds O(*t*) to adding
    ///   or removing a component of a type it names.
    @inlinable
    public mutating func cache<each T: QueryTerm>(_ query: Query<repeat each T>) {
        _ = cachePosition(of: query)
    }

    /// The position in ``caches`` of the cache of `query`'s conditions, made if there is none.
    @inlinable
    mutating func cachePosition<each T: QueryTerm>(of query: Query<repeat each T>) -> Int {
        var required: [ObjectIdentifier] = []
        for term in repeat (each T).self {
            if let type = term._termReader(in: self).required, !required.contains(type) {
                required.append(type)
            }
        }
        let filter = query.filter
        for type in filter.required where !required.contains(type) {
            required.append(type)
        }
        var excluded = filter.excluded
        for type in disablingComponents where !required.contains(type) && !filter.mentions(type) && !excluded.contains(type) {
            excluded.append(type)
        }
        let alternatives = filter.alternatives.filter { $0.allSatisfy(\.isStructural) }
        var cache = QueryCache(identifier: caches.count, required: required, excluded: excluded, alternatives: alternatives)
        if let existing = caches.firstIndex(where: { $0.hasConditions(of: cache) }) {
            return existing
        }
        var smallest: [Entity]?
        for type in required {
            let entities = columnPositions.position(of: type).map { columns[$0].index.dense } ?? []
            if smallest == nil || entities.count < smallest!.count {
                smallest = entities
            }
        }
        for entity in smallest ?? Array(entities) where meets(cache, entity) {
            _ = cache.entities.append(entity, at: .zero)
        }
        caches.append(cache)
        return caches.count - 1
    }

    /// Whether `entity` meets the conditions of `cache`.
    @inlinable
    func meets(_ cache: QueryCache, _ entity: Entity) -> Bool {
        for type in cache.required where !holds(type, entity) { return false }
        for type in cache.excluded where holds(type, entity) { return false }
        for group in cache.alternatives where !group.contains(where: { passesStructurally($0, entity) }) { return false }
        return true
    }

    @inlinable
    func holds(_ type: ObjectIdentifier, _ entity: Entity) -> Bool {
        guard let slot = columnPositions.position(of: type) else { return false }
        return columns[slot].index.position(of: entity) != nil
    }

    @inlinable
    func passesStructurally(_ filter: QueryFilter, _ entity: Entity) -> Bool {
        for type in filter.required where !holds(type, entity) { return false }
        for type in filter.excluded where holds(type, entity) { return false }
        for group in filter.alternatives where !group.contains(where: { passesStructurally($0, entity) }) { return false }
        return true
    }

    /// Brings every cache naming `type` up to date for `entity`, which gained or lost a `type`.
    ///
    /// A part split off for a concurrent change cannot see every column, so it drops those
    /// caches instead; merging the part rebuilds them.
    @usableFromInline
    @inline(never)
    mutating func refreshCaches(_ type: ObjectIdentifier, _ entity: Entity) {
        guard refreshesCaches else {
            caches.removeAll { $0.types.contains(type) }
            return
        }
        for index in caches.indices where !caches[index].isStale && caches[index].types.contains(type) {
            let isMet = meets(caches[index], entity)
            let position = caches[index].entities.position(of: entity)
            if isMet, position == nil {
                _ = caches[index].entities.append(entity, at: .zero)
                for hook in caches[index].onAdd {
                    hooks.pending.append { world in hook(&world, entity) }
                }
            } else if !isMet, let position {
                caches[index].entities.swapRemove(at: position)
                for hook in caches[index].onRemove {
                    hooks.pending.append { world in hook(&world, entity) }
                }
            }
        }
    }

    /// Removes `entity`, which is being despawned, from every cache.
    @usableFromInline
    @inline(never)
    mutating func leaveCaches(_ entity: Entity) {
        for index in caches.indices {
            if let position = caches[index].entities.position(of: entity) {
                caches[index].entities.swapRemove(at: position)
                for hook in caches[index].onRemove {
                    hooks.pending.append { world in hook(&world, entity) }
                }
            }
        }
    }

    /// Marks stale the caches `part`, a part of this world, dropped because it added or removed
    /// components of a type they name.
    @usableFromInline
    mutating func markCachesStale(droppedBy part: World) {
        guard part.caches.count != caches.count else { return }
        let kept = Set(part.caches.map(\.identifier))
        for index in caches.indices where !kept.contains(caches[index].identifier) {
            caches[index].isStale = true
        }
    }

    /// Refills the stale caches, once every split part is merged back and every column is here.
    @usableFromInline
    mutating func rebuildStaleCaches() {
        guard splitParts == 0 else { return }
        for index in caches.indices where caches[index].isStale {
            var entities = SparseIndex()
            for entity in self.entities where meets(caches[index], entity) {
                _ = entities.append(entity, at: .zero)
            }
            let old = caches[index].entities
            caches[index].entities = entities
            caches[index].isStale = false
            for entity in entities.dense where old.position(of: entity) == nil {
                for hook in caches[index].onAdd {
                    hooks.pending.append { world in hook(&world, entity) }
                }
            }
            for entity in old.dense where entities.position(of: entity) == nil {
                for hook in caches[index].onRemove {
                    hooks.pending.append { world in hook(&world, entity) }
                }
            }
        }
        endOperation()
    }

    /// The entities of the smallest cache whose conditions a visit's imply, or nil.
    @inlinable
    func cachedEntities(required: [ObjectIdentifier], excluded: [ObjectIdentifier], alternatives: [[QueryFilter]]) -> SparseIndex? {
        var best: SparseIndex?
        for cache in caches where !cache.isStale && cache.isImplied(required: required, excluded: excluded, alternatives: alternatives) {
            if best == nil || cache.entities.dense.count < best!.dense.count {
                best = cache.entities
            }
        }
        return best
    }
}
