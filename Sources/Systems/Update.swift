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

/// A system parameter that changes a component of every entity that holds it.
///
/// Call an update like a function, passing a closure that receives each entity's component to
/// change in place, and the entity. The update's type says which entities it visits and what
/// else it reads, by nesting:
///
/// - `Update<A>` changes the `A` of every entity holding one.
/// - `Update<A>.And<B>` and `Update<A>.And<B>.And<C>` change two or three components of every
///   entity holding all of them.
/// - `.Over<T...>` also reads the query terms `T`, components or ``/WorldModule/AnyOf`` groups,
///   and visits only the entities that match them. The closure receives them as a
///   ``/WorldModule/QueryRow``, as ``/WorldModule/World/update(_:over:body:)`` does.
/// - `.Where<F...>` visits only the entities that pass the filter types `F`, such as
///   ``/WorldModule/Without`` and ``/WorldModule/Changed``.
///
/// The following system bounces everything that has fallen below the ground, changing both its
/// position and its velocity:
///
/// ```swift
/// @System
/// struct Bounce {
///     func run(_ bouncers: Update<Position>.And<Velocity>) {
///         bouncers { position, velocity, _ in
///             if position.y < 0 {
///                 position.y = -position.y
///                 velocity.dy = -velocity.dy
///             }
///         }
///     }
/// }
///
/// var world = World()
/// let ball = world.spawn(Position(x: 0, y: -2), Velocity(dx: 0, dy: -5))
/// Schedule { Bounce() }.run(on: &world)
/// print(world[Position.self, of: ball])
/// // Prints "Position(x: 0.0, y: 2.0)"
/// print(world[Velocity.self, of: ball])
/// // Prints "Velocity(dx: 0.0, dy: 5.0)"
/// ```
///
/// Every written component an update visits is marked changed, whether or not the closure
/// changes it.
public final class Update<A: Component>: SystemParameter, @unchecked Sendable {
    /// The type of the closure the update calls for each entity.
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

    /// Calls a closure once for each matching entity, passing its components to change.
    ///
    /// - Parameter body: A closure that changes one entity's components.
    @inlinable
    public func callAsFunction(_ body: Body) {
        part.update(A.self, where: QueryFilter()) { a, row in body(&a, row.entity) }
    }

    /// An update of `A` that visits only the entities passing the filter types `F`.
    public final class Where<each F: FilterTerm>: SystemParameter, @unchecked Sendable {
        /// The type of the closure the update calls for each entity.
        public typealias Body = (inout A, Entity) -> Void

        @usableFromInline var part: World

        @inlinable
        init(part: World) {
            self.part = part
        }

        /// The filter the filter types `F` stand for, all of them applied.
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

        /// Calls a closure once for each matching entity, passing its components to change.
        ///
        /// - Parameter body: A closure that changes one entity's components.
        @inlinable
        public func callAsFunction(_ body: Body) {
            part.update(A.self, where: Self.filter) { a, row in body(&a, row.entity) }
        }
    }

    /// An update of `A` that also reads the query terms `T`, visiting only the entities that match
    /// them.
    public final class Over<each T: QueryTerm>: SystemParameter, @unchecked Sendable {
        /// The type of the closure the update calls for each entity.
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

        /// Calls a closure once for each matching entity, passing its components to change.
        ///
        /// - Parameter body: A closure that changes one entity's components.
        @inlinable
        public func callAsFunction(_ body: Body) {
            run(&part, Query(filter: QueryFilter()), body)
        }

        /// An update of `A` that reads the query terms `T`, visiting only the entities that match
        /// them and pass the filter types `F`.
        public final class Where<each F: FilterTerm>: SystemParameter, @unchecked Sendable {
            /// The type of the closure the update calls for each entity.
            public typealias Body = (inout A, QueryRow<repeat (each T).Value>) -> Void

            @usableFromInline var part: World
            @usableFromInline let run: (inout World, Query<repeat each T>, Body) -> Void

            @inlinable
            init(part: World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void) {
                self.part = part
                self.run = run
            }

            /// The filter the filter types `F` stand for, all of them applied.
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

            /// Calls a closure once for each matching entity, passing its components to change.
            ///
            /// - Parameter body: A closure that changes one entity's components.
            @inlinable
            public func callAsFunction(_ body: Body) {
                run(&part, Query(filter: Self.filter), body)
            }
        }
    }

    /// An update of `A` and `B` of every entity holding both.
    public final class And<B: Component>: SystemParameter, @unchecked Sendable {
        /// The type of the closure the update calls for each entity.
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

        /// Calls a closure once for each matching entity, passing its components to change.
        ///
        /// - Parameter body: A closure that changes one entity's components.
        @inlinable
        public func callAsFunction(_ body: Body) {
            part.update(A.self, B.self, where: QueryFilter()) { a, b, row in body(&a, &b, row.entity) }
        }

        /// An update of `A` and `B` that visits only the entities passing the filter types `F`.
        public final class Where<each F: FilterTerm>: SystemParameter, @unchecked Sendable {
            /// The type of the closure the update calls for each entity.
            public typealias Body = (inout A, inout B, Entity) -> Void

            @usableFromInline var part: World

            @inlinable
            init(part: World) {
                self.part = part
            }

            /// The filter the filter types `F` stand for, all of them applied.
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

            /// Calls a closure once for each matching entity, passing its components to change.
            ///
            /// - Parameter body: A closure that changes one entity's components.
            @inlinable
            public func callAsFunction(_ body: Body) {
                part.update(A.self, B.self, where: Self.filter) { a, b, row in body(&a, &b, row.entity) }
            }
        }

        /// An update of `A` and `B` that also reads the query terms `T`, visiting only the entities
        /// that match them.
        public final class Over<each T: QueryTerm>: SystemParameter, @unchecked Sendable {
            /// The type of the closure the update calls for each entity.
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

            /// Calls a closure once for each matching entity, passing its components to change.
            ///
            /// - Parameter body: A closure that changes one entity's components.
            @inlinable
            public func callAsFunction(_ body: Body) {
                run(&part, Query(filter: QueryFilter()), body)
            }

            /// An update of `A` and `B` that reads the query terms `T`, visiting only the entities
            /// that match them and pass the filter types `F`.
            public final class Where<each F: FilterTerm>: SystemParameter, @unchecked Sendable {
                /// The type of the closure the update calls for each entity.
                public typealias Body = (inout A, inout B, QueryRow<repeat (each T).Value>) -> Void

                @usableFromInline var part: World
                @usableFromInline let run: (inout World, Query<repeat each T>, Body) -> Void

                @inlinable
                init(part: World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void) {
                    self.part = part
                    self.run = run
                }

                /// The filter the filter types `F` stand for, all of them applied.
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

                /// Calls a closure once for each matching entity, passing its components to change.
                ///
                /// - Parameter body: A closure that changes one entity's components.
                @inlinable
                public func callAsFunction(_ body: Body) {
                    run(&part, Query(filter: Self.filter), body)
                }
            }
        }

        /// An update of `A`, `B` and `C` of every entity holding all three.
        public final class And<C: Component>: SystemParameter, @unchecked Sendable {
            /// The type of the closure the update calls for each entity.
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

            /// Calls a closure once for each matching entity, passing its components to change.
            ///
            /// - Parameter body: A closure that changes one entity's components.
            @inlinable
            public func callAsFunction(_ body: Body) {
                part.update(A.self, B.self, C.self, over: filteredQuery(filter: QueryFilter())) { a, b, c, row in body(&a, &b, &c, row.entity) }
            }

            /// An update of `A`, `B` and `C` that visits only the entities passing the filter types
            /// `F`.
            public final class Where<each F: FilterTerm>: SystemParameter, @unchecked Sendable {
                /// The type of the closure the update calls for each entity.
                public typealias Body = (inout A, inout B, inout C, Entity) -> Void

                @usableFromInline var part: World

                @inlinable
                init(part: World) {
                    self.part = part
                }

                /// The filter the filter types `F` stand for, all of them applied.
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

                /// Calls a closure once for each matching entity, passing its components to change.
                ///
                /// - Parameter body: A closure that changes one entity's components.
                @inlinable
                public func callAsFunction(_ body: Body) {
                    part.update(A.self, B.self, C.self, over: filteredQuery(filter: Self.filter)) { a, b, c, row in body(&a, &b, &c, row.entity) }
                }
            }

            /// An update of `A`, `B` and `C` that also reads the query terms `T`, visiting only the
            /// entities that match them.
            public final class Over<each T: QueryTerm>: SystemParameter, @unchecked Sendable {
                /// The type of the closure the update calls for each entity.
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

                /// Calls a closure once for each matching entity, passing its components to change.
                ///
                /// - Parameter body: A closure that changes one entity's components.
                @inlinable
                public func callAsFunction(_ body: Body) {
                    run(&part, Query(filter: QueryFilter()), body)
                }

                /// An update of `A`, `B` and `C` that reads the query terms `T`, visiting only the
                /// entities that match them and pass the filter types `F`.
                public final class Where<each F: FilterTerm>: SystemParameter, @unchecked Sendable {
                    /// The type of the closure the update calls for each entity.
                    public typealias Body = (inout A, inout B, inout C, QueryRow<repeat (each T).Value>) -> Void

                    @usableFromInline var part: World
                    @usableFromInline let run: (inout World, Query<repeat each T>, Body) -> Void

                    @inlinable
                    init(part: World, run: @escaping (inout World, Query<repeat each T>, Body) -> Void) {
                        self.part = part
                        self.run = run
                    }

                    /// The filter the filter types `F` stand for, all of them applied.
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

                    /// Calls a closure once for each matching entity, passing its components to change.
                    ///
                    /// - Parameter body: A closure that changes one entity's components.
                    @inlinable
                    public func callAsFunction(_ body: Body) {
                        run(&part, Query(filter: Self.filter), body)
                    }
                }
            }
        }
    }
}
