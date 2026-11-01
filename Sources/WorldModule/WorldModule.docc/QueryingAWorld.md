# Querying a World

Find the entities that hold the components you need, read those components, and change them in place.

## Overview

Most of the work in an entity component system is a loop over many similar entities: move
everything that has a velocity, damage everything standing in fire, draw everything that has a
sprite. A *query* describes which entities such a loop visits and which components it reads. A
world answers a query with a lazy view of the matching entities, and an *update* uses the same
description to change components where they're stored.

### Read the entities that hold a set of components

Pass component types to a world's `query(_:)` method to visit every entity that holds all of
them. Each row is a tuple of the entity, labeled `entity`, followed by one component per type, in
the order you listed them:

```swift
var world = World()
world.spawn(Name(value: "comet"), Position(x: 1, y: 2), Velocity(dx: 3, dy: 4))
world.spawn(Name(value: "rock"), Position(x: 0, y: 0))

for (_, name, position, velocity) in world.query(Name.self, Position.self, Velocity.self) {
    print(name.value, position.x + velocity.dx)
    // Prints "comet 4.0"
}
```

The rock has no velocity, so the query skips it.

Only the entity is labeled, because a tuple's labels can't be named after its element types. To
work with rows in a closure, such as when you sort or filter them, name the components by
destructuring the row rather than reaching for them by position:

```swift
var world = World()
world.spawn(Name(value: "comet"), Health(current: 3))
world.spawn(Name(value: "moon"), Health(current: 9))

let strongest = world.query(Name.self, Health.self)
    .sorted { first, second in
        let (_, _, firstHealth) = first
        let (_, _, secondHealth) = second
        return firstHealth.current > secondHealth.current
    }
    .map { (_, name, _) in name.value }
print(strongest)
// Prints "["moon", "comet"]"
```

A view is a snapshot of the world at the moment you asked for it. Changing the world while you
iterate the view doesn't change the rows it shows, so you can despawn entities or insert
components from inside the loop.

### Narrow a query with a filter

Some conditions matter without your needing to read the component. A *filter* adds them:
``QueryView/with(_:)`` requires types, ``QueryView/without(_:)`` excludes them, and
``QueryView/anyOf(_:)`` requires an entity to pass at least one of several filters. The rows still
carry only the components you asked to read:

```swift
var world = World()
world.spawn(Name(value: "comet"), Velocity(dx: 1, dy: 0))
world.spawn(Name(value: "statue"), Velocity(dx: 1, dy: 0), Frozen())
world.spawn(Name(value: "rock"))

var moving: [String] = []
for (_, name) in world.query(Name.self).with(Velocity.self).without(Frozen.self) {
    moving.append(name.value)
}
print(moving)
// Prints "["comet"]"

let still = world.query(Name.self).anyOf(.with(Frozen.self), .without(Velocity.self))
print(still.count)
// Prints "2"
```

A ``QueryFilter`` is a value of its own, so you can build one once and apply it with
``QueryView/filtered(by:)``, ``Query/filtered(by:)``, or the `where` argument of an update.

To visit entities without reading any component, call `query()` with no types and narrow the
``EntityQueryView`` it returns:

```swift
var world = World()
world.spawn(Position(x: 0, y: 0), Frozen())
world.spawn(Position(x: 1, y: 1))

for entity in world.query().with(Frozen.self) {
    world.remove(Frozen.self, from: entity)
}
print(world.query().with(Frozen.self).count)
// Prints "0"
```

### Describe a query once with a query value

A ``Query`` holds a query's terms and filter as a value that doesn't belong to any world. Store it,
compare it with another, and run it against any world:

```swift
let movers = Query(Position.self, Velocity.self).without(Frozen.self)

var level = World()
level.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
level.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0), Frozen())

var copy = level
copy.spawn(Position(x: 3, y: 3), Velocity(dx: 0, dy: 1))

print(level.query(movers).count, copy.query(movers).count)
// Prints "1 2"
```

### Match any of several components

A query's terms can include an ``AnyOf`` group. An entity matches the group when it holds at least
one of its types, and the row holds a tuple with one optional per type, `nil` where the entity
lacks that type. The following example adds up the forces that push each entity, whichever of
wind and thrust it feels (`Wind` and `Thrust` are components with a `force` property):

```swift
var world = World()
world.spawn(Name(value: "kite"), Wind(force: 3))
world.spawn(Name(value: "rocket"), Thrust(force: 5), Wind(force: 1))
world.spawn(Name(value: "rock"))

var forces: [String] = []
for (_, name, (wind, thrust)) in world.query(Query(Name.self, AnyOf<Wind, Thrust>.self)) {
    forces.append("\(name.value): \((wind?.force ?? 0) + (thrust?.force ?? 0))")
}
print(forces)
// Prints "["kite: 3.0", "rocket: 6.0"]"
```

The rock holds neither type, so the query skips it.

### Change components in place

To change components while you visit them, use an update instead of a view. The method visits
every entity that holds the component you change and the components you read. Its closure receives
the component to change as an `inout` argument, and a ``QueryRow`` carrying the entity and the
components it reads:

```swift
var world = World()
let comet = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 2))
let statue = world.spawn(Position(x: 5, y: 5), Velocity(dx: 1, dy: 1), Frozen())

world.update(Position.self, reading: Velocity.self, where: .without(Frozen.self)) { position, row in
    position.x += row.components.dx
    position.y += row.components.dy
}
print(world[Position.self, of: comet])
// Prints "Position(x: 1.0, y: 2.0)"
print(world[Position.self, of: statue])
// Prints "Position(x: 5.0, y: 5.0)"
```

An update can change up to three component types at once, and can take a ``Query`` in place of
the types it reads, which lets it read ``AnyOf`` groups:

```swift
var world = World()
let kite = world.spawn(Position(x: 0, y: 0), Wind(force: 2))
let rocket = world.spawn(Position(x: 0, y: 0), Thrust(force: 5))

world.update(Position.self, over: Query(AnyOf<Wind, Thrust>.self)) { position, row in
    let (wind, thrust) = row.components
    position.x += (wind?.force ?? 0) + (thrust?.force ?? 0)
}
print(world[Position.self, of: kite].x, world[Position.self, of: rocket].x)
// Prints "2.0 5.0"
```

An update can't read a type it changes, and its closure can't reach the world while it runs. To
spawn, despawn or add components along the way, such as despawning the entities whose health runs
out, record the changes in ``Commands`` and apply them after the update.

### Find what changed

The world stamps every component it adds or changes with its current ``World/changeTick``.
Filter on those stamps to visit only the entities whose components are new or changed:
``Query/added(_:since:)`` passes the entities that gained a component after a tick, and
``Query/changed(_:since:)`` the ones whose component was added or changed after it.

```swift
var world = World()
let hero = world.spawn(Name(value: "hero"), Health(current: 10))
world.spawn(Name(value: "guard"), Health(current: 8))

let checkpoint = world.changeTick
world.advanceChangeTick()
world[Health.self, of: hero].current -= 3

for (_, name, health) in world.query(Name.self, Health.self).changed(Health.self, since: checkpoint) {
    print(name.value, health.current)
    // Prints "hero 7"
}
```

Without a tick, the filters compare against the world's ``World/lastRun``. A schedule sets it to
the running system's previous run, so in a system, `changed(Health.self)` means "changed since
this system last ran".

### Filter in a system's parameters

A system receives a query as a parameter, already bound to the world it runs on, and iterates it
directly. Because a system's parameters are types, it names its filter with filter types in
``Query/Where``: ``With``, ``Without``, ``Added``, ``Changed``, ``Allows``, and ``AnyOf`` of filter
types. For example, a system that visits the entities whose health changed since its previous
run, and that aren't frozen, takes a parameter of type
`Query<Health>.Where<Changed<Health>, Without<Frozen>>`, and iterates it like a view.

### Speed up frequent queries

A query of several types walks the storage of the type the fewest entities hold, and looks each
entity up in the others. Three tools make frequent visits cheaper. None of them changes which
entities a query finds, only how it finds them.

A *group*, made with `group(_:)`, keeps a set of component types packed in the same order, so a
query or update of exactly those types walks them side by side with no lookups. Group the types
you visit together on every step:

```swift
var world = World()
let comet = world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))
world.group(Position.self, Velocity.self)

world.update(Position.self, reading: Velocity.self) { position, row in
    position.x += row.components.dx
}
print(world[Position.self, of: comet].x)
// Prints "1.0"
```

A *cached query*, made with `cache(_:)`, keeps a list of the entities that match a query's
structure. A visit whose conditions imply the cache's walks that list instead of a whole column.
Cache a query you run often that excludes most of the entities it would otherwise walk:

```swift
var world = World()
for index in 0 ..< 10 {
    world.spawn(Position(x: Double(index), y: 0), Velocity(dx: 1, dy: 0), Asleep())
}
world.spawn(Position(x: 0, y: 0), Velocity(dx: 1, dy: 0))

let awake = Query(Position.self, Velocity.self).without(Asleep.self)
world.cache(awake)
print(world.query(awake).count)
// Prints "1"
```

A *value index*, made with `index(_:)`, maps each value of a `Hashable` component type to the
entities holding it, so `lookup(_:)` finds them without walking the type's storage. Index a type
you look entities up by and whose values change rarely, such as a name:

```swift
var world = World()
let ada = world.spawn(Name(value: "ada"), Health(current: 3))
world.spawn(Name(value: "bob"), Health(current: 4))
world.index(Name.self)

print(world.lookup(Name(value: "ada")) == [ada])
// Prints "true"
```

To find entities by one property of a component rather than by the whole value, index the
property's key path and look it up with `lookup(_:equals:)`. The component type doesn't need to
be `Hashable`, only the property:

```swift
struct Berth: Component { var dock: Int, number: Int }

var world = World()
let ferry = world.spawn(Berth(dock: 2, number: 14))
world.spawn(Berth(dock: 3, number: 9))
world.index(\Berth.number)

print(world.lookup(\Berth.number, equals: 14) == [ferry])
// Prints "true"
```

To find the entities whose property falls in a range, or to visit them in the order of a
property, index the key path ordered with `index(ordered:)`. The property's type needs to be
`Comparable`. `lookup(_:in:)` takes any range and returns the entities in the property's order,
and `entities(sortedBy:)` returns every entity holding the component in that order:

```swift
var world = World()
let fresh = world.spawn(Name(value: "fresh"), Health(current: 9))
let wounded = world.spawn(Name(value: "wounded"), Health(current: 2))
let dying = world.spawn(Name(value: "dying"), Health(current: 1))
world.index(ordered: \Health.current)

print(world.lookup(\Health.current, in: ..<3) == [dying, wounded])
// Prints "true"
print(world.entities(sortedBy: \Health.current) == [dying, wounded, fresh])
// Prints "true"
```

An ordered index costs more to keep than an index by value, since each insert, removal and
despawn finds the entity's place in sorted order, so index a key path ordered only when you look
it up by range or order.
