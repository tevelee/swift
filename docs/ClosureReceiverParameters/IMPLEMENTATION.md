# Closure receiver parameters: implementation investigation

Reviewed on 2026-11-01; execution results below are from 2026-10-30. A local POC sketch now exists; its modified compiler remains unbuilt. This note separates released-compiler experiments, executed parser tests, inspected source, and unverified compiler implementation work.

## Local POC sketch

The working checkouts and detailed continuation instructions are under `~/projects/apple/receiver-poc` in the author's local workspace. Swift and SwiftSyntax use branch `feature/closure-receiver-parameters`, published to [tevelee/swift](https://github.com/tevelee/swift/tree/feature/closure-receiver-parameters) and [tevelee/swift-syntax](https://github.com/tevelee/swift-syntax/tree/feature/closure-receiver-parameters); exact revisions and exported patches are recorded there.

The SwiftSyntax change recognizes feature-gated receiver parameters while preserving escaped identifiers. **The parser suite passed: 2,759 tests, 3 skipped, 0 failures**, including **22 receiver tests**, with raw-syntax validation; **16 CodeGeneration schema tests passed**. These runs used Xcode 27.2 beta 3's Apple Swift 6.4.2 without changing the globally selected Xcode.

The published SwiftSyntax head also passed [Linux CI](https://github.com/tevelee/swift-syntax/actions/runs/41107071219) on Swift 6.4.1: the parser suite, 16 schema tests, and regenerated-source verification. Two initial workflow failures were corrected: oversized serial test-filter arguments and checkout discovery in the final Git comparison.

The compiler sketch introduces `ClosureReceiverParameters`, a separate AST receiver-parameter role, ASTGen and legacy-parser wiring, ordinary member-expression construction during precheck, and self-capture provenance handling. Eight compiler regression files and two AST unit tests are written. Receiver selection now follows cloned parameter lists by position; the sketch also diagnoses `super` in receiver scope and marks receiver closures in AST dumps. The compiler has **not** been built, and these compiler semantic/ownership/runtime fixtures have **not** been executed against it. Storage prevented a full build on October 30. A November 1 check found about 100 GiB free; the build has not yet been attempted with that space available.

An additional fixture verified existing capture-ownership diagnostics on installed Swift 6.4.2 without the receiver feature: borrowed and `inout` escaping captures are rejected, as is consuming noncopyable state captured by a repeatable closure. An ordinary owned-capture runtime baseline printed `7 7`. These are baseline checks, not execution of the modified compiler.

The precheck sketch intentionally preserves ordinary nonmember/global lookup, so it does not yet implement the pitch's complete receiver-before-global priority. An outsider review added a diagnostic for direct escaped `self` parameter/local shadowing, with fixtures in Swift 5 and 6 modes; these remain unexecuted. Capture and weak-unwrapping provenance, local functions, serialization, isolation, and lifetime-dependent result integration still require compiler validation.

An additional compatibility probe found that `{ (self: Item) in ... }` is already accepted by Swift 6.3.3 and 6.4.2. Its implicit member lookup remains lexical. The POC keeps reinterpretation behind its experimental flag and tests the old parser behavior with the feature disabled. The pitch's source-compatibility section has been corrected: typed receiver syntax needs a distinct marker or a migration strategy before adoption.

The build wrapper started CMake bootstrapping even with `--dry-run`; the task-owned process group was stopped and its partial bootstrap directory removed, with logs retained. The author's local `receiver-poc/build-compiler.sh` checks free space before invoking that wrapper.

## Evidence baseline

Local toolchain:

```text
swift-driver version: 1.148.6
Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
Target: arm64-apple-macosx28.0
```

The initial compiler-source inspection used upstream `swiftlang/swift` commit [`8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5`](https://github.com/swiftlang/swift/tree/8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5). This is a separately inspected source snapshot, not a claim that the installed Apple compiler was built from that revision. Those initial files were fetched read-only into a temporary directory. The later POC modifies a checkout at the same base revision, as described above.

## Released-compiler experiments

Independent Swift scripts were executed with the toolchain above. Unless stated otherwise, their common setup was:

```swift
struct Item { var value: Int }
func with<T, R>(_ value: T, _ body: (T) throws -> R) rethrows -> R {
  try body(value)
}
let item = Item(value: 42)
```

| Experiment | Observed result |
| --- | --- |
| `with(item) { self in self.value }` | Rejected at parsing/type checking; no receiver binder exists in this spelling. |
| ``with(item) { `self` in self.value }`` | Compiled and returned `42`. |
| ``with(item) { `self` in value }`` at top level | Rejected: cannot find `value` in scope. |
| `{ [self = item] in self.value }()` | Compiled and returned `42`. |
| `{ [self = item] in value }()` at top level | Rejected: cannot find `value` in scope. |
| `let self = item` in a `do` block | Rejected: keyword cannot be used as an identifier here. |
| ``let `self` = item`` followed by `print(value)` | Rejected: no implicit lookup of `Item.value`. |
| An ordinary `(inout T) -> Void` callback using `` `self` `` and explicit `self.value = 43` | Compiled and mutated the original value to `43`. |

An enclosing-instance probe is particularly relevant to compatibility:

```swift
struct Owner {
  var value = -1

  func test() {
    print(with(Item(value: 42)) { `self` in value })
    print(with(Item(value: 42)) { `self` in self.value })
  }
}

Owner().test()
// -1
// 42
```

This demonstrates that an escaped `self` parameter does not retarget implicit member lookup. Reinterpreting existing escaped syntax could silently change valid code. The new binder needs its own source-level opt-in.

The capture-alias form below also compiled with the escaped parameter and returned `41`:

```swift
with(Item(value: 42)) { [owner = self] `self` in
  owner.value + self.value
}
```

The ordinary helper implementations from the pitch were separately executed with named or `$0` parameters. Value configuration preserved the input's `10`, produced a configured value of `30`, and the `inout` update produced `40` in caller storage. A class-reference replacement through `configured` returned a different object while preserving the original reference. An explicit `[value]` capture of a copyable `inout Int` preserved the snapshot `1` after caller storage changed to `2`. These results verify the library mechanics; they do not verify proposed receiver lookup or generalized ownership/isolation behavior.

## Follow-up experiments: captures, ownership, and lifetimes

The following standalone programs were compiled with `swiftc -swift-version 6 input.swift -o output` and successful programs were executed. These runs used Swift 6.3.3 with no experimental flags. Full compilation matters because some ownership diagnostics occur after initial type checking. Each case used ordinary named parameters; receiver-binder syntax remains unimplemented.

| Case | Observed result |
| --- | --- |
| A class stores a closure that strongly captures the class instance, created inside nonescaping `with` | A weak observer remained nonnil after leaving the scope. Clearing the stored callback broke the cycle and released the instance. |
| The same callback uses a weak capture | The weak observer became nil after leaving the scope. |
| `withBorrowed<Value: ~Copyable & ~Escapable, Result: ~Copyable>` inspects a noncopyable token | Compiled; the callback read `7` and the caller could still read `7` afterward. |
| The borrowed callback calls the token's consuming method | Rejected: the parameter is borrowed and cannot be consumed. |
| The borrowed callback constructs a fresh noncopyable result | Compiled and returned a token containing `8`. |
| `configured<Value: ~Copyable>` takes a consuming input, mutates local storage, and returns ownership | Compiled with a noncopyable token and produced `8`. |
| `update<Value: ~Copyable & ~Escapable>` forwards `inout` storage | Compiled for a noncopyable token and for a `Span<Int>`. |
| An ordinary `(consuming Value) -> Result` callback consumes its invocation argument | Compiled with a noncopyable token; returned `7`. |
| An escaping closure owns an immutable noncopyable local and calls its borrowing method | Compiled; two invocations both returned `7`. |
| An escaping closure calls that captured token's consuming method | Rejected: the captured noncopyable value cannot be consumed. |
| Capture list `[owned = consume token]`, then borrow `owned` inside the escaping closure | Compiled; two invocations both returned `7`. |
| The same consume capture, then consume `owned` inside the closure | Rejected; formation-time ownership transfer did not permit consuming repeatable captured state. |
| Nonescaping closure borrows a noncopyable borrowing parameter | Compiled and returned `7`. |
| Escaping closure retains that noncopyable borrowing parameter | Rejected: a borrowed parameter cannot be captured by an escaping closure. |
| `[value]` snapshots an explicitly `borrowing Value` parameter | Rejected in the generic `Copyable` probe: explicit ownership needed. |
| `[value = copy value]` in the same probe | Compiled and returned the copied `7`. A borrowed class reference could likewise be explicitly copied into a capture. |
| `withBorrowed` computes the count of `values.span` | Compiled and returned `3`. |
| A span is copied locally or used in an immediately invoked capturing closure | Compiled; the values remained inside their permitted lifetimes. |
| A returned escaping closure captures a span from a local array | Rejected: the lifetime-dependent value escapes its scope. |
| The returned closure uses explicit `[span]` capture | Still rejected; a copy does not remove lifetime dependence. |
| A factory returns a callback of type `(borrowing Span<Int>) -> Int`, capturing no span | Compiled; a later invocation with `values.span` returned `3`. |
| The demonstrated `withBorrowed` helper is asked to return `Span<Int>` | Rejected with an explicitly typed result: `Result: Escapable` is implicit in its signature. |

The last callback case distinguishes *an escaping function value* from *an escaping capture of its invocation argument*. This ordinary program compiled and ran:

```swift
func makeCounter() -> (borrowing Span<Int>) -> Int {
  { span in span.count }
}

let count = makeCounter()
let values = [1, 2, 3]
print(count(values.span)) // 3
```

Similarly, a `Copyable` snapshot from an explicitly borrowed parameter required an explicit copy in this toolchain:

```swift
func snapshot<Value: Copyable>(
  _ value: borrowing Value
) -> () -> Value {
  { [value = copy value] in value }
}
```

These experiments motivate ownership-neutral receiver binding; they do not establish general support for every noncopyable capture shape or lifetime-dependent result. One exploratory span-result probe inferred `Void` and failed on a subsequent member access; it was refined to an explicitly typed `Span<Int>` result before attributing the rejection to `Escapable`.

## Inspected compiler entry points

All source links below are pinned to the inspected commit.

| Area | Existing source anchor | Relevance to a prototype |
| --- | --- | --- |
| C++ closure parser | [`Parser::parseClosureSignatureIfPresent`](https://github.com/swiftlang/swift/blob/8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5/lib/Parse/ParseExpr.cpp#L2650), [`parseExprClosure`](https://github.com/swiftlang/swift/blob/8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5/lib/Parse/ParseExpr.cpp#L3091) | Signature lookahead and shorthand names need contextual acceptance of the `self` keyword; typed parameter parsing must agree. |
| Swift AST generation | [`generate(closureSignature:)`](https://github.com/swiftlang/swift/blob/8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5/lib/ASTGen/Sources/ASTGen/Exprs.swift#L226), [`generate(closureExpr:)`](https://github.com/swiftlang/swift/blob/8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5/lib/ASTGen/Sources/ASTGen/Exprs.swift#L338) | Source syntax becomes an AST parameter list here; preserve receiver role through bridging. SwiftParser/SwiftSyntax needs matching syntax support. |
| Closure AST | [`ClosureExpr`](https://github.com/swiftlang/swift/blob/8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5/include/swift/AST/Expr.h#L4269), [`getCapturedSelfDecl`](https://github.com/swiftlang/swift/blob/8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5/include/swift/AST/Expr.h#L4556) | Captured `self` already has representation. A receiver argument is a different role and must not be stored as a capture. |
| Method-self identity | [`VarDecl::isSelfParameter`](https://github.com/swiftlang/swift/blob/8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5/lib/AST/Decl.cpp#L9178) | This recognizes method/initializer self, not merely an argument named `self`. Globally broadening this predicate would risk actor and ownership behavior. |
| Lexical closure parameters | [`ClosureParametersScope::lookupLocalsOrMembers`](https://github.com/swiftlang/swift/blob/8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5/lib/AST/ASTScopeLookup.cpp#L467) | Currently consumes parameter declarations; it does not turn their members into a lookup scope. |
| Closure type inference | [`ConstraintGenerator::inferClosureType`](https://github.com/swiftlang/swift/blob/8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5/lib/Sema/CSGen.cpp#L1901) | Parameters can begin as type variables. Receiver-member resolution must work before their types are fully solved. |
| Implicit-self diagnostics | [`ImplicitSelfUsageChecker`](https://github.com/swiftlang/swift/blob/8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5/lib/Sema/MiscDiagnostics.cpp#L1824), [`diagnoseImplicitSelfUseInClosure`](https://github.com/swiftlang/swift/blob/8c28b0dcbfd999dcef8c923aa51758ec61cb1eb5/lib/Sema/MiscDiagnostics.cpp#L2709) | Checks capture provenance, nested closures, and weak-self unwrapping. Introduce the explicit receiver parameter as a new valid provenance root. |

These anchors locate existing machinery; they are not a complete patch map. SourceKit, serialization, parameter parsing helpers, name-binding/precheck paths, and SILGen also need auditing.

## Proposed representation

Keep the selected argument as an ordinary `ParamDecl`. Store an explicit receiver role, for example a receiver-parameter index on `ClosureExpr`, with a query that returns the corresponding declaration. The exact storage layout is an implementation choice.

Do not treat every declaration whose identifier is `self` as a receiver. In particular, keep these concepts separate:

* An instance method's implicit self parameter.
* A closure's explicitly selected receiver parameter.
* A capture descended from either legitimate receiver.
* An unrelated declaration that happens to use the escaped name `self`.

Preserve the escaped-token distinction before identifier normalization loses it. Duplicate receiver binders and capture/parameter collisions should be diagnosed during signature formation. Do not synthesize an extension declaration or make the closure a type context: that could accidentally affect access control, `Self`, isolation, or initialization checking.

## Lookup and constraints: the difficult part

For `users.map { self in displayName }`, the contextual parameter type and the result expression constrain each other. Ordinary unqualified lookup must not permanently bind the name to a global declaration, bind it to an outer instance, or emit an undeclared-name error before receiver inference can run.

An implementation strategy is:

1. Identify lexical local bindings without importing the enclosing implicit receiver's members. Preserve shadowing by captured locals.
2. For names without a local binding, retain the selected receiver declaration and any nonreceiver fallback candidates in a deferred lookup representation.
3. Once a candidate receiver type is available, perform ordinary member lookup on that base, including generic constraints, access filtering, overload sets, and `@dynamicMemberLookup` behavior where ordinary explicit access supports it.
4. Select global fallback only when the receiver has no member with that name. A failed member overload or inaccessible declaration must not change the meaning to a fallback. Receiver-type alternatives in overloaded calls must be explored without committing one alternative's lookup results globally.
5. Apply the solution to form ordinary bound member expressions with source locations preserved for diagnostics, indexing, and refactorings.

The representation could be a dedicated unresolved receiver reference or an extension of existing precheck/constraint machinery. That choice needs a prototype. In the inspected source, `visitUnresolvedDeclRefExpr` is explicitly an error-recovery path, so simply leaving an undeclared-name expression there would not implement normal receiver inference.

The proposed shadowing policy has a nontrivial cost: receiver membership must be known before global fallback, and that decision cannot depend only on which overload happens to type check. Benchmark overloaded, generic, and nested examples. If this cannot be expressed predictably without excessive solver branching, narrow the lookup policy or reconsider the feature.

Leading-dot `UnresolvedMemberExpr` is also not a drop-in representation. The inspected constraint generator models it using contextual metatype/static-member inference. A closure receiver is an explicit runtime parameter with independently inferred type.

## Ownership, isolation, and lowering

The parameter's ordinary function-type convention supplies its ownership. An `inout` receiver remains the same exclusive access that an ordinary named `inout` argument would have; it is not a fresh mutable copy. Capture analysis must reject escaping that access and detect overlapping access through aliases. Explicit copy capture of a copyable value, when otherwise legal, creates independent captured storage and remains permitted. Borrowed and noncopyable captures keep their existing restrictions.

The core implementation invariant is ownership and lifetime equivalence with an ordinary named parameter. Keep the receiver-role query separate from method-self queries: naming an argument `self` must not change its convention or apply method-specific lifetime inference. Preserve constraints on all derived member values, nested captures, and closure conversions. Do not materialize a hidden `Copyable` temporary, erase a scoped dependency, or synthesize a retaining wrapper to make member lookup succeed.

An escaping closure's supplied argument is not part of its captured environment. A stored `(borrowing Span<Int>) -> Int` handler is therefore distinct from a stored `() -> Int` handler capturing a span. The capture checker must distinguish a fresh invocation parameter from a nested escaping capture of that parameter. For a noncopyable owned capture, preserve shared captured-storage rules; receiver binding must not authorize consuming that storage simply because a consuming method is found by implicit lookup.

The illustrative `withBorrowed` helper accepts possibly-noncopyable and possibly-nonescapable input but intentionally requires an escapable result. Returning a view needs the function's ordinary result dependencies, including any dependence on captured context. The compiler's [lifetime annotation guide](https://github.com/swiftlang/swift/blob/main/docs/ReferenceGuides/LifetimeAnnotation.md) can inform experiments, but its `Lifetimes` support and underscored attributes are experimental. The open [lifetime annotation proposal](https://github.com/swiftlang/swift-evolution/pull/3145) and draft [at-most-once function proposal](https://github.com/swiftlang/swift-evolution/pull/3429) must not be reported as accepted features implemented by this pitch.

Do not make receiver selection imply actor isolation. Existing method-self helpers, such as `isActorSelf`, are tied to declaration context. A closure receiver can be an arbitrary actor instance, requiring independent `isolated` evidence before synchronous state access is valid. Keep actor provenance and receiver-lookup provenance distinct.

Once lookup is resolved, ordinary closure emission and ordinary member-access lowering should suffice. Compare representative SIL against equivalent explicitly named closures. Verify retain/release behavior for class receivers, access scopes for `inout`, borrow scopes, generic witness calls, actor hops, and captures. “Same calling convention” is a design target, not evidence that the feature needs no further SIL work.

## Prototype sequence and acceptance tests

1. **Syntax and representation:** shorthand and typed binders; multiple ordinary parameters; one receiver in any position; escaped-name distinction; duplicate binders; capture aliases; malformed signatures; parser and ASTGen parity. Inspect the matching SwiftSyntax dependency before changing its grammar.
2. **Known receiver types:** explicit `self`, bare property/method/subscript access, lexical-local collisions, globals, inaccessible members, outer-instance aliases, nested receiver boundaries, and generic-constrained members.
3. **Inferred receiver types:** `map`, generic helpers, overloaded callees, overloaded receiver members, result inference, dynamic-member lookup, and diagnostics that distinguish missing members from missing lexical names.
4. **Capture provenance:** nested nonescaping/escaping closures, explicit and weak captures, guarded weak-self unwrap, demonstrated ARC cycles and weak-capture release, receiver closures invoked after their defining method returns, callbacks that receive an argument rather than capture it, and unchanged existing escaped-identifier behavior.
5. **Ownership and isolation:** struct/class configuration, `inout` replacement of the entire value where ordinary Swift permits it, exclusivity violations, throwing bodies, borrowing/consuming and noncopyable cases, owned versus borrowed noncopyable captures, formation-time consume captures, explicit copies of borrowed copyable values, actor parameters with and without isolation, `@Sendable` captures, global actors, and async execution modes.
6. **Compatibility and tooling:** current compiler self/capture suites, Swift language modes supported by the prototype, result builders and their explicit-parameter restrictions, optional/metatype/existential receivers, `Self`/`super` diagnostics, SourceKit completion and indexing, serialization round trips, `@inlinable` textual interfaces, and SIL/ABI comparisons.
7. **Lifetime preservation:** all four copyability/escapability combinations; local versus escaping captures of spans; copies retaining scoped dependencies; stored callbacks accepting nonescapable invocation arguments; escapable scalar results versus lifetime-dependent view results; function conversions and experimental lifetime annotations tested separately; and later borrowing/mutating accessors without introducing an implicit copy. Compare both accepted and rejected examples against ordinary named-parameter equivalents.

Suggested negative diagnostics include “receiver parameter does not permit mutation,” “escaping closure captures an inout access,” “capture and receiver parameter both bind self,” and an outer-member suggestion naming the alias. These describe desired diagnostic content, not finalized wording.

A feature-gated prototype and these tests are prerequisites for calling the design implemented. The current [Evolution process](https://github.com/swiftlang/swift-evolution/blob/main/process.md) requires a viable implementation before formal language review; this local pitch is an earlier discussion artifact.
