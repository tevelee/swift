# Closure receiver bindings: experimental prototype

Revision 0.12 selects one ordinary closure parameter as the implicit receiver:

```swift
func withValue<T, R>(_ value: T, _ body: (T) -> R) -> R { body(value) }
let length = withValue("hello") { self in count }
let render: (Document, Theme) -> String = { self, theme in title + theme.separator }
```

Enable `-enable-experimental-feature ClosureReceiverParameters` with the patched compiler. Explicit `self` selects lookup; the callback type, parameter position, ownership, and invocation remain ordinary Swift. `@receiver`, Kotlin-style receiver function types, and lexical dotted callback invocation are not part of this revision.

Read the [pitch](ClosureReceiverParameters/PITCH.md) for motivation, invariants, alternatives, and the unresolved typed-self compatibility question. The [implementation record](ClosureReceiverParameters/IMPLEMENTATION.md) separates current validation from production work. Configuration helpers are illustrative library code, not standard-library additions.

The pitch now develops request configuration, import-report accumulation, noncopyable packet construction, and task-group search with ordinary and receiver forms. The matching executable fixture checks all four examples in ordinary and optimized execution.
