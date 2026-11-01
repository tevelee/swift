# Closure receiver bindings: implementation record

Revision 0.11, 2026-11-01. The active prototype selects an ordinary closure parameter with an explicit `self` binder. Its signature, ownership convention, and invocation syntax remain ordinary Swift. The [pitch](PITCH.md) is a draft, not an accepted language feature.

## Scope of this revision

The earlier explicit-parameter implementation is the semantic foundation. This revision removes the receiver-function experiment from the active compiler and SwiftSyntax grammar:

- No `T.(A) -> R` type syntax or receiver bit in semantic function types.
- No contextual self insertion or `@receiver` declaration attribute.
- No lexical callback lookup after a dot.
- No receiver-function mangling node, parameter serialization bit, or module-format bump.
- No `FunctionTypeSyntax.receiver` / `.period` children.

The broader experiment was saved before editing in the local `receiver-poc/archive/before-receiver-binding-20261101-123308` directory, including patches and untracked invocation tests. Its prior commits remain in history. Archived results do not validate the active revision.

## Representation and parsing

`ClosureExpr` records the selected parameter index. `getReceiverParameter()` resolves the corresponding ordinary `ParamDecl`; parameter-list replacement/cloning preserves receiver identity. The method-self identity predicate is unchanged.

The C++ parser and SwiftParser/ASTGen preserve an unescaped `self` keyword in a closure's local parameter-name position when `ClosureReceiverParameters` is enabled. An escaped identifier stays ordinary. Typed ownership modifiers remain part of the parameter, and selection can occur at any parameter position. Duplicate receiver parameters and same-name capture conflicts are diagnosed.

The feature-disabled typed-self spelling retains its earlier interpretation. This distinction requires a release migration decision: experimental opt-in is not a complete source-compatibility solution.

## Lookup and capture

`PreCheckTarget.cpp` finds the active receiver across lexical local contexts, including local functions. It preserves locals/captures and defers unresolved receiver-member lookup until the receiver type is known. The constraint solver checks membership separately within each candidate solution. Existing but inaccessible or inapplicable receiver members prevent global fallback. Dynamic-member lookup follows the normal member path.

The enclosing instance is not an implicit fallback receiver. Capturing an outer alias is explicit. `Self` retains lexical type meaning, and `super` is rejected across the receiver boundary.

Capture provenance distinguishes receiver parameters, valid descended captures/weak unwrapping, and arbitrary values named self. A global fallback discards its unused receiver base so that a nested closure does not accidentally retain that receiver. Ordinary explicit-self diagnostics remain active for nested escaping closures.

## Ownership, effects, and ABI

Receiver lookup eventually becomes ordinary member access. The actual parameter remains borrowing, consuming, inout, isolated, or an ordinary value as declared by its callback type. The binder neither adds a copy nor supplies isolation authority. A supplied argument is distinct from a captured object.

The prototype retains existing noncopyable, nonescapable, capture, actor, Sendable, result-builder, interface, and runtime fixtures. These test selected accepted and rejected programs; they do not prove support for every lifetime-dependent result or accessor shape.

Function types and their manglings are ordinary. Exported signatures do not encode receiver intent. Inlinable/client-emitted bodies still need syntax feature guards, and binary-module clients must accept the ordinary signatures. No runtime/ABI extension is proposed.

## New composition coverage

`test/Constraints/closure_receiver_library_apis.swift` exercises both parser paths where ASTGen is available:

- ordinary callback aliases and named-parameter equivalents;
- receiver selection in first and later parameter positions;
- an API called through a stored function value;
- Array.map, Optional.map, and inout accumulation with Sequence.reduce(into:);
- consuming configuration helpers, immutable receiver diagnostics;
- withTaskGroup and AsyncStream callbacks;
- rejection of bare receiver lookup without a binder, @receiver, and lexical dotted callback invocation.

`test/Interpreter/closure_receiver_library_apis.swift` runs configuration, mapping, accumulation, stored callbacks invoked with different arguments, a builder whose result type differs from its receiver, noncopyable configuration, throwing value/reference examples, task groups, and asynchronous stream consumption. The suite also executes it with optimization.

SwiftParser tests exercise those literal shapes and reject the removed receiver-type grammar. Existing AST unit tests cover receiver selection and parameter cloning.

## Current validation

- Targeted parser suite: 49 tests passed, including 24 receiver tests (`receiver-binding-parser.log`).
- Full SwiftParser suite: 2,761 scheduled tests, zero failures; three long corpus tests disabled by `SKIP_LONG_TESTS=1` (`receiver-binding-parser-full.log`).
- CodeGeneration schema: all 16 tests passed (`receiver-binding-schema.log`).
- Regenerated syntax sources reproduce the restored schema exactly (`receiver-binding-regeneration.log`).
- Assertion-enabled Swift compiler and matching arm64 macOS host libraries rebuilt successfully (`receiver-binding-build.log`).
- Compiler verification: 15 fixture files passed, covering parsing, inference, ownership, captures, isolation, nonescapable values, module interfaces, and execution.
- AST unit tests: 2 passed; neighboring compiler regressions: 8 fixture files passed; optimized runtime: 4 fixture files passed (`receiver-binding-verification.log`).

These are local results, also recorded in `receiver-poc/README.md`; they do not claim compiler-wide or cross-platform validation. Earlier 0.8–0.10 results belong to different source states and are retained only as historical logs.

## Reproduction

Check out the matching Swift and SwiftSyntax branches under `~/projects/apple`:

```sh
~/projects/apple/receiver-poc/build-compiler.sh
~/projects/apple/receiver-poc/verify-compiler.sh
RECEIVER_TEST_FILTER=SwiftParserTest ~/projects/apple/receiver-poc/test-parser.sh --parallel --num-workers 2
```

The helpers set `DEVELOPER_DIR` per process to Xcode 27.2 beta 3 and select its linker for runtime tests. No global Xcode selection is changed. The compiler build uses assertions and matching rebuilt arm64 macOS host libraries. Parser/schema tests independently use the installed Xcode compiler. The build defaults to four jobs.

## Remaining production work

Resolve typed-self source compatibility; audit AST rewrites and all capture contexts; implement SourceKit completion/indexing/refactoring support; measure constraint-solver performance; expand lifetime-dependent result and isolation coverage; and run compiler-wide, cross-platform, and cross-version/back-deployment checks. Ordinary ABI is a design property, not a claim that these broader checks have passed. Local receiver declarations, contextual receiver types, scoped namespaces, and universal fluent helpers are separate design directions.
