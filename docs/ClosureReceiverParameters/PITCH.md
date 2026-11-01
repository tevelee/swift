# Receiver function types

* Proposal: SE-NNNN (unassigned)
* Authors: [Laszlo Teveli](https://github.com/tevelee)
* Review Manager: TBD
* Status: **Pitch draft** — revision 0.8; not submitted for review
* Implementation: Experimental [compiler](https://github.com/tevelee/swift/tree/feature/closure-receiver-parameters) and [SwiftSyntax](https://github.com/tevelee/swift-syntax/tree/feature/closure-receiver-parameters) branches; see the [implementation record](https://github.com/tevelee/swift/blob/feature/closure-receiver-parameters/docs/ClosureReceiverParameters/IMPLEMENTATION.md).
* Review: Not yet posted

## Summary of changes

Introduce receiver function types, written `T.(A) -> R`. A contextually typed closure binds its receiver as `self`, enabling implicit member access. Receiver intent survives aliases and stored callbacks. Ownership, capture, lifetime, and isolation remain governed by ordinary Swift parameter rules.

## Introduction

A **receiver function type** describes a callable whose first invocation argument supplies `self` to its closure body:

```swift
func with<T, R>(_ value: T, _ body: T.() throws -> R) rethrows -> R {
  try body(value)
}

let length = with("hello") {
  count
}
```

`T.() -> R` has a receiver of type `T`, no additional parameters, and a result of type `R`. It is not an ordinary zero-argument function. The API's callback type establishes the receiver; callers do not write `{ self in ... }`.

A **scope function** is a library use of receiver functions. This proposal introduces the language mechanism, without adding `with`, `run`, `apply`, or other helpers to the standard library.

Swift already has this receiver-scoped programming model in instance methods declared in extensions: `self` denotes the instance, and its members can be used without repeating the instance name. Receiver closures bring that familiar body syntax into a local closure, with the receiver supplied at each invocation.

## Motivation

Swift's ordinary closures can group operations on a value, but require a repeated base:

```swift
withArgument(request) { request in
  request.timeout = 30
  request.addHeader("Accept", value: "application/json")
  request.send()
}
```

An API intended to configure or inspect one value can instead advertise a receiver callback:

```swift
with(request) {
  timeout = 30
  addHeader("Accept", value: "application/json")
  send()
}
```

Here `request` is a class instance. Mutating a value-type argument requires an `inout` receiver, described below.

The receiver is part of the callback contract. A stored callback or type alias preserves that contract rather than depending on the name of the original API.

### A locally scoped counterpart to an extension

An extension already lets us write a body in the context of a particular receiver type:

```swift
extension Request {
  func sendJSON() {
    self.timeout = 30
    addHeader("Accept", value: "application/json")
    send()
  }
}

request.sendJSON()
```

Inside `sendJSON`, `self` is the `Request` instance on which the method is called. Both explicit `self.timeout` and implicit member access such as `send()` are existing Swift syntax.

A receiver closure lets us write the same body locally, without first declaring a named method:

```swift
with(request) {
  self.timeout = 30
  addHeader("Accept", value: "application/json")
  send()
}
```

The extension establishes a receiver context for a reusable member; `Request.() -> Void` establishes a receiver context for a closure. In this sense, the proposal makes the familiar extension-body model locally scoped: the callback's invocation argument becomes `self` for its body. When nested inside another instance method, that local receiver takes the place of the enclosing implicit `self` within the closure.

The analogy concerns the body's receiver scope. An extension does not literally reassign an enclosing `self`, and a receiver closure does not declare an extension, add members or conformances, or gain an extension's access privileges. The new syntax is the receiver function type; the use of `self` and implicit member access inside the body is already familiar Swift.

### Kotlin inspiration

Kotlin distinguishes ordinary argument callbacks from function types with receiver:

```kotlin
// Simplified signatures.
fun <T, R> T.let(block: (T) -> R): R
fun <T, R> T.run(block: T.() -> R): R
fun <T> T.apply(block: T.() -> Unit): T
```

`run`, `with`, and `apply` supply `this`; `let` and `also` supply an ordinary argument. The two independent choices are how the object enters the callback and whether the helper returns the callback result or the original object. [Kotlin scope functions](https://kotlinlang.org/docs/scope-functions.html)

This pitch adopts Kotlin's `T.(A) -> R` notation, using Swift's `self`, explicit return rules, effects, and ownership system. It does not introduce Kotlin's non-local returns, inline semantics, extension-style invocation of function values, or implicit receiver stack. [Kotlin function types](https://kotlinlang.org/docs/lambdas.html#function-types)

## Proposed solution

A receiver appears before a dot and the ordinary parameter list:

```swift
let describe: Document.(Theme) -> String = { theme in
  title + theme.separator
}

let text = describe(document, theme)
```

The closure has one implicit receiver named `self` and one explicitly named parameter, `theme`. A receiver function value is invoked with the receiver as its first argument. This pitch does not permit `document.describe(theme)` merely because `describe` is in scope.

A type alias preserves receiver intent:

```swift
typealias Inspector = Document.() -> String
let inspect: Inspector = { title }
let saved = inspect
let title = saved(document)
```

Existing ordinary callback types retain their meaning. For example, `(Document) -> String` does not implicitly rebind `self`.

## Detailed design

### Syntax and type identity

The basic grammar extends function types:

```text
receiver-function-type:
  receiver-type '.' '(' function-type-parameters? ')'
  'async'? throws-clause? '->' type
```

Receiver types can be generic, qualified, optional, or compound. Parentheses disambiguate compound receivers and enclose receiver parameter modifiers:

```swift
Document.() -> String
Module.Document.(Theme, Int) -> String
Document?.() -> Bool
(borrowing Resource).() -> Int
(consuming Resource).() -> Int
(inout Configuration).() -> Void
(isolated Worker).() -> Int
@Sendable Document.() async throws -> String
```

The usual function-type attributes apply to the whole function. Ownership and `isolated` inside the receiver parentheses apply to the receiver parameter. An optional receiver does not introduce optional chaining or automatic unwrapping; its members are members of `Optional` until explicitly unwrapped.

Receiver function types carry a semantic receiver marker on their first invocation parameter. This marker survives generic substitution, type aliases, function-valued storage, and module serialization. The receiver remains an ordinary argument for lowering and invocation.

`T.(A) -> R` and `(T, A) -> R` are distinct source-level function types. The initial design permits no implicit conversion between them. An adapter closure makes the change explicit:

```swift
let receiverFunction: Document.(Theme) -> String = { theme in
  title + theme.separator
}
let ordinary: (Document, Theme) -> String = { document, theme in
  receiverFunction(document, theme)
}
let adapted: Document.(Theme) -> String = { theme in
  ordinary(self, theme)
}
```

Kotlin permits interchange of non-literal function values between these shapes. Swift could explore that separately after establishing predictable overload and ownership rules. Equal calling conventions do not imply identical source-level types.

### Closure contextual typing

The expected receiver function type introduces `self` before name lookup in the closure body. An explicit closure parameter list describes only the parameters after the receiver:

```swift
let transform: Document.(Int, String) -> String = { count, suffix in
  title + String(count) + suffix
}
```

For `Document.() -> R`, an argument-less literal needs no parameter list. Anonymous parameters, when used, refer only to ordinary parameters: `$0` in `Document.(Theme) -> R` denotes the theme, not the document. `self` always denotes the receiver.

The receiver cannot also be declared in the closure signature or capture list under the same name. Capture initializers are evaluated in the enclosing context, so an explicit alias can preserve an outer instance:

```swift
with(request) { [controller = self] in
  timeout = controller.defaultTimeout
  send()
}
```

An uncontextualized closure does not infer a receiver type merely because it contains `self` or unresolved member names. Existing lexical-self behavior remains unchanged. When overload candidates provide different receiver contexts, the compiler must consider those contexts independently; it must not permanently rewrite the body according to the first candidate visited.

### Lookup and nesting

Lookup order inside a receiver closure is:

1. Ordinary lexical locals, explicit parameters, and capture aliases.
2. Members of the nearest receiver.
3. Ordinary nonmember/global declarations when the receiver has no member with that name.

An inaccessible member or incompatible member overload does not permit fallback to a same-named global. Receiver membership must be evaluated after its type is sufficiently known. There is no fallback to an enclosing instance's implicit members.

A nested receiver closure establishes a new receiver. A nested ordinary closure or local function inherits the surrounding receiver under normal capture rules. A nested type declaration creates a separate type context.

Explicit `self.member` bypasses local-name shadowing. Module qualification selects a global explicitly. An unrelated declaration merely named `self` does not establish receiver provenance.

`Self` retains its lexical type-context meaning; it does not mean the receiver's inferred type. `super` is not provided by a receiver closure. Access control, initialization rules, and dynamic dispatch remain those of explicit access through an ordinary parameter.

### Ownership and mutation

Receiver syntax does not imply mutability. A value receiver follows the same convention as the corresponding ordinary parameter. For mutation of a caller's value, use an `inout` receiver:

```swift
func configure<T>(
  _ value: inout T,
  _ body: (inout T).() throws -> Void
) rethrows {
  try body(&value)
}

configure(&settings) {
  timeout = 30
}
```

This is one exclusive access to the original storage. It creates no hidden mutable copy and does not permit escaping capture of that access. Assigning `self` replaces the whole value only where ordinary assignment through the corresponding parameter would be allowed.

For noncopyable values, receiver ownership is explicit in the callback type:

```swift
func inspect<T: ~Copyable, R>(
  _ value: borrowing T,
  _ body: (borrowing T).() throws -> R
) rethrows -> R {
  try body(value)
}
```

A consuming receiver transfers ownership into the invocation. It does not make an escaping closure that captures that value callable exactly once, or permit repeated consumption of captured state. Ordinary ownership diagnostics continue to apply. See [SE-0390](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0390-noncopyable-structs-and-enums.md) and [SE-0432](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0432-noncopyable-switch.md).

### Capture and reference cycles

A receiver is supplied at invocation time; it is not implicitly captured when the receiver function value is formed:

```swift
let describe: Document.() -> String = { title }
// No Document has been supplied yet.
let result = describe(document)
```

Nested closures can capture the receiver. Storing such a closure on that receiver can create a cycle:

```swift
with(controller) {
  onRefresh = { [self] in refresh() }
}
```

Weak capture follows ordinary rules:

```swift
with(controller) {
  onRefresh = { [weak self] in
    guard let self else { return }
    refresh()
  }
}
```

The receiver parameter is a valid root for capture-provenance checks. Strong capture, weak capture, and valid unwrapping can preserve that provenance; a different object captured under the name `self` cannot. Nested escaping reference captures retain Swift's explicit-self requirements. These rules build on [SE-0269](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0269-implicit-self-explicit-capture.md) and [SE-0365](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0365-implicit-self-weak-capture.md).

A global fallback reference must not capture or retain an otherwise unused receiver.

### Nonescapable values and lifetime dependencies

Noncopyability, nonescapability, and a callback's `@escaping` status are separate properties. A receiver callback can accept a nonescapable value during an invocation without storing that value in the function object. It cannot capture the value beyond its permitted lifetime or return a derived value without satisfying ordinary lifetime dependencies.

The receiver notation neither introduces nor removes a lifetime dependency. A helper supporting nonescapable inputs must declare the appropriate `~Escapable` constraints and lifetime relationships, just as an ordinary-parameter helper must. The initial `inspect` example returns an escapable result; it is not a complete lifetime-dependent-result API. See [SE-0446](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0446-non-escapable.md) and [SE-0465](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0465-nonescapable-stdlib-primitives.md).

### Isolation, effects, and builders

`T.() -> R` grants no actor isolation merely because `T` is an actor. `(isolated T).() -> R` carries the corresponding ordinary isolated-parameter contract. `@Sendable` applies to the function's captures; it does not automatically make a receiver value Sendable or make arbitrary cross-isolation calls valid.

`async`, throwing and typed-throwing effects retain their ordinary function-type meaning. Scope helpers must declare their own isolation and effects correctly. Result builders may transform the body, but receiver lookup does not introduce a different builder protocol or access-control scope. See [SE-0313](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0313-actor-isolation-control.md), [SE-0420](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0420-inheritance-of-actor-isolation.md), and [SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md).

### Implementation approach

Parse the receiver separately from the ordinary parameter list, then represent it as the first invocation parameter with an explicit receiver marker. Preserve that marker in canonical function types, substitution, diagnostics, mangling, and module serialization.

Contextual closure formation synthesizes a receiver parameter before body lookup. The constraint solver must keep receiver contexts separate across overload alternatives. Existing receiver-member lookup can then defer global fallback until the receiver type is known. Solution application lowers to ordinary parameter and member references.

Method-self identity must remain separate from closure-receiver identity. A new receiver cannot acquire method-specific ownership or isolation behavior merely by being called `self`.

## Source compatibility

The `T.() -> R` spelling is new. Ordinary function types, ordinary closure parameter lists, existing capture lists, and lexical-self closures retain their meaning.

This avoids reinterpreting existing typed closure parameters such as `{ (self: T) in ... }`, which already compile in Swift with ordinary parameter semantics. The explicit-binder spelling from the previous draft is no longer the proposed primary feature.

Changing an existing API parameter from `(T) -> R` to `T.() -> R` is a source-level API change. It can change arity interpretation and name lookup in literals, and existing stored callback values require explicit adapters. It should not be advertised as a compatibility-neutral annotation.

Overloads differing only in receiver intent can be ambiguous for literals that do not constrain the receiver. The design must diagnose ambiguity rather than select a receiver by declaration order.

## ABI compatibility

The receiver is passed as the first ordinary invocation argument, with its ordinary ownership convention. No receiver wrapper object or new retain operation is required.

The receiver marker is nevertheless part of source-level function-type identity. Mangling and serialized type representation must distinguish it from an ordinary first parameter. Textual interfaces must print receiver syntax and feature-guard declarations that require it. Changing a published callback type to a receiver callback is not promised to preserve an existing binary interface.

These claims require lowering, module-round-trip, and back-deployment validation; a matching runtime layout alone is insufficient.

## Implications on adoption

APIs opt in by using receiver function types. Callers then obtain receiver lookup from the contextual callback type. Existing APIs such as `map` continue to take ordinary callbacks unless explicitly redesigned or wrapped.

No standard-library scope functions are introduced. Library authors can independently choose return policy, optional behavior, mutation, ownership, and isolation. Fluent syntax such as `value.apply { ... }` also requires an actual applicable member or extension; receiver callback types do not create universal extensions on `Any`.

## Future directions

Potential follow-ups include implicit conversion between receiver and ordinary function values, receiver-aware completion and refactoring, and a separate standard-library scope-function proposal.

Multiple implicit receivers, extension-style invocation of local function values, non-local returns, and new outer-`self` labels are out of scope.

Before formal review, establish predictable overload resolution with inferred receivers, measure solver performance, and validate all ownership, lifetime, isolation, builder, and module interactions. The implementation record distinguishes the current experimental subset from this language design.

## Alternatives considered

### Explicit receiver binder

The previous draft selected a parameter at the closure literal:

```swift
users.map { self in displayName }
```

This works with ordinary callback types and makes the lookup change visible at the call site. Its limitation is that APIs and stored callback types do not advertise receiver intent. This revision chooses `T.() -> R` to express that contract and produce Kotlin-style scope-function bodies. The earlier prototype remains useful as a regression baseline; its existence does not make both syntaxes part of this proposal.

### Receiver parameter marker in the function type

`(self: T, A) -> R` would keep ownership and the receiver together in the parameter list. It is more visibly Swift-shaped, but needs a special distinction between the `self:` marker and ordinary argument labels. The dot notation instead separates the receiver from ordinary parameters directly.

### Receiver attribute

`@receiver (T, A) -> R` could mark the first parameter. It is compact to specify, but relies on a first-parameter convention. A declaration-only annotation would additionally need rules for preserving receiver intent through forwarding and storage.

### Ordinary parameters and dedicated constructs

Named parameters and `$0` already express the underlying operations and remain the clearest choice when several values are equally important. Receiver types primarily improve grouped expression and API intent.

A dedicated `with` statement would privilege one helper. A macro cannot obtain equivalent type-directed lookup, shadowing, capture diagnostics, and contextual inference merely by prefixing names with `self.`.

### Prior Swift discussion

The [2015 explicit-self closure discussion](https://forums.swift.org/t/idea-for-enabling-dsls-bind-to-self-in-closures/58) explores literal-selected receivers. [“Circling back to with”](https://forums.swift.org/t/circling-back-to-with/2766) separates the library operation from receiver syntax. These discussions motivate both alternatives; they do not constitute acceptance of this design.

The [2019 Receiver Closures discussion](https://forums.swift.org/t/receiver-closures/24020) is particularly relevant to this revision's API-declared model. [Jordan Rose's response](https://forums.swift.org/t/receiver-closures/24020/8) raises the visibility of receiver-driven lookup at the literal. The pitch must also address the [language steering group's 2023 feedback on `with`](https://forums.swift.org/t/pitch-with-functions-in-the-standard-library/65716/62); adopting familiar Kotlin notation is not evidence of Swift community acceptance.

This revision makes receiver intent explicit in the API's type, but makes it less visible in an individual closure literal than the previous binder did. That is a deliberate tradeoff, not a solved readability objection. One receiver, no outer-receiver fallback, and explicit ownership limit the scope of implicit lookup; the clarity benefit must still justify changing the meaning of `self` through contextual typing.

### Scoped leading-dot lookup

The [2021 Scoped Functions pitch](https://forums.swift.org/t/pitch-scoped-functions/45486) explores scoped `.member` access. It preserves a visible marker at every access and could leave lexical `self` unchanged, but needs disambiguation from contextual static-member and enum-case lookup. It is a distinct alternative to receiver rebinding.

## Acknowledgments

This draft builds on the Swift discussions cited above and Kotlin's documented receiver-function model. It has not yet received public pitch feedback.
