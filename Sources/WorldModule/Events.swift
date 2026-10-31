/// A message one part of a program sends and others read: a collision, a key press, a death.
///
/// ```swift
/// struct Collision: Event { var first: Entity, second: Entity }
/// ```
public protocol Event: Sendable {}

/// The events of one type a world holds: those sent since the last update and those sent in the
/// update before, double-buffered.
///
/// Each ``World/updateEvents()`` drops the older buffer, so an event can be read for the rest of
/// the update it was sent in and all of the next, whichever order the sender and readers run in.
/// Events are numbered in the order they were sent; readers remember the number of the next
/// event they have not read.
@frozen
public struct Events<E: Event>: Resource {
    @usableFromInline var previous: [E] = []
    @usableFromInline var current: [E] = []
    /// The number of the first event in `previous`.
    @usableFromInline var previousStart = 0

    /// No events.
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

    /// Whether no events are held.
    @inlinable
    public var isEmpty: Bool { count == 0 }

    /// Adds `event` after every event held.
    @inlinable
    public mutating func send(_ event: E) {
        current.append(event)
    }

    /// Drops the events sent before the last update; the events sent since become the older
    /// buffer.
    @inlinable
    public mutating func update() {
        previousStart = currentStart
        swap(&previous, &current)
        current.removeAll(keepingCapacity: true)
    }

    /// Every event held, oldest first.
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

/// Events of one type, oldest first: the part of a world's ``Events`` a reader asked for.
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

/// What ``World/updateEvents()`` does to an ``Events`` without knowing its event type.
@usableFromInline
protocol EventBuffer: Resource {
    mutating func update()
}

extension Events: EventBuffer {}

extension World {
    /// Sends `event`: every reader of `E` can read it for the rest of this update and all of the
    /// next.
    ///
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

    /// Every `E` the world holds, oldest first, without marking any read.
    @inlinable
    public func events<E: Event>(_ type: E.Type) -> EventsView<E> {
        ((try? resources[checked: Events<E>.self]) ?? Events()).all
    }

    /// The `E`s that `reader` has not read yet, oldest first, marking them read by it.
    ///
    /// Each reader type has its own place in the events, kept in the world, so readers do not
    /// affect one another and a copy of the world keeps the places its original had. A reader
    /// that has not read for two updates misses the events dropped in between.
    ///
    /// ```swift
    /// for collision in world.readEvents(Collision.self, by: DamageSystem.self) {
    ///     world[Health.self, of: collision.first].current -= 1
    /// }
    /// ```
    ///
    /// - Complexity: O(1); the view shares the events' storage.
    @inlinable
    public mutating func readEvents<E: Event, Reader>(_ type: E.Type, by reader: Reader.Type) -> EventsView<E> {
        let events = (try? resources[checked: Events<E>.self]) ?? Events()
        let next = (try? resources[checked: EventCursor<E, Reader>.self])?.next ?? 0
        resources.insert(EventCursor<E, Reader>(next: events.end))
        return events.view(from: next)
    }

    /// Ends an update for every event type: drops the events sent before the previous update.
    ///
    /// Call it once per frame or step, before the systems that send and read events; the
    /// `UpdateEvents` system does so as part of a schedule.
    ///
    /// - Complexity: O(*r*) for *r* resources.
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
    /// Records sending `event`.
    @inlinable
    public mutating func send<E: Event>(_ event: E) {
        record { world in world.send(event) }
    }
}
