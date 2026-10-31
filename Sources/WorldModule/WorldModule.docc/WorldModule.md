# ``WorldModule``

Entities, their components and resources, with queries, in-place updates and deferred commands.

## Overview

A ``World`` stores the components of each type in a sparse set: a dense array of components and
a sparse array from entity slot to position. Reading, adding and removing a component are O(1),
and walking a type is a walk over contiguous memory. A query or update of several types walks the
type the fewest entities hold and looks the others up.

## Topics

### The world

- ``World``
- ``Entity``
- ``Component``
- ``EntitiesView``

### Reading many entities

- ``QueryView``
- ``EntityQueryView``
- ``QueryRow``
- ``QueryFilter``

### Change detection

- ``ChangeTick``

### Hierarchy

- ``AncestorsView``
- ``DescendantsView``
- ``CyclicHierarchy``
- ``HierarchyError``

### Events

- ``Event``
- ``Events``
- ``EventsView``

### Deferred changes

- ``Commands``

### Resources

- ``Resource``
- ``Resources``

### Errors

- ``StaleEntity``
- ``MissingComponent``
- ``MissingResource``
