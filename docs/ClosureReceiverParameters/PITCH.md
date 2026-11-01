# Closure receiver bindings

* Proposal: [SE-NNNN](https://github.com/tevelee/swift-evolution/blob/feature/closure-receiver-parameters/proposals/0000-closure-receiver-parameters.md) (unassigned)
* Authors: [Laszlo Teveli](https://github.com/tevelee)
* Review Manager: TBD
* Status: **Pitch draft** — revision 0.12; not submitted for review
* Implementation: Experimental [compiler](https://github.com/tevelee/swift/tree/feature/closure-receiver-parameters) and [SwiftSyntax](https://github.com/tevelee/swift-syntax/tree/feature/closure-receiver-parameters) branches. See the [implementation record](https://github.com/tevelee/swift/blob/feature/closure-receiver-parameters/docs/ClosureReceiverParameters/IMPLEMENTATION.md) for tested scope and limitations.
* Review: Not yet posted

## Summary of changes

Allow a closure to designate one of its ordinary parameters as its implicit receiver. An explicit `self` binder enables instance-member lookup in the closure body while preserving the parameter's type, ownership, mutation, lifetime, and isolation rules. Function types and invocation syntax remain unchanged.

## Motivation

A closure often receives one value that is the focus of an entire operation: the request being configured, the report being accumulated, the encoder being written, or the task group being coordinated. Swift already lets the API specify how that value is passed and how long it may be used. The missing convenience is allowing the closure author to write that operation as an instance body, while keeping the receiver boundary visible.

The following examples use existing Swift APIs or explicitly identified library helpers. They do not require universal extension methods, generated setters, new callback types, or new control-flow constructs.

### Configure a request with ordinary control flow

Request construction combines property assignment, method calls, optional inputs, and policy decisions. Using an illustrative `configured` helper, ordinary Swift spells this:

```swift
let request = configured(URLRequest(url: endpoint)) { request in
  request.httpMethod = "POST"
  request.httpBody = payload
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  if let token {
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  }
  request.timeoutInterval = isInteractive ? 15 : 60
}
```

With receiver binding, the request becomes the explicit focus of the body:

```swift
let request = configured(URLRequest(url: endpoint)) { self in
  httpMethod = "POST"
  httpBody = payload
  setValue("application/json", forHTTPHeaderField: "Content-Type")
  if let token {
    setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  }
  timeoutInterval = isInteractive ? 15 : 60
}
```

`URLRequest` is a [Foundation type](https://developer.apple.com/documentation/foundation/urlrequest). `configured` is ordinary library code, with this complete implementation:

```swift
func configured<Value: ~Copyable>(
  _ value: consuming Value,
  _ body: (inout Value) throws -> Void
) rethrows -> Value {
  var result = consume value
  try body(&result)
  return consume result
}
```

The helper produces a configured value that can be bound with `let` or returned directly. Its callback allows existing setters and methods, branches, loops, and throwing operations without creating a fluent counterpart for each operation. `inout` supplies mutable access; receiver binding supplies member lookup. An existing caller variable is not passed by reference by this helper.

This benefit is modest when there are only one or two assignments. A local `var request` followed by statements is also good Swift. The case for receiver binding is cohesive, substantial configuration inside an expression or an existing callback API.

### Accumulate a report with a receiver and an explicit input

An import report may collect several related statistics in a single pass. Today:

```swift
let report = records.reduce(into: ImportReport()) { report, record in
  guard record.isValid else {
    report.rejectedIDs.append(record.id)
    return
  }
  report.acceptedCount += 1
  report.totalBytes += record.byteCount
  report.countsByKind[record.kind, default: 0] += 1
  report.largestRecord = max(report.largestRecord, record.byteCount)
}
```

The same existing API accepts a receiver closure:

```swift
let report = records.reduce(into: ImportReport()) { self, record in
  guard record.isValid else {
    rejectedIDs.append(record.id)
    return
  }
  acceptedCount += 1
  totalBytes += record.byteCount
  countsByKind[record.kind, default: 0] += 1
  largestRecord = max(largestRecord, record.byteCount)
}
```

[`Sequence.reduce(into:_:)`](https://developer.apple.com/documentation/swift/sequence/reduce(into:_:)) already accepts an update callback of type `(inout Result, Element) throws -> Void`. Its declaration and implementation need no receiver-specific changes. `ImportReport` and `record` are application types; the report holds the fields shown above.

The accumulator is the operation's mutable subject; `record` remains an explicit input. Read-modify-write expressions and dictionary subscripts use the same receiver throughout. `return` exits this invocation of the update closure, just as it does today. This example motivates receiver selection in a multi-parameter closure and adoption by an existing generic API, independently of any new configuration helper.

### Build a binary packet with temporary mutable state

A packet encoder illustrates why the receiver need not be the result. Here an illustrative noncopyable `PacketBuilder` provides `append`, `appendBigEndian`, `count`, `writeLength`, and a consuming `finish` operation. The library controls construction and finalization:

```swift
func buildPacket(
  _ body: (inout PacketBuilder) throws -> Void
) rethrows -> [UInt8] {
  var builder = PacketBuilder()
  try body(&builder)
  return builder.finish()
}
```

An ordinary callback uses a named builder:

```swift
let packet = try buildPacket { builder in
  builder.append(0xCA)
  builder.append(0xFE)
  builder.append(version)
  let lengthOffset = builder.count
  builder.append(0)
  let payloadStart = builder.count
  for reading in readings {
    builder.appendBigEndian(reading)
  }
  try builder.writeLength(builder.count - payloadStart, at: lengthOffset)
}
```

The receiver form reads like a locally scoped encoder method:

```swift
let packet = try buildPacket { self in
  append(0xCA)
  append(0xFE)
  append(version)
  let lengthOffset = count
  append(0)
  let payloadStart = count
  for reading in readings {
    appendBigEndian(reading)
  }
  try writeLength(count - payloadStart, at: lengthOffset)
}
```

The body mixes writes, reads of evolving state, local offsets, iteration, and validation. `writeLength` rejects payload lengths that cannot fit in the reserved byte. The helper consumes the builder into the final bytes only after the callback succeeds. These are ordinary ownership and error-propagation choices made by the library; the binder does not supply them.

This is an imperative builder, not a result-builder transform. It demonstrates a useful case for retaining arbitrary Swift statements and mutable access to a noncopyable intermediate value. The proposal's executable fixture implements the builder and checks both its encoded bytes and the oversized-payload failure.

### Coordinate a search using an existing task group

A search can query several independent indexes and cancel remaining work once one produces a match. `SearchIndex` and `SearchResult` below are application-defined `Sendable` values. With an ordinary parameter:

```swift
let match = await withTaskGroup(
  of: SearchResult?.self, returning: SearchResult?.self
) { group in
  for index in indexes {
    group.addTask { await index.search(query) }
  }
  while let candidate = await group.next() {
    if let match = candidate {
      group.cancelAll()
      return match
    }
  }
  return nil
}
```

Receiver binding changes only the group operations:

```swift
let match = await withTaskGroup(
  of: SearchResult?.self, returning: SearchResult?.self
) { self in
  for index in indexes {
    addTask { await index.search(query) }
  }
  while let candidate = await next() {
    if let match = candidate {
      cancelAll()
      return match
    }
  }
  return nil
}
```

[`withTaskGroup`](https://developer.apple.com/documentation/swift/withtaskgroup(of:returning:isolation:body:)) already accepts a body of type `(inout TaskGroup<ChildTaskResult>) async -> GroupResult`. Its isolation parameter and structured-concurrency behavior are unchanged. Child tasks receive their normal explicit inputs; they do not use or capture the group receiver. Cancellation is cooperative, and the group still waits for all child tasks before the scope returns. This selects the first matching result observed in completion order, not the first index in the input.

This case uses several operations on an API-owned context. A configuration-return helper or fluent setters cannot express its purpose. No new scope function is needed.

### Familiar instance bodies, scoped locally

Swift already establishes an implicit receiver in instance methods, including methods declared in extensions:

```swift
extension ImportReport {
  mutating func recordAccepted(_ record: Record) {
    acceptedCount += 1
    totalBytes += record.byteCount
    countsByKind[record.kind, default: 0] += 1
    largestRecord = max(largestRecord, record.byteCount)
  }
}
```

The proposed closure body uses that familiar instance-member idiom for a local operation. Reusable domain behavior should still become a named method. Receiver binding helps when the operation belongs to this call site, depends on surrounding inputs, or uses a callback whose scope the library controls. It adds no members or conformances and grants no extension-specific access privileges.

### What these examples establish

The common requirement is a visible choice of one existing argument as the body's implicit receiver. Configuration, accumulation, encoding, and task coordination retain their separate library semantics. Function types, mutation rights, and execution policies need no receiver-specific representation.

This is a readability proposal, not a new computational capability. The important question is whether naming the receiver once at the scope boundary makes a cohesive body easier to read than repeating its name throughout. Bodies that primarily compare several peer objects often benefit from keeping all their names explicit. For one property, `document.title` is simpler than `withValue(document) { self in title }`. Deeply nested receiver scopes are not motivating examples.

The prototype's `closure_receiver_motivating_examples.swift` runtime fixture checks all four cases, including named-parameter equivalents, report branches, packet length validation, and matching/empty/exhausted searches. That establishes feasibility for these examples; it does not settle the readability judgment.

## Proposed solution

Within a closure parameter list, an unescaped local parameter name `self` explicitly selects that parameter as the receiver. At most one parameter may be selected. It may appear in any position:

```swift
items.map { self in title }
entries.reduce(into: Report()) { self, entry in append(entry) }
combine(theme, document) { theme, self in title + theme.separator }
```

A **closure receiver binding** is the selected ordinary parameter binding plus its role in instance-member lookup. A **receiver closure** is a closure literal containing such a binding. A **scope function** is a library operation that invokes a callback in a useful scope; it is not a special language category.

The function type contains no receiver designation:

```swift
typealias Render = (Document, Theme) -> String
let implicit: Render = { self, theme in title + theme.separator }
let explicit: Render = { document, theme in
  document.title + theme.separator
}
```

These values have the same type. Either can be passed to any API accepting `Render`. Changing an implementation between these forms does not change its public callback contract. There is no `@receiver` attribute, `T.(A) -> R` type, automatic receiver insertion, or new `document.render(theme)` lookup rule in this proposal.

The spelling is experimental: existing typed `self` parameters create a source-compatibility question described below. The prototype requires `-enable-experimental-feature ClosureReceiverParameters`.

## Detailed design

### Parameter formation and scope

The closure signature accepts the `self` keyword wherever a local closure parameter name is accepted. The typed form preserves ordinary parameter ownership syntax:

```swift
{ (self: borrowing Resource) in inspect() }
{ (self: consuming Resource) in close() }
{ (self: inout Configuration) in name = "test" }
```

The role is determined by the local name, not an argument label. It applies to the closure body and lexical descendants that inherit its receiver. The parameter still occupies its original position and contributes to the ordinary closure arity. Explicit parameter names do not introduce a separate shorthand-argument convention: Swift's existing restrictions on mixing named parameters and `$0` remain.

A capture list is evaluated in the enclosing context, before the receiver parameter exists:

```swift
withValue(document) { [owner = self] self in
  owner.display(title)
}
```

A capture and parameter cannot both bind `self`. Duplicate receiver parameters are diagnosed. An escaped parameter named `` `self` `` is an ordinary identifier and does not opt in. An ordinary escaped local named `self` that shadows an active receiver cannot silently replace it; implicit receiver use through that shadow is diagnosed.

Local `let self = value`, `var self = value`, and assignment-based scope changes are not introduced. Assignment to a mutable receiver keeps ordinary assignment semantics; it can replace the value in the selected binding, not change its static type or lexical role.

### Lookup

For an unqualified name in a receiver body:

1. Ordinary lexical local declarations, parameters, and capture aliases take precedence.
2. Otherwise, perform instance-member lookup on the active receiver, using its inferred type and applicable generic constraints.
3. If no receiver member exists, consider nonreceiver declarations from the enclosing lexical/module environment under ordinary lookup rules.

An inaccessible or inapplicable receiver member still shadows a global of the same name. A type mismatch does not make lookup retry a global. Existing dynamic-member lookup participates through ordinary member lookup.

The selected receiver replaces, rather than supplements, an enclosing implicit instance receiver. A missing member never causes silent fallback to the enclosing instance. Save an explicit alias to access that instance. Local functions inherit the current receiver; a nested receiver closure establishes its own. Nested ordinary closures retain the active lexical receiver subject to capture rules.

Member lookup must be deferred when the receiver type is a constraint-system variable. Each overload candidate resolves membership with its own inferred receiver type. The explicit binder establishes the role before overload selection; the callee does not guess which parameter should become a receiver.

For example, a local `name` still wins over a receiver property:

```swift
let name = "configured name"
let config = configured(Configuration()) { self in
  self.name = name
}
```

`Self` keeps its enclosing declaration meaning; receiver binding does not create a type context. `super` is rejected within a receiver scope because the binding does not establish a superclass-method context. Access control and initialization rules are unchanged.

### Ownership, mutation, and invocation

The selected parameter retains its ordinary convention:

| Parameter convention | Receiver behavior |
| --- | --- |
| Ordinary value parameter | Same value/reference and mutation rules as the named parameter |
| `borrowing T` | Borrow the argument; do not gain consuming access or an implicit copy |
| `consuming T` | Receive ownership according to ordinary parameter rules |
| `inout T` | Access caller-supplied storage exclusively under ordinary access rules |

For a class value, an immutable reference can still permit mutation of the referenced object's mutable properties. For a struct, changing stored properties requires mutable access. Receiver status does not make an immutable parameter mutable.

The `configured` helper in the motivation accepts `Value: ~Copyable` and a callback of type `(inout Value) throws -> Void`.

The helper owns its input, lends mutable access to local storage, and returns the result. It does not update an existing caller variable by reference. A class input still denotes the same object unless replaced; the helper does not clone it. Throwing does not imply rollback of changes to shared objects. A separate operation accepting `inout` caller storage has separate mutation semantics and need not return a value.

The configuration helper is one library example, not part of the proposed language addition. All normal invocation syntax is retained, including passing a stored function value or an ordinary named function to the helper. No function-type adapter or new runtime receiver representation is needed.

### Captures, lifetime, and isolation

A receiver parameter is supplied at invocation, not captured at closure formation. A stored `(Document) -> String` receiver closure need not retain any document before it is called.

A nested escaping closure that uses the receiver can capture it and form a retain cycle. Naming a parameter `self` does not choose weak ownership. The receiver binding is an explicit provenance root for implicit-self lookup; nested closures still obey Swift's explicit-self/capture rules:

```swift
withValue(controller) { self in
  onFinish = { [weak self] in
    guard let self else { return }
    finish()
  }
}
```

Captures descended from a valid receiver remain distinguishable from unrelated values named `self`. Selecting a global fallback must not cause capture of an otherwise unused receiver.

An `inout` receiver cannot escape through an illegal capture. Borrowed noncopyable parameters cannot be retained as owned captures without the rights required by ordinary Swift. A copied nonescapable view retains its lifetime dependence. An escaping function value that *accepts* a nonescapable argument is distinct from a closure that *captures* such an argument.

Generic helpers must opt into the copyability and escapability domains they support. A helper whose result implicitly requires `Escapable` cannot be used to return a nonescapable view merely because the callback uses a receiver. Lifetime-dependent result APIs require the same lifetime annotations and checks as explicitly named callbacks; broad coverage is not claimed by this prototype.

Receiver lookup grants no actor-isolation authority. An actor receiver still requires `await` or valid `isolated` evidence for isolated operations. `@Sendable`, global-actor, execution-mode, exclusivity, and capture checks apply normally.

### Result builders

Receiver selection and result-builder transformation are independent. An API whose builder closure already accepts an argument can allow that argument to be selected as receiver. A zero-argument builder callback does not acquire an argument automatically. Builder methods and nested types are not implicitly imported as a namespace by this feature.

### Implementation model

Represent the receiver as an ordinary parameter declaration with a receiver index on the closure AST. Preserve the index when cloning parameter lists. Do not broaden the compiler's method-self predicate to include arbitrary named variables.

Both parser paths preserve the distinction between the keyword binder and an escaped identifier. Semantic lookup forms a deferred receiver-member lookup when inference is incomplete. After resolution, normal member access, capture analysis, ownership checking, and SIL generation apply. Exported function signatures remain ordinary function types. Textual interfaces containing receiver syntax in inlinable bodies require feature-aware handling.

## Source compatibility

This pitch is not unconditionally source-compatible. Existing Swift accepts some unescaped *typed* parameters named `self` without giving them implicit receiver lookup. Interpreting those existing bodies differently could silently change which member is used.

The experimental flag makes the prototype opt-in; it is not a final migration policy. Before formal review, the proposal must choose either a distinct typed binder spelling or a language-mode/upcoming-feature transition that preserves old interpretation unless deliberately enabled. This remains a release-design question, not a claim that the POC can ship unchanged.

Escaped parameter spellings retain their existing behavior. Ordinary closures without a selected receiver retain their lookup and function types. The implementation includes a feature-disabled typed-self runtime regression. No source-compatible API can secretly opt its existing callers into receiver lookup.

## ABI compatibility

The receiver role belongs to a closure implementation, not its function type. Parameter order, ownership conventions, function mangling, and runtime calling conventions are unchanged. There is no receiver-function ABI marker or module-format version bump.

Compiler AST representation and feature guarding of serialized/textual bodies still require testing. The POC covers selected module-interface reconstruction and optimized imported clients; this is not a compiler-wide ABI certification.

## Implications on adoption

A library can keep an ordinary callback signature while individual callers opt in. A stored receiver closure remains usable by clients expecting an ordinary function value. Removing a receiver binder and qualifying its member references does not change the callback's public type.

Adopters need a compiler implementing the syntax. Inlinable and client-emitted bodies also need suitable interface feature guards or an older-syntax representation. The mechanism is designed to need no new runtime support; cross-version and back-deployment validation remain required before a production claim.

## Future directions

A generalized local receiver declaration could select a receiver outside closure signatures. It would need to distinguish owning local values from borrows or aliases: `var self = value` cannot silently gain writeback semantics.

API-declared receiver function types could allow `.apply { name = "test" }` without an explicit binder and preserve receiver intent through function aliases. Such a proposal would need conversion, overload, migration, and typed ownership rules beyond this pitch.

Scoped DSL namespaces, member extensions like Kotlin's Compose scope APIs, and universal availability of fluent helpers are separate potential additions. None is required for explicit receiver binding. Locally named extension functions and lexical function-value lookup after a dot are likewise outside scope.

## Alternatives considered

### Keep ordinary parameters

`{ value in value.member }` and `{ $0.member }` remain clear and sufficient for many APIs. They make every member's base visible and avoid a new lookup rule. The proposed convenience must justify its complexity with cohesive multi-operation contexts, not single-property examples. This is the strongest baseline alternative.

### API-declared receiver types

Kotlin's `T.(A) -> R` notation produces compact call sites and makes receiver intent part of a reusable callback type. It is a coherent alternative, not merely another spelling of this proposal. It lets the API select the receiver, whereas an explicit binder lets the closure author select any existing parameter. It also introduces public type-system distinctions or conversions that are unnecessary for the proposed opt-in lookup role.

The previous experiment explored such types, a closure marker, and dotted invocation. Revision 0.11 removes those mechanisms from the active prototype. This narrowing does not rule them out as separately justified proposals.

### Local `self` rebinding or a dedicated `with` block

A local declaration is more general than a parameter binder, but plain `let`/`var` declarations have ownership and storage meanings. Reusing `self = value` would also conflate existing assignment with introducing a new lexical binding. A dedicated scope construct introduces additional control-flow and result rules. Parameter binding reuses the API's existing argument and access conventions.

### Scoped leading-dot lookup

The [2021 Scoped Functions pitch](https://forums.swift.org/t/pitch-scoped-functions/45486) explored contextual member access with a leading dot. That preserves a visual receiver cue without changing `self`, but interacts with existing contextual static-member syntax and multiline chaining. The [discussion](https://forums.swift.org/t/pitch-scoped-functions/45486?page=2) also compares explicit parameters and key-path-based approaches.

### Result-builder namespaces

The [2022–23 scoped unqualified lookup pitch](https://forums.swift.org/t/pitch-result-builder-scoped-unqualified-lookup/62190) addresses DSL-specific names without global namespace pollution. Importing a namespace does not necessarily require a runtime value or a mutable receiver. Receiver binding should compose with result builders, not replace their transform or absorb every namespace problem.

### Fluent setters and macros

Fluent setters can express simple configuration, but arbitrary conditions, read-modify-write operations, and calls to existing mutating APIs fit naturally in an ordinary callback. [John McCall's 2023 comparison](https://forums.swift.org/t/pitch-with-functions-in-the-standard-library/65716/70) explains this distinction. The [2026 Implicit Fluent Chaining pitch](https://forums.swift.org/t/implicit-fluent-chaining/86660) is another configuration-focused approach. Generating setter methods is separate from changing lexical member lookup.

### Prior art and steering-group concerns

The [2015 self-binding discussion](https://forums.swift.org/t/idea-for-enabling-dsls-bind-to-self-in-closures/58), [2016 with discussion](https://forums.swift.org/t/circling-back-to-with/2766), and [2019 Receiver Closures pitch](https://forums.swift.org/t/receiver-closures/24020) explored related mechanisms. The 2019 discussion already considered receiver types and mutating receivers. This pitch does not claim those ideas are new.

The [July 2023 steering-group guidance](https://forums.swift.org/t/pitch-with-functions-in-the-standard-library/65716/62) preferred actual closures over special configuration blocks and explicitly raised concerns about Kotlin-style self rebinding. It also distinguished configure-and-return from expression chains that mutate existing caller storage. This is a substantive objection, not an endorsement of the present proposal.

This pitch responds with an explicit lookup boundary, an ordinary callback type, no hidden receiver inference, and applications beyond configuration. These choices make the tradeoff more reviewable; they do not establish that the readability and complexity concerns have been resolved to the community's satisfaction.

### Kotlin comparison

[Kotlin scope functions](https://kotlinlang.org/docs/scope-functions.html) separate how the value is accessed from what is returned. `let` and `also` use ordinary arguments; `run`, `with`, and `apply` use receivers. The helpers are library APIs, not individually privileged syntax.

The closest Kotlin analogue of the packet builder is a library-controlled construction callback. For example, [buildList](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/build-list.html) declares a `MutableList<E>.() -> Unit` callback and returns `List<E>`:

```kotlin
val arguments = buildList {
    add("compile")
    if (warningsAsErrors) add("--warnings-as-errors")
    addAll(sourceFiles)
}
```

The receiver holds evolving construction state while local inputs remain named. Swift can express this pattern with an ordinary `inout` callback and an explicit `self` binder, as in `buildPacket`. Kotlin's mutable/read-only list distinction does not itself provide Swift's ownership or lifetime guarantees; those must come from the Swift helper's actual types and parameter conventions.

Kotlin's `let` is a useful counterexample: `source?.let { parse(it) }` uses an ordinary argument. Its closest Swift spelling, `source.map { parse($0) }`, already works without receiver binding. The goal is to support bodies centered on receiver operations, not to reproduce every Kotlin helper under a new Swift name.

Further motivating APIs include [buildList](https://kotlinlang.org/api/core/kotlin-stdlib/kotlin.collections/build-list.html), [Json builders](https://kotlinlang.org/api/kotlinx.serialization/kotlinx-serialization-json/kotlinx.serialization.json/-json.html), [coroutineScope](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/coroutine-scope.html), and [Ktor callbacks with a receiver and ordinary arguments](https://api.ktor.io/ktor-server-core/io.ktor.server.routing/post.html). Their receiver role does not by itself establish resource safety, structured concurrency, or deferred execution.

Swift's corresponding foundations include `inout` callbacks, result builders, task groups, and continuation-based producers. This pitch adds explicit receiver lookup to those foundations rather than copying Kotlin's whole scope-function family or receiver tower.

## Acknowledgments

This draft draws on the public discussions cited above, including work and analysis by Erica Sadun, Brent Royal-Gordon, Simon Anreiter, Gwendal Roué, Angela Laar, Matt Ricketson, John McCall, and Xiaodi Wu. Citation does not imply endorsement of this draft.
