# Known issues

Swift compiler and runtime bugs this package works around, recorded here rather than filed
upstream. Each names the workaround in place; recheck them when the toolchain changes.

## Runtime

- **A key path into a row whose pack is generic crashes.** In a function generic over `each C`,
  `view.map(\.entity)` on a `QueryView<repeat each C>` traps in
  `DecodedMetadataBuilder::beginPackExpansion` (Swift 6.4, debug builds). The same key path on a
  concrete view works. Workaround: a closure, `view.map { $0.entity }`.

## Compiler

- **Destructuring a tuple built from `(each T).Value` fails.** A `for` pattern or member access
  (`row.3`) on `(entity: Entity, repeat (each T).Value)` reports "pattern cannot match values of
  type …" when the pack is bound at that call. Workaround: `QueryView` and `QueryRow` are
  generic over the values (`QueryView<repeat (each T).Value>`), not over the terms.
- **Appending types to a pack in a method's result fails to type-check** once the receiver's
  pack holds two or more types (`Query<A, B>.anyOf(C.self, D.self) -> Query<A, B, C?, D?>`).
  Workaround: `AnyOf` is a term inside one pack.
- **Initializers cannot fix a pack to a given number of types** (`init<P, Q>(…) where (repeat
  each T) == (P, Q)`), so specialization happens in overloads on the query's exact type
  (`tools/QueryShapes`).
- **Forwarding a pack tuple as a value crashes SILGen** (`QueryRow(entity:components: values)`
  with `values: (repeat each C)`). Workaround: `(repeat each values)`.
- **A one-element pack given a tuple is ambiguous** (`QueryRow(entity:components: v0)` with
  `v0: (A?, B?)` could be one element or two). Workaround: name the type,
  `QueryRow<(A?, B?)>(…)`.
