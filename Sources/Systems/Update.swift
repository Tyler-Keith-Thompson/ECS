import WorldModule

// The Update system parameters: one to three written types, each optionally reading terms
// (`Over`) and filtered (`Where`). A visit with terms runs through a closure its call site
// builds, so the overload for the query's shape reads the rows.

/// The query of `terms` with `filter`; with no terms, a query of none, which a call cannot
/// otherwise spell.
@inlinable
func filteredQuery<each T: QueryTerm>(_ terms: repeat (each T).Type, filter: QueryFilter) -> Query<repeat each T> {
    Query(repeat each terms).filtered(by: filter)
}

/// Writes `A` of every entity holding them.
///
/// ```swift
/// @System
/// struct Movement {
///     func run(_ movers: Update<Position>.Over<Velocity>.Where<Without<Frozen>>) {
///         movers { position, row in position.x += row.components.dx }
///     }
/// }
/// ```
///
/// `And<B>` and `And<B>.And<C>` write two and three types; `Over<…>` reads terms alongside, as
/// ``WorldModule/World/update(_:over:body:)`` does; `Where<…>` filters the entities. Every
/// written component visited is marked changed.
public final class Update<A: Component>: SystemParameter, @unchecked Sendable {
    /// What the visit calls for each entity.
    public typealias Body = (inout A, Entity) -> Void

    @usableFromInline var part: World

    @inlinable
    init(part: World) {
        self.part = part
    }

    @inlinable
    public static func _access<S>(in system: S.Type) -> Access {
        return Access.writes(A.self)
    }

    /// Takes the written columns out of `world` until ``_restore(into:)``.
    @inlinable
    public static func _fetch(from world: inout World) -> Self {
        Self(part: world.split(writing: _access(in: Self.self)))
    }

    /// Puts the written columns back into `world`.
    @inlinable
    public func _restore(into world: inout World) {
        world.merge(writing: Self._access(in: Self.self), from: part)
    }

    /// Visits every matching entity once, calling `body` with its written components.
    @inlinable
    public func callAsFunction(_ body: Body) {
        part.update(A.self, where: QueryFilter()) { a, row in body(&a, row.entity) }
    }

    /// Writes `A` of every entity holding them, and passing the filter types `F`.
    public final class Where<each F: FilterTerm>: SystemParameter, @unchecked Sendable {
        /// What the visit calls for each entity.
        public typealias Body = (inout A, Entity) -> Void

        @usableFromInline var part: World

        @inlinable
        init(part: World) {
            self.part = part
        }

        /// The filter the filter types stand for, every one applied.
        public static var filter: QueryFilter {
            var filter = QueryFilter()
            for type in repeat (each F).self {
                filter = filter.merging(type.filter)
            }
            return filter
        }

        @inlinable
        public static func _access<S>(in system: S.Type) -> Access {
            var access = Access.writes(A.self)
            for type in repeat (each F).self {
                access = type._reading(access)
            }
            return access
        }

        /// Takes the written columns out of `world` until ``_restore(into:)``.
        @inlinable
        public static func _fetch(from world: inout World) -> Self {
            Self(part: world.split(writing: _access(in: Self.self)))
        }

        /// Puts the written columns back into `world`.
        @inlinable
        public func _restore(into world: inout World) {
            world.merge(writing: Self._access(in: Self.self), from: part)
        }

        /// Visits every matching entity once, calling `body` with its written components.
        @inlinable
        public func callAsFunction(_ body: Body) {
            part.update(A.self, where: Self.filter) { a, row in body(&a, row.entity) }
        }
    }

    /// Writes `A` of every entity holding them and matching the terms `T`, which it reads.
    public final class Over<each T: QueryTerm>: SystemParameter, @unchecked Sendable {
        /// What the visit calls for each entity.
        public typealias Body = (inout A, QueryRow<repeat (each T).Value>) -> Void

        @usableFromInline var part: World
        @usableFromInline let run: (inout World, Query<repeat each T>, Body) -> Void

        @inlinable
        init(part: World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void) {
            self.part = part
            self.run = run
        }

        @inlinable
        public static func _access<S>(in system: S.Type) -> Access {
            var access = Access.writes(A.self)
            for type in repeat (each T).self {
                access = type._reading(access)
            }
            return access
        }

        /// Takes the written columns out of `world` until ``_restore(into:)``, visiting through
        /// `run`, which a call site that knows the types writes as
        /// `{ world, query, body in world.update(A.self, over: query, body: body) }` so the overload for the query's shape runs.
        @inlinable
        public static func _fetch(
            from world: inout World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void
        ) -> Self {
            Self(part: world.split(writing: _access(in: Self.self)), run: run)
        }

        /// Takes the written columns out of `world` until ``_restore(into:)``.
        @inlinable
        public static func _fetch(from world: inout World) -> Self {
            _fetch(from: &world) { world, query, body in world.update(A.self, over: query, body: body) }
        }

        /// Puts the written columns back into `world`.
        @inlinable
        public func _restore(into world: inout World) {
            world.merge(writing: Self._access(in: Self.self), from: part)
        }

        /// Visits every matching entity once, calling `body` with its written components.
        @inlinable
        public func callAsFunction(_ body: Body) {
            run(&part, Query(filter: QueryFilter()), body)
        }

        /// Writes `A` of every entity holding them and matching the terms `T`, which it reads, and passing the filter types `F`.
        public final class Where<each F: FilterTerm>: SystemParameter, @unchecked Sendable {
            /// What the visit calls for each entity.
            public typealias Body = (inout A, QueryRow<repeat (each T).Value>) -> Void

            @usableFromInline var part: World
            @usableFromInline let run: (inout World, Query<repeat each T>, Body) -> Void

            @inlinable
            init(part: World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void) {
                self.part = part
                self.run = run
            }

            /// The filter the filter types stand for, every one applied.
            public static var filter: QueryFilter {
                var filter = QueryFilter()
                for type in repeat (each F).self {
                    filter = filter.merging(type.filter)
                }
                return filter
            }

            @inlinable
            public static func _access<S>(in system: S.Type) -> Access {
                var access = Access.writes(A.self)
                for type in repeat (each T).self {
                    access = type._reading(access)
                }
                for type in repeat (each F).self {
                    access = type._reading(access)
                }
                return access
            }

            /// Takes the written columns out of `world` until ``_restore(into:)``, visiting through
            /// `run`, which a call site that knows the types writes as
            /// `{ world, query, body in world.update(A.self, over: query, body: body) }` so the overload for the query's shape runs.
            @inlinable
            public static func _fetch(
                from world: inout World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void
            ) -> Self {
                Self(part: world.split(writing: _access(in: Self.self)), run: run)
            }

            /// Takes the written columns out of `world` until ``_restore(into:)``.
            @inlinable
            public static func _fetch(from world: inout World) -> Self {
                _fetch(from: &world) { world, query, body in world.update(A.self, over: query, body: body) }
            }

            /// Puts the written columns back into `world`.
            @inlinable
            public func _restore(into world: inout World) {
                world.merge(writing: Self._access(in: Self.self), from: part)
            }

            /// Visits every matching entity once, calling `body` with its written components.
            @inlinable
            public func callAsFunction(_ body: Body) {
                run(&part, Query(filter: Self.filter), body)
            }
        }
    }

    /// Writes `A`, `B` of every entity holding them.
    public final class And<B: Component>: SystemParameter, @unchecked Sendable {
        /// What the visit calls for each entity.
        public typealias Body = (inout A, inout B, Entity) -> Void

        @usableFromInline var part: World

        @inlinable
        init(part: World) {
            self.part = part
        }

        @inlinable
        public static func _access<S>(in system: S.Type) -> Access {
            return Access.writes(A.self, B.self)
        }

        /// Takes the written columns out of `world` until ``_restore(into:)``.
        @inlinable
        public static func _fetch(from world: inout World) -> Self {
            Self(part: world.split(writing: _access(in: Self.self)))
        }

        /// Puts the written columns back into `world`.
        @inlinable
        public func _restore(into world: inout World) {
            world.merge(writing: Self._access(in: Self.self), from: part)
        }

        /// Visits every matching entity once, calling `body` with its written components.
        @inlinable
        public func callAsFunction(_ body: Body) {
            part.update(A.self, B.self, where: QueryFilter()) { a, b, row in body(&a, &b, row.entity) }
        }

        /// Writes `A`, `B` of every entity holding them, and passing the filter types `F`.
        public final class Where<each F: FilterTerm>: SystemParameter, @unchecked Sendable {
            /// What the visit calls for each entity.
            public typealias Body = (inout A, inout B, Entity) -> Void

            @usableFromInline var part: World

            @inlinable
            init(part: World) {
                self.part = part
            }

            /// The filter the filter types stand for, every one applied.
            public static var filter: QueryFilter {
                var filter = QueryFilter()
                for type in repeat (each F).self {
                    filter = filter.merging(type.filter)
                }
                return filter
            }

            @inlinable
            public static func _access<S>(in system: S.Type) -> Access {
                var access = Access.writes(A.self, B.self)
                for type in repeat (each F).self {
                    access = type._reading(access)
                }
                return access
            }

            /// Takes the written columns out of `world` until ``_restore(into:)``.
            @inlinable
            public static func _fetch(from world: inout World) -> Self {
                Self(part: world.split(writing: _access(in: Self.self)))
            }

            /// Puts the written columns back into `world`.
            @inlinable
            public func _restore(into world: inout World) {
                world.merge(writing: Self._access(in: Self.self), from: part)
            }

            /// Visits every matching entity once, calling `body` with its written components.
            @inlinable
            public func callAsFunction(_ body: Body) {
                part.update(A.self, B.self, where: Self.filter) { a, b, row in body(&a, &b, row.entity) }
            }
        }

        /// Writes `A`, `B` of every entity holding them and matching the terms `T`, which it reads.
        public final class Over<each T: QueryTerm>: SystemParameter, @unchecked Sendable {
            /// What the visit calls for each entity.
            public typealias Body = (inout A, inout B, QueryRow<repeat (each T).Value>) -> Void

            @usableFromInline var part: World
            @usableFromInline let run: (inout World, Query<repeat each T>, Body) -> Void

            @inlinable
            init(part: World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void) {
                self.part = part
                self.run = run
            }

            @inlinable
            public static func _access<S>(in system: S.Type) -> Access {
                var access = Access.writes(A.self, B.self)
                for type in repeat (each T).self {
                    access = type._reading(access)
                }
                return access
            }

            /// Takes the written columns out of `world` until ``_restore(into:)``, visiting through
            /// `run`, which a call site that knows the types writes as
            /// `{ world, query, body in world.update(A.self, B.self, over: query, body: body) }` so the overload for the query's shape runs.
            @inlinable
            public static func _fetch(
                from world: inout World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void
            ) -> Self {
                Self(part: world.split(writing: _access(in: Self.self)), run: run)
            }

            /// Takes the written columns out of `world` until ``_restore(into:)``.
            @inlinable
            public static func _fetch(from world: inout World) -> Self {
                _fetch(from: &world) { world, query, body in world.update(A.self, B.self, over: query, body: body) }
            }

            /// Puts the written columns back into `world`.
            @inlinable
            public func _restore(into world: inout World) {
                world.merge(writing: Self._access(in: Self.self), from: part)
            }

            /// Visits every matching entity once, calling `body` with its written components.
            @inlinable
            public func callAsFunction(_ body: Body) {
                run(&part, Query(filter: QueryFilter()), body)
            }

            /// Writes `A`, `B` of every entity holding them and matching the terms `T`, which it reads, and passing the filter types `F`.
            public final class Where<each F: FilterTerm>: SystemParameter, @unchecked Sendable {
                /// What the visit calls for each entity.
                public typealias Body = (inout A, inout B, QueryRow<repeat (each T).Value>) -> Void

                @usableFromInline var part: World
                @usableFromInline let run: (inout World, Query<repeat each T>, Body) -> Void

                @inlinable
                init(part: World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void) {
                    self.part = part
                    self.run = run
                }

                /// The filter the filter types stand for, every one applied.
                public static var filter: QueryFilter {
                    var filter = QueryFilter()
                    for type in repeat (each F).self {
                        filter = filter.merging(type.filter)
                    }
                    return filter
                }

                @inlinable
                public static func _access<S>(in system: S.Type) -> Access {
                    var access = Access.writes(A.self, B.self)
                    for type in repeat (each T).self {
                        access = type._reading(access)
                    }
                    for type in repeat (each F).self {
                        access = type._reading(access)
                    }
                    return access
                }

                /// Takes the written columns out of `world` until ``_restore(into:)``, visiting through
                /// `run`, which a call site that knows the types writes as
                /// `{ world, query, body in world.update(A.self, B.self, over: query, body: body) }` so the overload for the query's shape runs.
                @inlinable
                public static func _fetch(
                    from world: inout World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void
                ) -> Self {
                    Self(part: world.split(writing: _access(in: Self.self)), run: run)
                }

                /// Takes the written columns out of `world` until ``_restore(into:)``.
                @inlinable
                public static func _fetch(from world: inout World) -> Self {
                    _fetch(from: &world) { world, query, body in world.update(A.self, B.self, over: query, body: body) }
                }

                /// Puts the written columns back into `world`.
                @inlinable
                public func _restore(into world: inout World) {
                    world.merge(writing: Self._access(in: Self.self), from: part)
                }

                /// Visits every matching entity once, calling `body` with its written components.
                @inlinable
                public func callAsFunction(_ body: Body) {
                    run(&part, Query(filter: Self.filter), body)
                }
            }
        }

        /// Writes `A`, `B`, `C` of every entity holding them.
        public final class And<C: Component>: SystemParameter, @unchecked Sendable {
            /// What the visit calls for each entity.
            public typealias Body = (inout A, inout B, inout C, Entity) -> Void

            @usableFromInline var part: World

            @inlinable
            init(part: World) {
                self.part = part
            }

            @inlinable
            public static func _access<S>(in system: S.Type) -> Access {
                return Access.writes(A.self, B.self, C.self)
            }

            /// Takes the written columns out of `world` until ``_restore(into:)``.
            @inlinable
            public static func _fetch(from world: inout World) -> Self {
                Self(part: world.split(writing: _access(in: Self.self)))
            }

            /// Puts the written columns back into `world`.
            @inlinable
            public func _restore(into world: inout World) {
                world.merge(writing: Self._access(in: Self.self), from: part)
            }

            /// Visits every matching entity once, calling `body` with its written components.
            @inlinable
            public func callAsFunction(_ body: Body) {
                part.update(A.self, B.self, C.self, over: filteredQuery(filter: QueryFilter())) { a, b, c, row in body(&a, &b, &c, row.entity) }
            }

            /// Writes `A`, `B`, `C` of every entity holding them, and passing the filter types `F`.
            public final class Where<each F: FilterTerm>: SystemParameter, @unchecked Sendable {
                /// What the visit calls for each entity.
                public typealias Body = (inout A, inout B, inout C, Entity) -> Void

                @usableFromInline var part: World

                @inlinable
                init(part: World) {
                    self.part = part
                }

                /// The filter the filter types stand for, every one applied.
                public static var filter: QueryFilter {
                    var filter = QueryFilter()
                    for type in repeat (each F).self {
                        filter = filter.merging(type.filter)
                    }
                    return filter
                }

                @inlinable
                public static func _access<S>(in system: S.Type) -> Access {
                    var access = Access.writes(A.self, B.self, C.self)
                    for type in repeat (each F).self {
                        access = type._reading(access)
                    }
                    return access
                }

                /// Takes the written columns out of `world` until ``_restore(into:)``.
                @inlinable
                public static func _fetch(from world: inout World) -> Self {
                    Self(part: world.split(writing: _access(in: Self.self)))
                }

                /// Puts the written columns back into `world`.
                @inlinable
                public func _restore(into world: inout World) {
                    world.merge(writing: Self._access(in: Self.self), from: part)
                }

                /// Visits every matching entity once, calling `body` with its written components.
                @inlinable
                public func callAsFunction(_ body: Body) {
                    part.update(A.self, B.self, C.self, over: filteredQuery(filter: Self.filter)) { a, b, c, row in body(&a, &b, &c, row.entity) }
                }
            }

            /// Writes `A`, `B`, `C` of every entity holding them and matching the terms `T`, which it reads.
            public final class Over<each T: QueryTerm>: SystemParameter, @unchecked Sendable {
                /// What the visit calls for each entity.
                public typealias Body = (inout A, inout B, inout C, QueryRow<repeat (each T).Value>) -> Void

                @usableFromInline var part: World
                @usableFromInline let run: (inout World, Query<repeat each T>, Body) -> Void

                @inlinable
                init(part: World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void) {
                    self.part = part
                    self.run = run
                }

                @inlinable
                public static func _access<S>(in system: S.Type) -> Access {
                    var access = Access.writes(A.self, B.self, C.self)
                    for type in repeat (each T).self {
                        access = type._reading(access)
                    }
                    return access
                }

                /// Takes the written columns out of `world` until ``_restore(into:)``, visiting through
                /// `run`, which a call site that knows the types writes as
                /// `{ world, query, body in world.update(A.self, B.self, C.self, over: query, body: body) }` so the overload for the query's shape runs.
                @inlinable
                public static func _fetch(
                    from world: inout World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void
                ) -> Self {
                    Self(part: world.split(writing: _access(in: Self.self)), run: run)
                }

                /// Takes the written columns out of `world` until ``_restore(into:)``.
                @inlinable
                public static func _fetch(from world: inout World) -> Self {
                    _fetch(from: &world) { world, query, body in world.update(A.self, B.self, C.self, over: query, body: body) }
                }

                /// Puts the written columns back into `world`.
                @inlinable
                public func _restore(into world: inout World) {
                    world.merge(writing: Self._access(in: Self.self), from: part)
                }

                /// Visits every matching entity once, calling `body` with its written components.
                @inlinable
                public func callAsFunction(_ body: Body) {
                    run(&part, Query(filter: QueryFilter()), body)
                }

                /// Writes `A`, `B`, `C` of every entity holding them and matching the terms `T`, which it reads, and passing the filter types `F`.
                public final class Where<each F: FilterTerm>: SystemParameter, @unchecked Sendable {
                    /// What the visit calls for each entity.
                    public typealias Body = (inout A, inout B, inout C, QueryRow<repeat (each T).Value>) -> Void

                    @usableFromInline var part: World
                    @usableFromInline let run: (inout World, Query<repeat each T>, Body) -> Void

                    @inlinable
                    init(part: World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void) {
                        self.part = part
                        self.run = run
                    }

                    /// The filter the filter types stand for, every one applied.
                    public static var filter: QueryFilter {
                        var filter = QueryFilter()
                        for type in repeat (each F).self {
                            filter = filter.merging(type.filter)
                        }
                        return filter
                    }

                    @inlinable
                    public static func _access<S>(in system: S.Type) -> Access {
                        var access = Access.writes(A.self, B.self, C.self)
                        for type in repeat (each T).self {
                            access = type._reading(access)
                        }
                        for type in repeat (each F).self {
                            access = type._reading(access)
                        }
                        return access
                    }

                    /// Takes the written columns out of `world` until ``_restore(into:)``, visiting through
                    /// `run`, which a call site that knows the types writes as
                    /// `{ world, query, body in world.update(A.self, B.self, C.self, over: query, body: body) }` so the overload for the query's shape runs.
                    @inlinable
                    public static func _fetch(
                        from world: inout World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void
                    ) -> Self {
                        Self(part: world.split(writing: _access(in: Self.self)), run: run)
                    }

                    /// Takes the written columns out of `world` until ``_restore(into:)``.
                    @inlinable
                    public static func _fetch(from world: inout World) -> Self {
                        _fetch(from: &world) { world, query, body in world.update(A.self, B.self, C.self, over: query, body: body) }
                    }

                    /// Puts the written columns back into `world`.
                    @inlinable
                    public func _restore(into world: inout World) {
                        world.merge(writing: Self._access(in: Self.self), from: part)
                    }

                    /// Visits every matching entity once, calling `body` with its written components.
                    @inlinable
                    public func callAsFunction(_ body: Body) {
                        run(&part, Query(filter: Self.filter), body)
                    }
                }
            }
        }
    }
}
