# Closure receiver parameters

* Proposal: SE-NNNN (unassigned)
* Authors: TBD
* Review Manager: TBD
* Status: **Pitch draft** — revision 0.7; not submitted for review
* Implementation: Locally tested compiler POC and SwiftSyntax parser; see [implementation status](IMPLEMENTATION.md#local-poc-sketch)
* Review: Not yet posted

## Introduction

Allow a closure to explicitly bind one of its parameters as `self`, enabling implicit member lookup on that parameter. The closure retains an ordinary function type and Swift's existing ownership, capture, lifetime, and isolation rules. This supports user-defined scope functions without giving particular library functions special language behavior.

```swift
let names = users.map { self in
  displayName.uppercased()
}
```

The term **closure receiver parameter** describes the language feature. A **scope function**, such as Kotlin's `run` or `apply`, is one library use of it. This pitch proposes receiver binding; it does not propose new standard-library functions.

The main design uses an explicit binder in each closure. An API-declared receiver is explored under **Alternatives considered**. A source-compatible spelling for explicitly typed receivers remains open before a formal proposal. Local function bodies inherit the nearest receiver scope. The shorthand `{ self in ... }` is the starting point; typed examples below are experimental notation.

A feature-gated parser and compiler prototype accompany this draft. Local validation passes the parser suite, 13 compiler fixtures, two AST unit tests, eight neighboring closure regressions, and three optimized runtime fixtures. This is targeted prototype evidence, not full language-feature validation. Its deferred member lookup implements receiver-before-global priority, including inferred receiver types and inaccessible-member shadowing. [Implementation status](IMPLEMENTATION.md#local-poc-sketch) records the evidence and remaining work.

## Motivation

Swift can group operations on a value using an ordinary closure:

```swift
func with<Value, Result>(
  _ value: Value,
  _ body: (Value) throws -> Result
) rethrows -> Result {
  try body(value)
}

with(request) { request in
  request.timeout = 30
  request.addHeader("Accept", value: "application/json")
  request.send()
}
```

Here, assume `request` is an instance of a reference type. Inside an instance method, Swift allows these same operations to be written through implicit `self`:

```swift
extension Request {
  func prepareAndSend() {
    timeout = 30
    addHeader("Accept", value: "application/json")
    send()
  }
}
```

An extension does not dynamically redefine `self`: its instance methods receive `self` as their receiver. The useful analogy is that a closure could explicitly select an existing parameter to play that role locally. This would make it possible to group operations without moving them into a method or repeatedly spelling a temporary name.

The language capability and the library APIs should be distinguished:

| Term | Meaning in this pitch |
| --- | --- |
| **Receiver** | A value used as the base of member access. |
| **Receiver parameter** | A closure parameter explicitly selected as its local `self`. |
| **Receiver closure** | A closure containing such a parameter binding. |
| **Implicit member lookup** | Resolving an unqualified member reference through that receiver. |
| **Scope function** | A library function that calls a closure with a value, possibly returning that value or the closure's result. |

### Inspiration from Kotlin's scope functions

[Kotlin's scope functions](https://kotlinlang.org/docs/scope-functions.html) demonstrate how a small receiver-binding capability can support several useful library operations. They combine two independent choices: how the block accesses its context value, and what the enclosing operation returns.

| Kotlin operation | Context inside the block | Operation returns | Use |
| --- | --- | --- | --- |
| `value.let { ... }` | Ordinary argument, usually `it` | Block result | Transform or use an intermediate value. |
| `value.run { ... }` | Receiver, `this` | Block result | Compute a result using the receiver's members. |
| `with(value) { ... }` | Receiver, `this` | Block result | Group operations on an existing value. |
| `value.apply { ... }` | Receiver, `this` | Context value | Configure a value and continue using it. |
| `value.also { ... }` | Ordinary argument, usually `it` | Context value | Perform an additional operation, such as logging. |
| `run { ... }` | No supplied context | Block result | Evaluate a block as an expression. |

For example, Kotlin's [`let`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin/let.html) and receiver-based [`run`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin/run.html) can perform the same transformation with different member-access styles:

```kotlin
val explicitName = user.let { it.displayName.uppercase() }
val receiverName = user.run { displayName.uppercase() }
```

With the proposed Swift binder, both styles can use the ordinary `with` helper defined above:

```swift
let explicitName = with(user) { user in
  user.displayName.uppercased()
}

let receiverName = with(user) { self in
  displayName.uppercased()
}
```

This is a deliberate difference from Kotlin: in the explicit-binder design, the closure author selects receiver lookup, so separate `let` and `run` functions are not required solely to distinguish argument and receiver access. Returning the block's result or the supplied value remains a library decision.

Kotlin's [`apply`](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin/apply.html) illustrates the other return policy:

```kotlin
val options = Options().apply {
    timeout = 30
    retryCount = 3
}
```

The Swift `configured` helper defined below provides a related configuration operation while retaining Swift's value and reference semantics:

```swift
let options = configured(Options()) { self in
  timeout = 30
  retryCount = 3
}
```

The analogy does not imply identical mutation semantics: the Swift helper passes local mutable storage as `inout`, allowing value-type configuration and, for class references, replacement of that reference. An `also`-like helper can instead accept an ordinary argument, execute a side effect, and return the supplied value without needing receiver binding.

Optional handling remains compositional. Kotlin commonly combines safe calls with `let`; Swift already has `Optional.map` for an optional transformation. The proposed binder could be used in that existing API:

```swift
let name = maybeUser.map { self in
  displayName
}
```

The optional controls whether the closure executes; the receiver syntax introduces no unwrapping or conditional execution of its own. Kotlin's context-free `run` likewise requires no receiver feature; Swift can already evaluate an immediately invoked closure expression.

### Current Swift behavior

Swift also already permits some related spellings. In a local Swift 6.3.3 experiment, this compiles:

```swift
with(request) { `self` in
  self.send()
}
```

However, the escaped parameter does not establish implicit member lookup. Bare `send()` can fail or continue to refer to the enclosing instance. Similarly, `[self = request]` does not generally establish a new implicit receiver. [SE-0269](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0269-implicit-self-explicit-capture.md) deliberately distinguishes capturing the original receiver from capturing a different value under the name `self`.

Implementation experiments also found that the typed unescaped form `{ (self: Request) in self.send() }` is already accepted by Swift 6.3.3 and 6.4.2, without establishing the proposed implicit receiver lookup. This creates a compatibility question for typed binders, discussed below.

This pitch proposes a deliberate receiver binding with specified lookup behavior, rather than relying on an escaped identifier.

## Proposed solution

Allow the unescaped keyword `self` in a closure's parameter list:

```swift
with(request) { self in
  timeout = 30
  addHeader("Accept", value: "application/json")
  send()
}
```

The binder makes the change of receiver visible in the closure literal. The function `with` remains an ordinary generic function. No protocol conformance, new function type, or special treatment of the name `with` is required.

This also works with existing APIs:

```swift
let names = users.map { self in
  displayName.uppercased()
}
```

The same callback can use an ordinary parameter instead:

```swift
let names = users.map { user in
  user.displayName.uppercased()
}
```

The feature is useful beyond configuration: transformations, callbacks, tests, and existing domain APIs can opt in at the point of use. It changes member lookup, not what the called function does with its closure.

For discussion, this draft develops explicit binding as its main design and explores API-declared receiver behavior under **Alternatives considered**. Choosing between them remains a pitch question.

## Detailed design

### Syntax and function types

The proposed shorthand form selects one parameter using the unescaped keyword `self`:

```swift
{ self in /* body */ }
{ self, index in /* body */ }
```

The prototype also explores the following typed forms. **Their production spelling is unresolved:** Swift already accepts typed `self` as an ordinary parameter, so reinterpreting it needs a migration strategy or a distinct marker. Until that decision is made, these examples describe the desired type and ownership behavior, not a settled grammar addition.

```swift
{ (self: Request) in /* body */ }
{ (self: borrowing Resource) in /* body */ }
{ (self: consuming Resource) in /* body */ }
{ (self: inout Options) in /* body */ }
```

These are proposed spellings. They do not compile as receiver bindings in the released compiler used for this draft.

The grammar change is contextual: add the `self` keyword as an alternative to a closure parameter's local name, both in shorthand parameter lists and parenthesized parameter declarations. A closure may contain at most one receiver parameter. Existing rules for type annotations, effects, ownership modifiers, parameter arity, and shorthand arguments continue to apply.

The grammar delta can be expressed schematically as:

```text
closure-parameter-name → identifier | '_' | 'self'
closure-parameter-name-list → closure-parameter-name
                           | closure-parameter-name ',' closure-parameter-name-list
```

Use this name-list production for the shorthand alternative of a closure's parameter clause, and admit the same `self` alternative for the local name in a parenthesized closure parameter. Do not extend identifier lists or parameter names outside closure signatures. An escaped `` `self` `` takes the ordinary identifier alternative, not the receiver-keyword alternative.

The selected parameter need not be the first parameter. It is not an additional hidden argument. A closure written `{ self, index in ... }` still takes two arguments, in that order. Introducing a receiver does not introduce tuple destructuring.

Receiver selection belongs to the closure literal, not its function type:

```swift
let send: (Request) -> Void = { self in
  sendImmediately()
}

send(request)
```

The variable has the ordinary type `(Request) -> Void`. Assigning or passing the closure does not propagate receiver syntax to other closure literals. Explicitly typed closures can also use the feature without a contextual API.

An escaped parameter named `` `self` `` keeps its existing meaning and does not acquire receiver behavior. This distinction is necessary for source compatibility.

### Member lookup and shadowing

Within the receiver closure, `self.member` refers to the selected parameter, subject to ordinary lexical shadowing in nested scopes. Implicit lookup follows these rules:

1. Look for ordinary lexical local bindings, including closure parameters, local functions, explicit capture aliases, and captured locals from enclosing functions. These retain their normal shadowing behavior.
2. If no such binding exists, look for the name through the selected receiver, using the same member-access capabilities and access checks as explicit `self.member`.
3. If the receiver has no member with that name, consider ordinary nonreceiver declarations such as file-level and module-level functions and types.

Receiver lookup does not fall back to members of an enclosing implicit `self`. Nesting receiver closures therefore selects one receiver at a time; it does not build an implicit receiver stack. Lexical type-name lookup remains available, but this feature does not import the receiver type's nested declarations as an extension body would.

Finding a receiver member by name is a shadowing decision. An inaccessible member or an incompatible overload produces a diagnostic; it does not silently redirect the expression to an outer receiver or a global overload. The prototype tests this rule with inferred receiver types, generic constraints, dynamic members, and overloaded calls.

For example:

```swift
func showTimeouts(for request: Request) {
  let timeout = 15
  with(request) { self in
    print(timeout)       // Captured local: 15.
    print(self.timeout)  // Receiver property.
  }
}
```

This priority is intentional: `self.timeout = timeout` remains a useful way to assign an external local value to a property. Explicit `self.` qualification selects the property when a local binding shadows its name.

An outer instance can be retained under an ordinary name:

```swift
// Inside a method on a controller:
with(request) { [controller = self] self in
  timeout = controller.defaultTimeout
  send()
}
```

Capture initializers are evaluated in the enclosing context, before the receiver parameter is in scope. Here, the initializer's `self` is the controller; the body's `self` is the supplied request. Binding both a capture and a parameter under `self`, as in `{ [self] self in ... }`, is rejected as a duplicate binding. An explicitly named alias is required.

An unrelated binding named `` `self` `` does not become a receiver. If a nested parameter or local declaration shadows the receiver name, implicit receiver-member access is diagnosed; explicit access through a suitable alias remains available. A simple `[self]` capture, or a valid unwrap of `[weak self]`, preserves receiver provenance under the capture rules below. This prevents an ordinary identifier from silently changing the receiver.

Local functions inherit the nearest receiver scope. For example:

```swift
with(request) { self in
  func finishLater() { send() }
  finishLater()
}
```

`send()` resolves on the supplied request. The local function captures any values it uses under ordinary Swift rules; receiver lookup does not grant permission to escape borrowed or exclusive access. A nested type declaration starts a separate type context and does not inherit the receiver. A nested receiver closure selects its own receiver.

### Relationship to methods and extensions

A receiver closure is an ordinary closure with a selected parameter. It does not become a method or an extension declaration:

* It adds no members or conformances and grants no additional `private` or `fileprivate` access.
* It has no initialization privileges, witness role, override relationship, or method dispatch convention.
* `Self` retains its ordinary lexical meaning. It does not become an alias for the receiver parameter's inferred type.
* `super` is not available directly in a receiver closure. There is no declaration-level superclass relationship for its parameter. An enclosing instance can expose an ordinary helper when superclass behavior is needed.

Member dispatch otherwise follows explicit access on the parameter, including normal class dispatch, protocol requirements, generic constraints, and existential restrictions.

### Value semantics and mutation

Receiver binding does not grant mutation. Its parameter retains the mutability and ownership behavior it would have under an ordinary name. An ordinary parameter can mutate the referenced object's properties where Swift permits that operation, but cannot mutate a value type merely because it is named `self`.

For value configuration, a library can pass an explicit `inout` parameter referring to a local value:

```swift
/// Returns the supplied value after applying `body` to local mutable storage.
/// Ownership is transferred for a noncopyable value.
/// For reference types, `body` may mutate the object or replace the reference.
func configured<Value: ~Copyable>(
  _ value: consuming Value,
  _ body: (inout Value) throws -> Void
) rethrows -> Value {
  var result = consume value
  try body(&result)
  return consume result
}

var options = configured(Options()) { self in
  timeout = 30
  retryCount = 3
}
```

The helper has today's ordinary function signature; only its call-site receiver binding is new. Copyable inputs retain their ordinary value semantics. A noncopyable input transfers ownership into local storage and then to the returned result. For a class, this does not clone the instance; the body can mutate the object or replace the reference in local storage. The result is implicitly required to be `Escapable`.

A separate API can make mutation of caller storage explicit:

```swift
/// Applies `body` to the caller's value using ordinary exclusive access.
func update<Value: ~Copyable & ~Escapable>(
  _ value: inout Value,
  _ body: (inout Value) throws -> Void
) rethrows {
  try body(&value)
}

update(&options) { self in
  timeout = 45
}
```

This API is illustrative, not a proposed standard-library addition. The `&` at the call site remains visible.

Neither helper promises rollback after a throw. Changes to caller storage or a shared reference can remain observable. Existing exclusivity and escaping-`inout` restrictions apply, including overlapping accesses through captured aliases.

Explicit `borrowing`, `consuming`, and `inout` annotations compose with receiver parameters wherever they are already legal on closure parameters. [SE-0377](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0377-parameter-ownership-modifiers.md) supplies these conventions:

| Parameter convention | Receiver behavior |
| --- | --- |
| `borrowing` | Access a borrowed value without consuming it. |
| `inout` | Mutate or replace the value under the existing exclusive access. |
| `consuming` | Receive ownership of the argument, which can be consumed under normal rules. |

An explicitly annotated parameter retains that convention. An inferred parameter receives the convention of its ordinary contextual function type; spelling it `self` must not apply instance-method ownership defaults. Receiver binding adds no implicit copies and does not relax restrictions on escaping borrows or noncopyable values. The initial minimal `with` helper is `Copyable`-only; the helpers in this and the following sections demonstrate ownership-aware signatures.

### Captures and nested closures

The receiver is supplied when the closure is invoked. Selecting it does not capture the enclosing instance and does not make the closure nonescaping, synchronous, or exactly-once. The caller may invoke an otherwise valid receiver closure repeatedly, store it, or never invoke it.

A nested closure can capture the receiver under ordinary capture rules. For reference receivers, nested escaping closures must use explicit access or an explicit capture to enable implicit member references, following the policy of [SE-0269](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0269-implicit-self-explicit-capture.md):

```swift
with(request) { self in
  scheduleLater { [self] in
    send()
  }
}
```

Here `scheduleLater` is a free function accepting an escaping closure. A receiver parameter becomes a valid root for the existing self-capture provenance checks; arbitrary escaped variables or captures merely named `self` do not. Weak capture and subsequent unwrapping follow the same provenance-based policy as [SE-0365](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0365-implicit-self-weak-capture.md).

#### Retain cycles

Binding a receiver parameter does not itself capture the supplied object. A nested closure can still strongly capture it and form an ordinary ARC cycle:

```swift
// Assume Request has an onComplete property of type (() -> Void)?.
with(request) { self in
  onComplete = { [self] in
    finish()
  }
}
```

If the request retains `onComplete`, the ownership graph is request → stored closure → request. The nonescaping lifetime of the outer `with` body does not prevent this nested cycle. A weak capture can break the back-reference:

```swift
with(request) { self in
  onComplete = { [weak self] in
    guard let self else { return }
    finish()
  }
}
```

The new receiver must participate in the same explicit-capture and weak-unwrapping diagnostics as other legitimate `self` roots. There is no automatic weak capture. `weak` and `unowned` are class-reference mechanisms, not substitutes for value borrowing or lifetime dependencies. Noncopyable wrappers can themselves contain class references, so noncopyability is not a general proof that an ownership graph is acyclic. [The Swift Programming Language: Automatic Reference Counting](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/LanguageGuide/AutomaticReferenceCounting.md)

Passing the object as a callback parameter is a different case. If an API stores a callback of type `(Request) -> Void` and supplies the request when invoking it, that callback can select the parameter as its receiver without capturing a particular request at all. This is one reason to model receiver binding as a parameter role rather than as capture-list rebinding.

#### Other capture restrictions

Escaping capture of the receiver's `inout` access remains invalid. Where ordinary Swift permits explicit copy capture of a `Copyable` parameter, a capture such as `[self]` instead creates an independent captured value; it does not retain access to caller storage. A copied class reference can still identify the same shared object. Noncopyable and borrowed receivers retain their existing restrictions. The feature adds no new lifetime extension or reference-cycle prevention.

An optional parameter remains optional. Receiver binding does not unwrap it or synthesize optional chaining to its wrapped value. Existing member access on `Optional` itself remains available; users can use `Optional.map` or explicit unwrapping to obtain a nonoptional receiver.

### Noncopyable and nonescapable receivers

Copyability, escapability, parameter ownership, and closure capture are separate properties. The receiver role changes none of them:

| Receiver capabilities | Consequence |
| --- | --- |
| `Copyable` and `Escapable` | Ordinary copy and escape rules apply. Class references belong here and retain ordinary ARC behavior. |
| Noncopyable and `Escapable` | Ownership may be transferred, but the value cannot be implicitly duplicated. Owned escaping capture can be legal. |
| `Copyable` and nonescapable | Local copies are possible, but the copies retain lifetime constraints. `Span` is a useful example. |
| Noncopyable and nonescapable | Both ownership and lifetime restrictions apply. |

In generic constraints, `Value: ~Copyable & ~Escapable` suppresses the default requirements; it accepts values with or without either capability. It does not require arguments to lack both capabilities. These distinctions follow [SE-0427](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0427-noncopyable-generics.md) and [SE-0446](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0446-non-escapable.md).

#### Borrowing a receiver

A scope helper can borrow either kind of value without requiring a copy:

```swift
/// Calls `body` with a borrowed value and returns its escapable result.
func withBorrowed<Value: ~Copyable & ~Escapable, Result: ~Copyable>(
  _ value: borrowing Value,
  _ body: (borrowing Value) throws -> Result
) rethrows -> Result {
  try body(value)
}

// Proposed binder; Span and the ordinary helper signature already exist.
let spanCount = withBorrowed(values.span) { self in
  count
}
```

The result type remains implicitly `Escapable`, while permitting a noncopyable result. Calculating an integer count does not escape the span. Calling a consuming method on a borrowed noncopyable receiver remains invalid.

A borrowed class reference is still a reference to an escapable object. Where copying is legal, an explicit owned copy can outlive the borrow; a scope function does not make that object nonescapable. Explicit-copy requirements also remain in force: for example, a snapshot from an explicitly borrowed `Copyable` parameter can use `[snapshot = copy self]` and then access `snapshot` normally. The binder supplies no implicit ownership conversion.

#### Escaping callbacks and captured receivers

An escaping closure can accept a nonescapable receiver as a parameter without capturing that receiver. For example, a stored or returned handler can have this ordinary function type:

```swift
// Proposed binder; this closure can be stored independently of any span.
let elementCount: (borrowing Span<Int>) -> Int = { self in
  count
}
```

Each invocation supplies a span whose lifetime covers the required access. If the body creates a nested closure that captures that span, the capture must satisfy its lifetime restrictions. Escaping captures of a nonescapable receiver remain invalid, including capture-list copies: copying a view does not detach it from its source storage. Nonescaping captures remain subject to lifetime and exclusivity checks.

Conversely, noncopyability alone does not prohibit an escaping capture. The owned noncopyable local can live in captured storage and be borrowed by a repeatable closure. Consuming its captured value is a separate restriction, because subsequent invocations still need valid captured state. [SE-0390](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0390-noncopyable-structs-and-enums.md#noncopyable-variables-captured-by-escaping-closures)

A consuming receiver parameter is supplied afresh on each invocation and may be consumed. That does not mean the closure itself is consumed or called at most once. Similarly, `[owned = consume resource]` transfers a value when forming a closure; it does not by itself authorize consuming that captured value in an ordinary repeatable closure body. The current [at-most-once function pitch](https://github.com/swiftlang/swift-evolution/pull/3429) addresses that separate capability and remains an unmerged draft.

#### Returning lifetime-dependent values

Returning another nonescapable view requires preserving its lifetime relationship to source storage. Merely adding `Result: ~Escapable` to a generic scope helper is insufficient: its function and closure signatures must express the actual result dependencies. Receiver syntax cannot manufacture an independent lifetime, retain source storage implicitly, or copy a borrowed noncopyable value to make such a return valid.

[SE-0465](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0465-nonescapable-stdlib-primitives.md) explains why higher-order APIs can require lifetime relationships beyond their input/output type constraints. Public annotation spelling remains under discussion in [the lifetime dependency proposal](https://github.com/swiftlang/swift-evolution/pull/3145); experimental compiler attributes are not a stable API introduced by this pitch. The initial `withBorrowed` example intentionally returns an escapable result. Future lifetime-annotated helpers should compose with receiver binding without changing their dependency semantics.

The implementation requirement is **ownership and lifetime equivalence**: after receiver lookup is resolved, using the receiver binder must have the same capture, access, ownership, and lifetime behavior as an ordinary parameter with the same convention and corresponding explicit member accesses. In particular, the new role must not trigger method-specific lifetime inference merely because it is spelled `self`.

### Effects and isolation

`return` returns from the closure. `throw`, `try`, `await`, `defer`, result inference, and closure effects retain their existing meanings. There are no nonlocal returns or Kotlin-style inline-function control-flow rules.

Binding an actor as `self` does not supply actor isolation or by itself permit synchronous access to isolated state. A receiver parameter can also be `isolated` where ordinary isolated parameters are supported; any access permission comes from that modifier or the surrounding isolation context, not from its name. `@MainActor`, `@Sendable`, `sending`, and inferred closure isolation remain independent of receiver lookup.

This requires checking against [SE-0313](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0313-actor-isolation-control.md), [SE-0420](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0420-inheritance-of-actor-isolation.md), and [SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md). In particular, synchronous helper examples do not establish an isolation-correct design for every asynchronous scope function.

Result-builder transformation is also independent. Receiver binding does not make the builder type an implicit receiver or change its transformation rules. A prototype must check existing builder restrictions and diagnostics before claiming full composition.

### Implementation approach

The intended implementation is a frontend feature with an ordinary closure calling convention:

1. Parse unescaped `self` as a contextual closure parameter name. Preserve whether the source token was escaped.
2. Record an explicit receiver-parameter role on the closure or parameter declaration. Do not infer that role by comparing an identifier's text to `self`.
3. Resolve lexical bindings normally, then represent receiver-member candidates using the selected parameter as their base. When its type is inferred, defer member resolution into constraint solving rather than failing ordinary unqualified-name lookup first.
4. Apply access, lvalue, ownership, capture, and isolation checks to the actual parameter declaration. Generalize self-capture provenance only for the new explicit receiver role.
5. Lower successful member references and the closure through the existing ordinary closure path. No receiver-specific runtime operation is intended.

The name-lookup step is the main implementation risk: a generic callback's receiver type can be unknown when an unqualified name is first examined. Neither a parser-only patch nor a textual insertion of `self.` implements the shadowing rules above. The compiler must also preserve its existing distinction between an instance method's implicit `self` parameter and an ordinary closure argument.

The companion [implementation note](IMPLEMENTATION.md) maps these steps to inspected compiler sources and lists the required compiler tests. It distinguishes the implemented sketch from the remaining semantic and integration work.

## Source compatibility

The shorthand unescaped binder `{ self in ... }` is currently invalid syntax. However, implementation experiments confirmed that the typed form `{ (self: Value) in ... }` is already accepted by Swift 6.3.3 and 6.4.2. It acts as an ordinary named parameter: explicit `self.member` uses that parameter, while bare member names can still resolve through the enclosing instance.

Reinterpreting that existing typed form is therefore not purely additive. The POC gates its new behavior behind `-enable-experimental-feature ClosureReceiverParameters` and preserves legacy typed lookup with the feature disabled. Before adoption, the proposal must choose a distinct explicit typed-receiver spelling or an appropriate migration/upcoming-feature mechanism. The experimental gate establishes a POC boundary, not a completed source-compatibility design.

Ordinary parameters, escaped `` `self` `` parameters, existing capture-list spellings, and closures with implicit lexical `self` are intended to preserve their behavior. In particular, existing backticked parameters must not be reinterpreted to change their unqualified lookup.

No annotation changes to existing APIs are required. Choosing the new syntax can change the selected receiver, which is its explicit purpose. Adding new receiver members later can still change lookup in opted-in closures; lexical shadowing and qualification rules do not eliminate that general API-evolution concern.

## ABI compatibility

The explicit-binder design adds no function-type identity, receiver argument, runtime metadata, or calling convention. A receiver closure is intended to lower to the same ABI shape as a closure with a normally named parameter and explicit member accesses.

This does not mean no compiler work is needed for module formats. AST representation, serialized bodies, textual interfaces containing `@inlinable` code, debugging information, and older-toolchain parsing must be checked. Source using the syntax requires a supporting compiler. A prototype must verify ABI and serialization claims before formal review.

## Implications on adoption

Existing APIs taking ordinary function parameters can use receiver closures without being recompiled or annotated. Libraries can separately decide whether scope helpers improve their APIs.

This pitch does not add the five Kotlin function names to the standard library. Those names, return policies, optional behavior, and the possibility of a universally available fluent member are separate API questions. In particular, a universal `value.apply { ... }` cannot be obtained simply by writing an extension on `Any` in today's Swift; marker-protocol workarounds should not be a prerequisite for this language feature.

The proposed frontend-only model is intended to avoid a new operating-system runtime dependency. That must be confirmed by lowering and back-deployment tests. Tooling should show which parameter is the receiver and offer qualification or conversion to an ordinary parameter when it improves clarity.

## Future directions

Potential follow-up work includes a library-only pitch for scope helpers, API annotations advertising receiver-oriented usage, receiver-specific code completion, and interaction with result-builder lookup contexts. Multiple simultaneous implicit receivers and new labeled outer-`self` syntax are deliberately outside this draft.

The immediate questions for this pitch are:

* Is changing the meaning of `self` acceptable when the closure literal makes that choice explicit?
* Should captured lexical locals retain the precedence specified above, and should outer implicit receivers be excluded completely?
* Is a literal-selected receiver sufficient, or does an API need to declare receiver behavior as part of its contract?
* Which typed spelling preserves existing source?

## Alternatives considered

### API-declared receiver closures

Kotlin supplies direct inspiration for this alternative. Its scope functions declare whether their callback takes an ordinary argument or has a [function type with receiver](https://kotlinlang.org/docs/lambdas.html#function-types). The relevant signature shapes are:

```kotlin
// Simplified signatures; implementation details omitted.
inline fun <T, R> T.let(block: (T) -> R): R
inline fun <T, R> T.run(block: T.() -> R): R
inline fun <T> T.apply(block: T.() -> Unit): T
```

Here `T.() -> R` describes a block with a receiver of type `T`; it is not a zero-argument ordinary block. This lets Kotlin APIs advertise receiver-oriented bodies without an explicit binder in each literal. A Swift API-declared design would adopt that aspect of the model, whereas the main design above lets each literal choose its receiver while retaining an ordinary function type.

An API could request receiver behavior, allowing a shorter literal:

```swift
// Alternative design only; @receiver is an unimplemented placeholder.
func with<Value, Result>(
  _ value: Value,
  _ body: @receiver (Value) throws -> Result
) rethrows -> Result {
  try body(value)
}

with(request) {
  timeout = 30
  send()
}
```

One model treats the annotation as a closure-parameter attribute: the callback still takes one ordinary argument, but an argument-less literal gets a synthesized receiver parameter. A literal with an explicit ordinary parameter list opts out. This preserves a conventional invocation inside `with`, but must define how the behavior survives wrappers, forwarding, aliases, overloads, and function-valued storage. If it exists only on the original declaration, it is not a general property of the function value.

A different model introduces a receiver function type, such as the `Value.() -> Result` notation explored in earlier pitches. That can carry receiver intent through storage, but needs rules for type identity, conversions, invocation syntax, ownership, mangling, and module serialization. Equal runtime layout would not by itself establish source-level type equivalence.

| Consideration | Explicit `{ self in ... }` | API-declared receiver |
| --- | --- | --- |
| Where lookup changes | Visible in the literal. | Discovered from the selected API or contextual type. |
| Existing callbacks | Can opt in immediately. | Need annotations or new receiver types. |
| API contract | Receiver style is a caller choice. | API can advertise and consistently supply receiver style. |
| Stored function values | Keep an ordinary function type. | Must define whether receiver information persists. |
| Overload resolution | Selects a receiver parameter syntactically. | Context can determine both the receiver and the meaning of bare names. |
| Compatibility | Shorthand opts in; typed spelling still needs a compatibility decision. | Adding an annotation may alter existing literal lookup. |

Both alternatives deserve exploration. This draft starts with explicit binding because the location of the lookup change is visible and its function-type model is smaller. An API annotation could later guide tooling without silently changing existing literals. This is a recommendation for discussion, not a claim that the language steering group has endorsed the design.

### Previous Swift discussions and steering feedback

The core idea has substantial prior art:

* [“Idea for enabling DSLs: bind to self in closures” (2015)](https://forums.swift.org/t/idea-for-enabling-dsls-bind-to-self-in-closures/58) proposes an explicit `{ self in ... }` binder and discusses lexical locals retaining precedence.
* [“Circling back to `with`” (2016)](https://forums.swift.org/t/circling-back-to-with/2766) separates a library configuration operation from possible receiver-binding syntax. The associated [PR #346](https://github.com/swiftlang/swift-evolution/pull/346) was closed as outside that release's scope; that is not a formal rejection of a numbered receiver proposal.
* [“Receiver Closures” (2019)](https://forums.swift.org/t/receiver-closures/24020) examines API-declared receiver types and mutating receivers. [Jordan Rose's response](https://forums.swift.org/t/receiver-closures/24020/8) raises the visibility of receiver-driven lookup at the literal.
* [“Pitch: Scoped Functions” (2021)](https://forums.swift.org/t/pitch-scoped-functions/45486) explores scoped leading-dot lookup. Its `.member` mechanism differs from rebinding bare-name lookup to an instance.
* [“Result builder scoped unqualified lookup” (2022)](https://forums.swift.org/t/pitch-result-builder-scoped-unqualified-lookup/62190) investigates lookup in a builder type rather than rebinding an instance receiver.

The most significant obstacle is [the language steering group's 2023 feedback on `with`](https://forums.swift.org/t/pitch-with-functions-in-the-standard-library/65716/62). It favors ordinary closures, expresses opposition to special DSL rules including rebinding `self`, rejects a nonsemantic marker protocol, and questions APIs that obscure caller mutation through chaining.

This draft responds with an explicit lexical binder, ordinary function types, one selected receiver, named outer-instance aliases, and unchanged mutation rules. Those choices narrow the issue, but they do not establish that receiver rebinding is desirable. The pitch must still justify the clarity benefit against the cost of changing `self` and unqualified-name lookup.

### Leading-dot receiver lookup

Scoped `.member` syntax could preserve the enclosing `self` while avoiding repeated receiver names. It provides a visible cue on every access and has direct prior art in the 2021 pitch. It also needs disambiguation from Swift's contextual static-member and enum-case lookup. It is a separate viable design, rather than a spelling variant of the rules in this draft.

### Local or scoped extensions

A local extension declaration could make an extension-like body available in a lexical scope, but would introduce separate questions about declaring members, visibility, conformances, and dispatch. None is necessary to select an existing closure argument as a receiver. “Closure receiver parameter” therefore describes this proposal more precisely.

### Ordinary named parameters

Using `request` or `$0` already expresses all the underlying operations and makes every member base visible. It remains the strongest alternative: the proposed feature primarily improves grouped source expression, not runtime capabilities. Its value must be demonstrated through representative code, especially nested code and code with name collisions.

### Hard-coded scope constructs and macros

A built-in `with` statement would give one operation special language behavior without enabling existing callback APIs. A freestanding macro could approximate a configuration block by rewriting syntax, but reproducing type-directed lookup, lexical shadowing, diagnostics, and IDE behavior is more than a simple syntactic substitution. Neither alternative is needed to establish an ordinary closure parameter's receiver role.

## Acknowledgments

This draft builds on the Swift discussions linked above, particularly the distinction between closure-author-selected and API-declared receiver scope. A publication-ready version should confirm author attribution and acknowledge specific feedback received during iteration.
