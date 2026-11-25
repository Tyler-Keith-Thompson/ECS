# Reacting to Changes

Find the components that changed or went away, run code as changes happen, and pass messages
between the parts of a program.

## Overview

A world gives you two ways to respond to what happens in it. You can look later: change
detection, removal records and events keep track of what happened, and the code that cares reads
them when it next runs. Or you can respond at once: hooks and observers run a closure as part of
the change that fired them.

Look later when the response belongs in a system that runs every step anyway, such as a health
bar that redraws when the health changed. Respond at once when other data must never fall out of
step with the world, such as a directory of entities by name.

### Find Components That Changed

Every component remembers the ``World/changeTick`` at which it was added and the one at which it
last changed. The `changed(_:since:)` and `added(_:since:)` filters pass only the entities whose
component is newer than a tick. Inside a system run by a schedule, leave out the tick:
`changed(Health.self)` then means "changed since this system last ran". See "Find what changed"
in <doc:QueryingAWorld>.

Those filters check every entity that holds the type. When few of many entities change between
visits, ``World/trackChanges(of:)`` keeps a log of the type's changes, so the filters cost time in
proportion to what changed rather than to how many entities hold the type.

### Find Components That Went Away

A removed component leaves nothing behind to filter on, so the world records removals instead.
``World/removed(_:by:)`` returns the entities that lost a component of a type since a reader last
asked, whether by removal or by despawn. A reader is any type you choose, so different parts of a
program each keep their own place.

Recording starts at the first call to `removed(_:by:)`, or at ``World/trackRemovals(of:)``;
removals before that aren't reported. The record is kept as events are, so each
``World/updateEvents()`` drops the removals from before the previous one.

### Run Code When Components Come and Go

A *hook* is a closure the world runs when an entity gains, is given or loses a component of a
type: ``World/onAdd(_:perform:)-27g0l``, ``World/onInsert(_:perform:)`` and
``World/onRemove(_:perform:)-2t2p``. Given a ``Query`` in place of a type, `onAdd` and `onRemove`
run when an entity starts or stops matching the query. A hook runs after the operation that fired
it has finished, so it sees the whole spawn or insert.

Hooks don't run for changes made in place, through the subscript or an update. Use change
detection for those.

The following example keeps a list of the fallen as they're despawned, and reads the same
despawn from the removal record afterward:

```swift
struct Fallen: Resource { var names: [String] = [] }
enum TallyReader {}

var world = World()
world.resources.insert(Fallen())
_ = world.removed(Health.self, by: TallyReader.self)
world.onRemove(Name.self) { world, _, name in
    world.resources[Fallen.self].names.append(name.value)
}

let knight = world.spawn(Name(value: "knight"), Health(current: 0))
world.despawn(knight)

print(world.resources[Fallen.self].names)
// Prints "["knight"]"
print(world.removed(Health.self, by: TallyReader.self) == [knight])
// Prints "true"
```

### Trigger Events on an Entity

An ``EntityEvent`` tells one entity that something happened to it, such as a barrel being hit.
Register observers with ``World/observe(_:on:perform:)`` for one entity, or
``World/observe(_:perform:)`` for every entity, and fire the event with
``World/trigger(_:on:)``. The observers run before `trigger(_:on:)` returns. An event whose type
propagates moves up the hierarchy (``ChildOf``) after each entity's observers run, until it
reaches the root or an observer stops it.

### Send Messages Between Systems

An ``Event`` is a message one part of a program sends and other parts read later, such as a
collision that a damage system and a sound system both respond to. Send one with
``World/send(_:)``, and read it with ``World/readEvents(_:by:)``. Each reader reads each event
once.

Events wait in two buffers, and each ``World/updateEvents()`` drops the older one, so an event can
be read for the rest of the step it was sent in and all of the next. Call `updateEvents()` once a
step, such as with the `UpdateEvents` system at the start of a frame. Without it, events are never
dropped.
