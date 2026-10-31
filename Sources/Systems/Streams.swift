import Synchronization
import WorldModule

/// A system that yields each event of one type to an asynchronous stream, so code outside the
/// schedule can await the events.
///
/// Use this system to hand events to code that doesn't run in a schedule, such as a task that
/// plays a sound for each hit. Make a stream, put a `ForwardEvents` with the stream's
/// continuation in the schedule after the systems that send the events, and iterate the stream
/// elsewhere:
///
/// ```swift
/// let (damages, continuation) = AsyncStream.makeStream(of: Damage.self)
/// var world = World()
/// world.spawn(Position(x: 0, y: -1))
///
/// let frame = Schedule {
///     UpdateEvents()
///     Combat()
///     ForwardEvents(to: continuation).after(Combat.self)
/// }
/// frame.run(on: &world)
/// continuation.finish()
///
/// var amounts: [Int] = []
/// for await damage in damages {
///     amounts.append(damage.amount)
/// }
/// print(amounts)
/// // Prints "[10]"
/// ```
///
/// Each run yields the events the system hasn't forwarded yet, oldest first, as an
/// ``EventReader`` reads them. Each `ForwardEvents` you create has its own place in the events,
/// which its copies share. A stream whose consumer has stopped drops what it's given. The stream
/// ends when you finish the continuation, not when the system leaves a schedule.
public struct ForwardEvents<E: Event>: System {
    let continuation: AsyncStream<E>.Continuation
    let reader: UInt64

    /// Creates a system that yields each new event to a stream's continuation.
    ///
    /// - Parameter continuation: The continuation of the stream to yield the events to.
    public init(to continuation: AsyncStream<E>.Continuation) {
        self.continuation = continuation
        reader = nextForwarderNumber.wrappingAdd(1, ordering: .relaxed).newValue
    }

    /// The system's access: reading the events, and writing the place each forwarding system has
    /// reached in them.
    public var access: Access? {
        .reads(resources: Events<E>.self).writes(resources: NumberedEventCursors<E>.self)
    }

    public func run(in world: inout World) {
        for event in world.readEvents(E.self, byReaderNumbered: reader) {
            continuation.yield(event)
        }
    }
}

/// A system that yields each component of one type added or changed since it last ran to an
/// asynchronous stream, with its entity.
///
/// Use this system to let code outside the schedule follow a component, such as a view that
/// redraws a health bar when the health changes. Each element of the stream is a
/// ``/WorldModule/QueryRow`` of the entity and its component:
///
/// ```swift
/// let (changes, continuation) = AsyncStream.makeStream(of: QueryRow<Health>.self)
/// var world = World()
/// let knight = world.spawn(Health(current: 30))
/// world.spawn(Health(current: 50))
///
/// let frame = Schedule { ForwardChanges(to: continuation) }
/// frame.run(on: &world)
/// world[Health.self, of: knight].current = 25
/// frame.run(on: &world)
/// continuation.finish()
///
/// var healths: [Int] = []
/// for await row in changes {
///     healths.append(row.components.current)
/// }
/// print(healths)
/// // Prints "[30, 50, 25]"
/// ```
///
/// The first run yields every `C`; each later run yields those added or changed since the run
/// before. The stream ends when you finish the continuation.
public struct ForwardChanges<C: Component>: System {
    @usableFromInline let continuation: AsyncStream<QueryRow<C>>.Continuation

    /// Creates a system that yields each added or changed component to a stream's continuation.
    ///
    /// - Parameter continuation: The continuation of the stream to yield the rows to.
    @inlinable
    public init(to continuation: AsyncStream<QueryRow<C>>.Continuation) {
        self.continuation = continuation
    }

    /// The system's access: reading `C`.
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
