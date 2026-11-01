# Closure receiver parameters: experimental POC

The [pitch](ClosureReceiverParameters/PITCH.md) develops the language design, Kotlin inspiration, alternatives, and ownership model. This page describes the implementation and its validation limits.

This branch explores explicitly binding an ordinary closure argument as `self`:

```swift
func with<Value, Result>(_ value: Value, _ body: (Value) -> Result) -> Result {
  body(value)
}

let length = with("hello") { self in count }
```

Enable the sketch with `-enable-experimental-feature ClosureReceiverParameters`.
The receiver is an invocation argument, not a capture or a method's implicit
`self`. Library functions retain ordinary function types and ownership rules.
The parser also accepts typed, `borrowing`, `consuming`, and `inout` parameters.
Escaped `` `self` `` retains its existing meaning.

The matching parser branch is
[tevelee/swift-syntax, feature/closure-receiver-parameters](https://github.com/tevelee/swift-syntax/tree/feature/closure-receiver-parameters).
Build both checkouts together; an unmodified SwiftSyntax checkout does not expose
the experimental parser feature used by ASTGen.

## Validation and limits

Verified on 2026-11-01 on arm64 macOS. The modified Swift 6.5-dev compiler
and host standard library built with assertions enabled. All eight receiver
compiler fixtures and both AST unit tests passed. Eight existing closure/parser/
capture regressions passed, as did both runtime fixtures with optimization.
The constraints fixture exercises Swift 5 and 6 modes; parser and AST-dump
fixtures exercise both the C++ and ASTGen paths.

The independently tested SwiftParser suite passed: 2,759 tests, 3 skipped,
zero failures, including 22 receiver tests. All 16 schema tests passed and
regeneration produced no changes. These parser tests used Apple Swift 6.4.2;
compiler fixtures used the new compiler and matching libraries.

Verification fixed missing feature-registry wiring and incorrect receiver
lookup for expression-form `Self`. Direct ordinary `self` parameter/local
shadowing, selected-parameter cloning, nested strong/weak capture, and ownership
fixtures now have execution evidence. This remains a limited prototype:
receiver-before-global lookup is unimplemented, local functions are receiver
boundaries, and serialization/inlinable bodies, broader capture provenance,
builders, isolation, and general SIL equivalence remain unverified.

Unescaped `{ (self: Item) in ... }` already works in existing Swift with different
implicit lookup. This branch changes that spelling only behind the experimental
flag. A proposal needs an explicit compatibility decision before adoption.

## Compiler fixtures

After building a compiler from this branch and the matching SwiftSyntax branch
(the successful local configuration and test setup are described in the
[implementation note](ClosureReceiverParameters/IMPLEMENTATION.md#local-poc-sketch)):

```sh
utils/run-test --build-dir <swift-build-directory> \
  test/Parse/closure_receiver_parameters.swift \
  test/Frontend/closure_receiver_parameters_ast.swift \
  test/Constraints/closure_receiver_parameters.swift \
  test/SILOptimizer/closure_receiver_ownership.swift \
  test/SILOptimizer/closure_receiver_capture_ownership.swift \
  test/SILOptimizer/closure_receiver_nonescapable.swift \
  test/Interpreter/closure_receiver_parameters.swift \
  test/Interpreter/closure_receiver_legacy_typed_self.swift
```

These passing fixtures cover syntax and parser parity, inference, lexical shadowing, mutation,
explicit nested captures, strong capture cycles, weak capture release,
noncopyable arguments, owned noncopyable capture, rejection of borrowed and
`inout` escaping capture, nonescapable invocation arguments, escaping lifetime
errors, and flag-off typed `self` compatibility. Also build and run
`SwiftASTTests` with `--gtest_filter='ClosureReceiverParameter.*'`.

The capture-ownership fixture uses typed `self` and explicit member access, so
it can also run without the experimental flag on an installed compiler. That
baseline passed diagnostic verification on Apple Swift 6.4.2: a consuming
argument can move into captured storage, while borrowed escaping capture,
consuming repeatable captured state, and escaping `inout` access are rejected.
This validates existing ownership behavior, not this branch's compiler changes.

## Next semantic iteration

Receiver-before-global lookup needs a deferred name lookup in the constraint
solver, rather than an unconditional rewrite in precheck:

1. Preserve lexical local bindings, including parameters, captures, local types,
   and forward references to local functions.
2. Retain the nearest receiver binding and ordinary nonmember candidates without
   selecting a global declaration before the receiver type is inferred.
3. For each receiver-type alternative, perform ordinary member lookup on that
   base. If the member name exists, keep its overload set and diagnose access or
   type errors there. A global function that happens to type-check must not
   bypass a shadowing receiver member.
4. Use nonmember fallback only when the receiver has no such member. Do not
   restore the enclosing instance as an implicit receiver.

That decision must remain local to the solver branch exploring a receiver type.
Tests should include an overloaded enclosing call, a same-named global with a
more convenient result type, inaccessible receiver members, and generic and
dynamic-member lookup. An unconditional precheck rewrite would break calls such
as `print(value)` when the receiver has no `print` member. A ranked disjunction
alone would incorrectly accept a global overload when a receiver member exists
but has an incompatible signature.
