// Each test is self-contained: the systems it runs are declared inside it or below.

import ECSTestSupport
import Systems
import Testing
import WorldModule

struct Chime: Event, Equatable {
    var number: Int
}

/// Sends a `Chime` numbered by the frame, read from the world's Frame resource.
struct Chimer: System {
    func run(in world: inout World) {
        world.resources[ChimeFrame.self].number += 1
        world.send(Chime(number: world.resources[ChimeFrame.self].number))
    }
}

struct ChimeFrame: Resource {
    var number = 0
}

/// Heals every entity with a Health of 1 to 2.
struct Healer: System {
    var access: Access? { .writes(Health.self) }

    func run(in world: inout World) {
        for (entity, health) in world.query(Health.self) where health.current == 1 {
            world[Health.self, of: entity].current = 2
        }
    }
}

@Suite("Streams of events and changes")
struct StreamTests {
    @Test("ForwardEvents yields each event once, in the order sent")
    func forwardEvents() async {
        let (chimes, continuation) = AsyncStream.makeStream(of: Chime.self)
        let frame = Schedule {
            UpdateEvents()
            Chimer()
            ForwardEvents(to: continuation).after(Chimer.self)
        }
        var world = World()
        world.resources.insert(ChimeFrame())
        for _ in 0 ..< 3 { frame.run(on: &world) }
        world.send(Chime(number: 10))
        frame.run(on: &world)
        continuation.finish()
        var received: [Int] = []
        for await chime in chimes { received.append(chime.number) }
        let expected: [Int] = [1, 2, 3, 10, 4]
        #expect(received == expected)
    }

    @Test("Two forwarders of one event type each yield every event")
    func twoForwarders() async {
        let (first, firstContinuation) = AsyncStream.makeStream(of: Chime.self)
        let (second, secondContinuation) = AsyncStream.makeStream(of: Chime.self)
        let frame = Schedule {
            UpdateEvents()
            Chimer()
            ForwardEvents(to: firstContinuation).after(Chimer.self)
            ForwardEvents(to: secondContinuation).after(Chimer.self)
        }
        var world = World()
        world.resources.insert(ChimeFrame())
        for _ in 0 ..< 2 { frame.run(on: &world) }
        firstContinuation.finish()
        secondContinuation.finish()
        var firstReceived: [Int] = []
        for await chime in first { firstReceived.append(chime.number) }
        var secondReceived: [Int] = []
        for await chime in second { secondReceived.append(chime.number) }
        let expected: [Int] = [1, 2]
        #expect(firstReceived == expected)
        #expect(secondReceived == expected)
    }

    @Test("A forwarder before the sender yields each event one frame late, and none are lost")
    func forwarderBeforeSender() async {
        let (chimes, continuation) = AsyncStream.makeStream(of: Chime.self)
        let frame = Schedule {
            UpdateEvents()
            ForwardEvents(to: continuation)
            Chimer().after(ForwardEvents<Chime>.self)
        }
        var world = World()
        world.resources.insert(ChimeFrame())
        for _ in 0 ..< 3 { frame.run(on: &world) }
        continuation.finish()
        var received: [Int] = []
        for await chime in chimes { received.append(chime.number) }
        let expected: [Int] = [1, 2]
        #expect(received == expected)
    }

    @Test("ForwardChanges yields every component on its first run, then only those added or changed")
    func forwardChanges() async {
        let (changes, continuation) = AsyncStream.makeStream(of: QueryRow<Health>.self)
        let frame = Schedule {
            Healer()
            ForwardChanges(to: continuation).after(Healer.self)
        }
        var world = World()
        let wounded = world.spawn(Health(1))
        let healthy = world.spawn(Health(5))
        frame.run(on: &world)
        frame.run(on: &world)
        world.insert(Health(1), into: healthy)
        let newcomer = world.spawn(Health(7))
        frame.run(on: &world)
        continuation.finish()
        var received: [String] = []
        for await row in changes { received.append("\(row.entity.index):\(row.components.current)") }
        let expected: [String] = [
            "\(wounded.index):2", "\(healthy.index):5",
            "\(healthy.index):2", "\(newcomer.index):7",
        ]
        #expect(received.prefix(2).sorted() == expected.prefix(2).sorted())
        #expect(received.dropFirst(2).sorted() == expected.dropFirst(2).sorted())
        let expectedCount = 4
        #expect(received.count == expectedCount)
    }

    @Test("A forwarder whose stream's consumer stopped runs without effect")
    func stoppedConsumer() {
        let (_, continuation) = AsyncStream.makeStream(of: Chime.self)
        continuation.finish()
        let frame = Schedule {
            UpdateEvents()
            Chimer()
            ForwardEvents(to: continuation).after(Chimer.self)
        }
        var world = World()
        world.resources.insert(ChimeFrame())
        frame.run(on: &world)
        let expected = 1
        #expect(world.resources[ChimeFrame.self].number == expected)
    }
}

extension StreamTests {
    @Test("Copies of one forwarder share its place in the events, so each event is yielded once")
    func copiesSharePlace() async {
        let (chimes, continuation) = AsyncStream.makeStream(of: Chime.self)
        let forwarder = ForwardEvents(to: continuation)
        let frame = Schedule {
            UpdateEvents()
            Chimer()
            forwarder.after(Chimer.self)
            forwarder.after(Chimer.self)
        }
        var world = World()
        world.resources.insert(ChimeFrame())
        for _ in 0 ..< 2 { frame.run(on: &world) }
        continuation.finish()
        var received: [Int] = []
        for await chime in chimes { received.append(chime.number) }
        let expected: [Int] = [1, 2]
        #expect(received == expected)
    }

    @Test("A forwarder's stream does not end when the schedule holding it is gone")
    func streamOutlivesSchedule() async {
        let (chimes, continuation) = AsyncStream.makeStream(of: Chime.self)
        do {
            let frame = Schedule {
                UpdateEvents()
                Chimer()
                ForwardEvents(to: continuation).after(Chimer.self)
            }
            var world = World()
            world.resources.insert(ChimeFrame())
            frame.run(on: &world)
        }
        let late = Chime(number: 9)
        continuation.yield(late)
        continuation.finish()
        var received: [Int] = []
        for await chime in chimes { received.append(chime.number) }
        let expected: [Int] = [1, 9]
        #expect(received == expected)
    }
}
