// Each test is self-contained: it builds its own world and states its own expectations.

import ECSTestSupport
import PropertyBased
import Testing
import WorldModule

struct Hit: Event, Equatable {
    var amount: Int
}

struct Spoken: Event, Equatable {
    var word: String
}

enum FirstReader {}
enum SecondReader {}

@Suite("Events")
struct EventsTests {
    @Test("A world with no events of a type reads none and holds none")
    func noEvents() {
        var world = World()
        let held = Array(world.events(Hit.self))
        let read = Array(world.readEvents(Hit.self, by: FirstReader.self))
        let expected: [Hit] = []
        #expect(held == expected)
        #expect(read == expected)
    }

    @Test("The first event sent of a type creates the world's Events resource for it")
    func sendCreatesResource() {
        var world = World()
        let before = world.resources.contains(Events<Hit>.self)
        world.send(Hit(amount: 1))
        let after = world.resources.contains(Events<Hit>.self)
        let held = world.resources[Events<Hit>.self].count
        let one = 1
        #expect(!before)
        #expect(after)
        #expect(held == one)
    }

    @Test("Listing the events held marks none read, and the events value lists read ones too")
    func listingMarksNothingRead() {
        var world = World()
        world.send(Hit(amount: 1))
        world.send(Hit(amount: 2))
        let listed = Array(world.events(Hit.self))
        let read = Array(world.readEvents(Hit.self, by: FirstReader.self))
        let all = Array(world.resources[Events<Hit>.self].all)
        let expected = [Hit(amount: 1), Hit(amount: 2)]
        #expect(listed == expected)
        #expect(read == expected)
        #expect(all == expected)
    }

    @Test("Updating events ends an update for every event type at once")
    func updateEveryType() {
        var world = World()
        world.send(Hit(amount: 1))
        world.send(Spoken(word: "ow"))
        world.updateEvents()
        world.updateEvents()
        let hits = Array(world.events(Hit.self))
        let words = Array(world.events(Spoken.self))
        let noHits: [Hit] = []
        let noWords: [Spoken] = []
        #expect(hits == noHits)
        #expect(words == noWords)
    }

    @Test("Sent events are read in the order they were sent")
    func order() {
        var world = World()
        world.send(Hit(amount: 1))
        world.send(Hit(amount: 2))
        world.send(Hit(amount: 3))
        let read = Array(world.readEvents(Hit.self, by: FirstReader.self))
        let expected = [Hit(amount: 1), Hit(amount: 2), Hit(amount: 3)]
        #expect(read == expected)
    }

    @Test("A reader reads each event once")
    func readOnce() {
        var world = World()
        world.send(Hit(amount: 1))
        _ = world.readEvents(Hit.self, by: FirstReader.self)
        world.send(Hit(amount: 2))
        let second = Array(world.readEvents(Hit.self, by: FirstReader.self))
        let third = Array(world.readEvents(Hit.self, by: FirstReader.self))
        let expectedSecond = [Hit(amount: 2)]
        let expectedThird: [Hit] = []
        #expect(second == expectedSecond)
        #expect(third == expectedThird)
    }

    @Test("Readers keep separate places in the events")
    func independentReaders() {
        var world = World()
        world.send(Hit(amount: 1))
        let first = Array(world.readEvents(Hit.self, by: FirstReader.self))
        let second = Array(world.readEvents(Hit.self, by: SecondReader.self))
        let expected = [Hit(amount: 1)]
        #expect(first == expected)
        #expect(second == expected)
    }

    @Test("Event types are kept apart")
    func separateTypes() {
        var world = World()
        world.send(Hit(amount: 1))
        world.send(Spoken(word: "ow"))
        let hits = Array(world.readEvents(Hit.self, by: FirstReader.self))
        let words = Array(world.readEvents(Spoken.self, by: FirstReader.self))
        let expectedHits = [Hit(amount: 1)]
        let expectedWords = [Spoken(word: "ow")]
        #expect(hits == expectedHits)
        #expect(words == expectedWords)
    }

    @Test("An event survives one update and is dropped by the second")
    func lifetime() {
        var world = World()
        world.send(Hit(amount: 1))
        world.updateEvents()
        let afterOne = Array(world.events(Hit.self))
        world.updateEvents()
        let afterTwo = Array(world.events(Hit.self))
        let expectedAfterOne = [Hit(amount: 1)]
        let expectedAfterTwo: [Hit] = []
        #expect(afterOne == expectedAfterOne)
        #expect(afterTwo == expectedAfterTwo)
    }

    @Test("A reader that runs before the sender still reads the event in the next update")
    func readerBeforeSender() {
        var world = World()
        _ = world.readEvents(Hit.self, by: FirstReader.self)
        world.send(Hit(amount: 7))
        world.updateEvents()
        let read = Array(world.readEvents(Hit.self, by: FirstReader.self))
        let expected = [Hit(amount: 7)]
        #expect(read == expected)
    }

    @Test("A reader that skips two updates misses the events dropped in between")
    func missedEvents() {
        var world = World()
        world.send(Hit(amount: 1))
        world.updateEvents()
        world.send(Hit(amount: 2))
        world.updateEvents()
        world.send(Hit(amount: 3))
        let read = Array(world.readEvents(Hit.self, by: FirstReader.self))
        let expected = [Hit(amount: 2), Hit(amount: 3)]
        #expect(read == expected)
    }

    @Test("Reading events does not change what the world holds")
    func readingKeepsEvents() {
        var world = World()
        world.send(Hit(amount: 1))
        _ = world.readEvents(Hit.self, by: FirstReader.self)
        let held = Array(world.events(Hit.self))
        let expected = [Hit(amount: 1)]
        #expect(held == expected)
    }

    @Test("A copy of a world keeps its events and its readers' places")
    func copies() {
        var world = World()
        world.send(Hit(amount: 1))
        _ = world.readEvents(Hit.self, by: FirstReader.self)
        world.send(Hit(amount: 2))
        var copy = world
        copy.send(Hit(amount: 3))
        let fromCopy = Array(copy.readEvents(Hit.self, by: FirstReader.self))
        let fromOriginal = Array(world.readEvents(Hit.self, by: FirstReader.self))
        let expectedCopy = [Hit(amount: 2), Hit(amount: 3)]
        let expectedOriginal = [Hit(amount: 2)]
        #expect(fromCopy == expectedCopy)
        #expect(fromOriginal == expectedOriginal)
    }

    @Test("Updating events leaves other resources alone")
    func otherResources() {
        var world = World()
        world.resources.insert(Clock(ticks: 4))
        world.send(Hit(amount: 1))
        world.updateEvents()
        let ticks = world.resources[Clock.self].ticks
        let expected = 4
        #expect(ticks == expected)
    }

    @Test("Sending through commands sends when the commands apply")
    func commands() {
        var world = World()
        var commands = Commands()
        commands.send(Hit(amount: 5))
        let before = world.events(Hit.self).count
        world.apply(commands)
        let after = Array(world.events(Hit.self))
        let expected = [Hit(amount: 5)]
        #expect(before == 0)
        #expect(after == expected)
    }

    @Test("An events value counts what it holds and drops the older buffer on update")
    func eventsValue() {
        var events = Events<Hit>()
        #expect(events.isEmpty)
        events.send(Hit(amount: 1))
        events.update()
        events.send(Hit(amount: 2))
        #expect(events.count == 2)
        events.update()
        let held = Array(events.all)
        let expected = [Hit(amount: 2)]
        #expect(held == expected)
        events.update()
        #expect(events.isEmpty)
    }

    @Test("Any interleaving of sends, reads and updates agrees with a model that keeps every event", .tags(.randomized))
    func agreesWithModel() async {
        let operations = Gen.int(in: 0 ... 1_000).array(of: 0 ... 200)
        await propertyCheck(count: 200, input: operations) { operations in
            Self.run(operations)
        }
    }

    @Test("Long seeded interleavings agree with a model that keeps every event", .tags(.randomized), arguments: [1, 2, 3, 42, 1_000] as [UInt])
    func seeded(seed: UInt) {
        var generator = SeededRandomNumberGenerator(seed: seed)
        let operations = (0 ..< 5_000).map { _ in Int.random(in: 0 ... 1_000, using: &generator) }
        Self.run(operations)
    }

    /// Replays `operations` on a world and on a naive model: every event ever sent, the update
    /// each was sent in, and each reader's count of events read.
    static func run(_ operations: [Int]) {
        var world = World()
        var sent: [(hit: Hit, update: Int)] = []
        var update = 0
        var firstNext = 0
        var secondNext = 0
        for code in operations {
            switch code % 4 {
            case 0, 1:
                let hit = Hit(amount: code)
                world.send(hit)
                sent.append((hit, update))
            case 2:
                world.updateEvents()
                update += 1
            default:
                let isFirst = code % 8 == 3
                let next = isFirst ? firstNext : secondNext
                let expected = sent.indices
                    .filter { $0 >= next && sent[$0].update >= update - 1 }
                    .map { sent[$0].hit }
                let read = isFirst
                    ? Array(world.readEvents(Hit.self, by: FirstReader.self))
                    : Array(world.readEvents(Hit.self, by: SecondReader.self))
                #expect(read == expected)
                if isFirst { firstNext = sent.count } else { secondNext = sent.count }
            }
            let held = Array(world.events(Hit.self))
            let expectedHeld = sent.filter { $0.update >= update - 1 }.map(\.hit)
            #expect(held == expectedHeld)
        }
    }
}
