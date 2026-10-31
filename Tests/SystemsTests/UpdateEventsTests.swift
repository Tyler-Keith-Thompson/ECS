// Each test is self-contained: the systems it runs are declared inside it or below.

import ECSTestSupport
import Systems
import Testing
import WorldModule

struct Ping: Event, Equatable {
    var number: Int
}

/// Sends one `Ping` per run, numbered by the runs so far.
struct Pinger: System {
    func run(in world: inout World) {
        world.resources[PingLog.self].sent += 1
        world.send(Ping(number: world.resources[PingLog.self].sent))
    }
}

/// Records the pings it reads.
struct PingListener: System {
    func run(in world: inout World) {
        let pings = Array(world.readEvents(Ping.self, by: PingListener.self))
        world.resources[PingLog.self].read.append(contentsOf: pings.map(\.number))
    }
}

struct PingLog: Resource {
    var sent = 0
    var read: [Int] = []
}

@Suite("UpdateEvents")
struct UpdateEventsTests {
    @Test("A listener written before the sender reads every event, one frame late")
    func listenerBeforeSender() {
        let frame = Schedule {
            UpdateEvents()
            PingListener()
            Pinger()
        }
        var world = World()
        world.resources.insert(PingLog())
        for _ in 0 ..< 3 { frame.run(on: &world) }
        let read = world.resources[PingLog.self].read
        let expected = [1, 2]
        #expect(read == expected)
    }

    @Test("A listener written after the sender reads every event in the frame it was sent")
    func listenerAfterSender() {
        let frame = Schedule {
            UpdateEvents()
            Pinger()
            PingListener()
        }
        var world = World()
        world.resources.insert(PingLog())
        for _ in 0 ..< 3 { frame.run(on: &world) }
        let read = world.resources[PingLog.self].read
        let expected = [1, 2, 3]
        #expect(read == expected)
    }

    @Test("Events are dropped two frames after they were sent")
    func dropped() {
        let frame = Schedule { UpdateEvents() }
        var world = World()
        world.send(Ping(number: 1))
        frame.run(on: &world)
        let afterOne = world.events(Ping.self).count
        frame.run(on: &world)
        let afterTwo = world.events(Ping.self).count
        #expect(afterOne == 1)
        #expect(afterTwo == 0)
    }
}
