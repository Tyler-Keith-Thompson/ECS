/// A type that describes a message one part of a program sends and other parts read later.
///
/// Use events to decouple the code that notices something from the code that responds to it:
/// a physics step sends a collision, and separate damage and sound systems each read it. Declare
/// an event as a type that conforms to `Event`, send it with ``World/send(_:)``, and read it
/// with ``World/readEvents(_:by:)``:
///
/// ```swift
/// struct Collision: Event { var first: Entity, second: Entity }
/// enum DamageReader {}
///
/// var world = World()
/// let ship = world.spawn(Health(current: 3))
/// let asteroid = world.spawn(Health(current: 1))
/// world.send(Collision(first: ship, second: asteroid))
///
/// for collision in world.readEvents(Collision.self, by: DamageReader.self) {
///     world[Health.self, of: collision.first].current -= 1
/// }
/// print(world[Health.self, of: ship])
/// // Prints "Health(current: 2)"
/// ```
///
/// Events wait in the world's ``Events`` resource until ``World/updateEvents()`` drops them,
/// so senders and readers don't need to run at the same moment. Unlike an ``EntityEvent``, an
/// event isn't aimed at an entity and runs no code when sent.
public protocol Event: Sendable {}

/// The resource that holds a world's events of one type.
///
/// A world keeps the events of each type in two buffers: the events sent since the last update,
/// and those sent in the update before. Each call to ``World/updateEvents()`` drops the older
/// buffer, so an event can be read for the rest of the update it was sent in and all of the
/// next, whichever order the sender and its readers run in.
///
/// ``World/send(_:)`` creates this resource the first time it sends an event of a type, and
/// ``World/readEvents(_:by:)`` keeps each reader's place in it. Read the resource directly when
/// you need every event held, regardless of who has read them:
///
/// ```swift
/// var world = World()
/// let ship = world.spawn(Health(current: 3))
/// let asteroid = world.spawn(Health(current: 1))
/// world.send(Collision(first: ship, second: asteroid))
///
/// world.updateEvents()
/// print(world.resources[Events<Collision>.self].count)
/// // Prints "1"
/// world.updateEvents()
/// print(world.resources[Events<Collision>.self].isEmpty)
/// // Prints "true"
/// ```
@frozen
public struct Events<E: Event>: Resource {
    @usableFromInline var previous: [E] = []
    @usableFromInline var current: [E] = []
    /// The number of the first event in `previous`.
    @usableFromInline var previousStart = 0

    /// Creates an empty event buffer.
    @inlinable
    public init() {}

    /// The number of the first event in `current`.
    @inlinable
    var currentStart: Int { previousStart + previous.count }

    /// The number the next event sent will have.
    @inlinable
    var end: Int { currentStart + current.count }

    /// The number of events held.
    @inlinable
    public var count: Int { previous.count + current.count }

    /// A Boolean value indicating whether no events are held.
    @inlinable
    public var isEmpty: Bool { count == 0 }

    /// Adds an event after every event held.
    ///
    /// - Parameter event: The event to add.
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func send(_ event: E) {
        current.append(event)
    }

    /// Drops the events sent before the last update, and makes the events sent since then the
    /// older buffer.
    ///
    /// ``World/updateEvents()`` calls this method on every event type at once.
    ///
    /// - Complexity: O(*n*), where *n* is the number of events dropped.
    @inlinable
    public mutating func update() {
        previousStart = currentStart
        swap(&previous, &current)
        current.removeAll(keepingCapacity: true)
    }

    /// Every event held, oldest first, whether or not any reader has read it.
    @inlinable
    public var all: EventsView<E> { view(from: previousStart) }

    /// The events numbered `start` or later that are still held, oldest first.
    @inlinable
    func view(from start: Int) -> EventsView<E> {
        let start = max(start, previousStart)
        let fromPrevious = min(max(start - previousStart, 0), previous.count)
        let fromCurrent = max(start - currentStart, 0)
        return EventsView(previous: previous[fromPrevious...], current: current[min(fromCurrent, current.count)...])
    }
}

/// A collection of events of one type, oldest first.
///
/// You get a view of events from ``World/readEvents(_:by:)``, ``World/events(_:)`` or
/// ``Events/all``. The view shares the events' storage, so creating one copies nothing.
@frozen
public struct EventsView<E: Event>: RandomAccessCollection, Sendable {
    @usableFromInline let previous: ArraySlice<E>
    @usableFromInline let current: ArraySlice<E>

    @inlinable
    init(previous: ArraySlice<E>, current: ArraySlice<E>) {
        self.previous = previous
        self.current = current
    }

    @inlinable
    public var startIndex: Int { 0 }

    @inlinable
    public var endIndex: Int { previous.count + current.count }

    @inlinable
    public subscript(position: Int) -> E {
        position < previous.count
            ? previous[previous.startIndex + position]
            : current[current.startIndex + position - previous.count]
    }
}

/// The number of the next `E` that `Reader` has not read.
@usableFromInline
struct EventCursor<E: Event, Reader>: Resource {
    @usableFromInline var next: Int

    @inlinable
    init(next: Int) {
        self.next = next
    }
}

/// The place in the `E`s of each reader told apart by a number.
package struct NumberedEventCursors<E: Event>: Resource {
    package var next: [UInt64: Int] = [:]

    package init() {}
}

/// What ``World/updateEvents()`` does to an ``Events`` without knowing its event type.
@usableFromInline
protocol EventBuffer: Resource {
    mutating func update()
}

extension Events: EventBuffer {}

extension World {
    /// Sends an event for readers of its type.
    ///
    /// Every reader of `E` can read the event for the rest of this update and all of the next
    /// (see ``Events``). The first event of a type creates the world's `Events<E>` resource.
    ///
    /// - Parameter event: The event to send.
    /// - Complexity: O(1) amortized.
    @inlinable
    public mutating func send<E: Event>(_ event: E) {
        if resources.contains(Events<E>.self) {
            resources[Events<E>.self].send(event)
        } else {
            var events = Events<E>()
            events.send(event)
            resources.insert(events)
        }
    }

    /// Returns every event of a type that the world holds, oldest first, without marking any as
    /// read.
    ///
    /// ```swift
    /// var world = World()
    /// let ship = world.spawn(Health(current: 3))
    /// let asteroid = world.spawn(Health(current: 1))
    /// world.send(Collision(first: ship, second: asteroid))
    ///
    /// print(world.events(Collision.self).count)
    /// // Prints "1"
    /// ```
    ///
    /// - Parameter type: The event type.
    /// - Returns: The events of `type`, or an empty view if none were sent.
    @inlinable
    public func events<E: Event>(_ type: E.Type) -> EventsView<E> {
        ((try? resources[checked: Events<E>.self]) ?? Events()).all
    }

    /// Returns the events of a type that a reader hasn't read yet, oldest first, and marks them
    /// as read by that reader.
    ///
    /// A reader is any type you choose to identify the code reading, such as the system's own
    /// type. The world keeps each reader's place in the events, so readers don't affect one
    /// another, and a copy of the world keeps the places its original had:
    ///
    /// ```swift
    /// enum SoundReader {}
    ///
    /// var world = World()
    /// let ship = world.spawn(Health(current: 3))
    /// let asteroid = world.spawn(Health(current: 1))
    /// world.send(Collision(first: ship, second: asteroid))
    ///
    /// let heard = world.readEvents(Collision.self, by: SoundReader.self)
    /// print(heard.count)
    /// // Prints "1"
    ///
    /// let heardAgain = world.readEvents(Collision.self, by: SoundReader.self)
    /// print(heardAgain.count)
    /// // Prints "0"
    ///
    /// let damaging = world.readEvents(Collision.self, by: DamageReader.self)
    /// print(damaging.count)
    /// // Prints "1"
    /// ```
    ///
    /// - Important: A reader that doesn't read for two updates misses the events dropped in
    ///   between.
    ///
    /// - Parameters:
    ///   - type: The event type.
    ///   - reader: The type that identifies the reader.
    /// - Returns: The events of `type` that `reader` hasn't read.
    /// - Complexity: O(1). The view shares the events' storage.
    @inlinable
    public mutating func readEvents<E: Event, Reader>(_ type: E.Type, by reader: Reader.Type) -> EventsView<E> {
        let events = (try? resources[checked: Events<E>.self]) ?? Events()
        let next = (try? resources[checked: EventCursor<E, Reader>.self])?.next ?? 0
        resources.insert(EventCursor<E, Reader>(next: events.end))
        return events.view(from: next)
    }

    /// The `E`s that the reader identified by `reader` has not read yet, oldest first, marking
    /// them read by it; ``readEvents(_:by:)`` for readers told apart by a number rather than a
    /// type.
    ///
    /// - Complexity: O(1) amortized; the view shares the events' storage.
    package mutating func readEvents<E: Event>(_ type: E.Type, byReaderNumbered reader: UInt64) -> EventsView<E> {
        let events = (try? resources[checked: Events<E>.self]) ?? Events()
        var cursors = resources.remove(NumberedEventCursors<E>.self) ?? NumberedEventCursors()
        let next = cursors.next[reader] ?? 0
        cursors.next[reader] = events.end
        resources.insert(cursors)
        return events.view(from: next)
    }

    /// Ends an update for every event type, dropping the events sent before the previous
    /// update.
    ///
    /// Call this method once per frame or step, before the systems that send and read events.
    /// The `UpdateEvents` system does so as part of a schedule.
    ///
    /// - Complexity: O(*r*), where *r* is the number of resources.
    @inlinable
    public mutating func updateEvents() {
        resources.updateEvents()
    }
}

extension Resources {
    @inlinable
    mutating func updateEvents() {
        for key in Array(storage.keys) {
            guard var buffer = storage[key] as? any EventBuffer else { continue }
            storage[key] = nil
            buffer.update()
            storage[key] = buffer
        }
    }
}

extension Commands {
    /// Records sending an event, which ``World/send(_:)`` performs when the commands are
    /// applied.
    ///
    /// - Parameter event: The event to send.
    @inlinable
    public mutating func send<E: Event>(_ event: E) {
        operations.append { world, _ in world.send(event) }
    }
}
