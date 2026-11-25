# Relating Entities

Link entities to one another, build trees of parents and children, and query entities by what
they're linked to.

## Overview

Some state belongs to a pair of entities rather than to one: a unit likes another, a turret aims
at a ship, a button sits on a panel. A *relation* stores that kind of link, and the *hierarchy* is
the relation that makes trees of parents and children.

### Link Entities with Relations

Declare a relation as a type that conforms to ``Relation``, then link a source entity to a target
with ``World/relate(_:_:to:)`` and unlink it with ``World/unrelate(_:_:from:)``. Read the links in
either direction: ``World/targets(_:of:)`` lists what a source relates to, and
``World/sources(_:of:)`` lists what relates to a target.

A relation can carry values, one per link, such as the amount one entity owes another. It
chooses two behaviors with static properties:

- ``Relation/isExclusive`` limits a source to one target, so relating it to a new target
  replaces the old one.
- ``Relation/onTargetDespawn`` says what despawning a target does to its sources: remove their
  links, the default, or despawn them too.

A source holds its links in a ``Targets`` component, which you read and filter on like any other
component. To visit only the sources of one target, filter a query with `.related(_:to:)`, which
uses the world's index of each target's sources rather than walking every source.

### Build a Hierarchy

The hierarchy is the ``ChildOf`` relation: exclusive, so each entity has at most one parent, and
despawning a parent despawns its children, and theirs in turn. Spawn an entity under a parent
with ``World/spawn(_:childOf:)``, or move an existing one with ``World/addChild(_:to:)``, which
throws ``CyclicHierarchy`` rather than make an entity its own ancestor. Walk the tree with
``World/parent(of:)``, ``World/children(of:)``, ``World/ancestors(of:)`` and
``World/descendants(of:)``.

Because the hierarchy is a relation, the same query filters work on it:
`.related(ChildOf.self, to: ship)` visits the children of `ship`, and
`.without(Targets<ChildOf>.self)` visits the roots.

The following example aims a ship's turret at a comet, then at a moon, and despawns the ship
with its turret:

```swift
struct AimsAt: Relation {
    static var isExclusive: Bool { true }
}

var world = World()
let ship = world.spawn(Name(value: "ship"))
let turret = world.spawn(Name(value: "turret"), childOf: ship)
let comet = world.spawn(Name(value: "comet"))
let moon = world.spawn(Name(value: "moon"))

world.relate(turret, AimsAt(), to: comet)
world.relate(turret, AimsAt(), to: moon)
print(world.targets(AimsAt.self, of: turret) == [moon])
// Prints "true"

world.despawn(ship)
print(world.contains(turret), world.sources(AimsAt.self, of: moon).isEmpty)
// Prints "false true"
```

Observers of an ``EntityEvent`` that propagates also use the hierarchy: the event moves from the
entity it was triggered on up to each of its ancestors. ``Commands`` record changes to relations
and to the hierarchy, to apply after a query or update.
