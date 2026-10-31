import Synchronization
import WorldModule

/// Hands each `E` sent in a world to an `AsyncStream`, so code outside the schedule can await
/// events.
///
/// ```swift
/// let (damages, continuation) = AsyncStream.makeStream(of: Damage.self)
/// let frame = Schedule {
///     UpdateEvents()
///     Combat()
///     ForwardEvents(to: continuation).after(Combat.self)
/// }
/// Task { for await damage in damages { print(damage) } }
/// ```
///
/// Each run yields the events the system has not yet forwarded, oldest first, as an
/// ``EventReader`` would read them; each `ForwardEvents` value has its own place in the events,
/// and copies of it share that place. A stream whose consumer has stopped drops what it is
/// given. The stream ends when the continuation is finished, not when the system leaves a
/// schedule.
public struct ForwardEvents<E: Event>: System {
    let continuation: AsyncStream<E>.Continuation
    let reader: UInt64

    /// A system yielding each new `E` to `continuation`.
    public init(to continuation: AsyncStream<E>.Continuation) {
        self.continuation = continuation
        reader = nextForwarderNumber.wrappingAdd(1, ordering: .relaxed).newValue
    }

    /// Reading the events and writing the forwarders' places in them.
    public var access: Access? {
        .reads(resources: Events<E>.self).writes(resources: NumberedEventCursors<E>.self)
    }

    public func run(in world: inout World) {
        for event in world.readEvents(E.self, byReaderNumbered: reader) {
            continuation.yield(event)
        }
    }
}

/// Hands each `C` added or changed since the system last ran to an `AsyncStream`, with its
/// entity.
///
/// ```swift
/// let (healthChanges, continuation) = AsyncStream.makeStream(of: QueryRow<Health>.self)
/// let frame = Schedule {
///     Combat()
///     ForwardChanges(to: continuation).after(Combat.self)
/// }
/// Task { for await row in healthChanges { print(row.entity, row.components.current) } }
/// ```
///
/// Each run yields the rows `.changed(C.self)` lists for the system, in the query's order; the
/// first run yields every `C`. The stream ends when the continuation is finished.
public struct ForwardChanges<C: Component>: System {
    @usableFromInline let continuation: AsyncStream<QueryRow<C>>.Continuation

    /// A system yielding each added or changed `C` to `continuation`.
    @inlinable
    public init(to continuation: AsyncStream<QueryRow<C>>.Continuation) {
        self.continuation = continuation
    }

    /// Reading `C`.
    @inlinable
    public var access: Access? { .reads(C.self) }

    @inlinable
    public func run(in world: inout World) {
        for (entity, component) in world.query(C.self).changed(C.self) {
            continuation.yield(QueryRow(entity: entity, components: component))
        }
    }
}

/// The source of ``ForwardEvents`` reader numbers.
let nextForwarderNumber = Atomic<UInt64>(0)
