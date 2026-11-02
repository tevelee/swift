# Pack destructuring: local compiler proof of concept

This experiment implements `let (head, each tail)` and `let (each prefix, last)` over tuples whose types already identify an expansion component. The marked local is an ordinary abstract tuple value, which can be expanded with `repeat each`.

Both the Swift and SwiftSyntax checkouts are on `feature/pack-destructuring`. The Swift branch starts at local receiver commit `972b26e4`; SwiftSyntax starts at `1cddc909`. Use companion [SwiftSyntax revision `61036d6`](https://github.com/tevelee/swift-syntax/commit/61036d657f9b84fed4c0a64e759cf8b24aa0aed2). The existing receiver branches are preserved. This experiment reuses the assertion-enabled compiler build and matching libraries under `../build/receiver-poc-release`.

## Intended example

```swift
func decode<each Capture, Model>(
  _ regex: Regex<(Substring, repeat each Capture)>,
  in input: String,
  using make: (repeat each Capture) -> Model
) throws -> Model? {
  guard let match = try regex.wholeMatch(in: input) else { return nil }
  let (_, each captures) = match.output
  return make(repeat each captures)
}
```

The whole-match `Substring` provides the known leading scalar. The capture pack may contain zero, one, or multiple distinct types, including transformed capture values. Supplying a model initializer is explicit; this does not infer fields from property names or introduce runtime tuple reflection.

## Build and verify

From this checkout:

```sh
bash utils/pack-destructuring-poc.sh
```

The script rebuilds `swift-frontend` and the lit feature registry, runs the focused parser, semantic, executable, and module-interface tests, checks neighboring pack tests, and executes both new runtime fixtures in optimized mode. It also runs the SwiftSyntax parser and schema checks. Logs go to `../pack-destructuring-poc/logs`. It uses Xcode 27.2 beta 3 through a per-process `DEVELOPER_DIR`; it does not change the system Xcode selection.

`PACK_BUILD_DIR`, `PACK_NINJA`, `PACK_LOG_DIR`, `PACK_JOBS`, and `DEVELOPER_DIR` may override the existing build configuration. This helper expects a configured compiler build with matching host standard libraries; it does not bootstrap a new LLVM/Swift build.

For a direct semantic check:

```sh
../build/receiver-poc-release/swift-macosx-arm64/bin/swift-frontend \
  -typecheck -swift-version 6 \
  -enable-experimental-feature PackDestructuring \
  test/Interpreter/pack_destructuring_regex.swift
```

## Implementation

- `TuplePatternElt` records the source location of the `each` binding marker.
- The C++ parser recognizes the marker only with `PackDestructuring` enabled and initially accepts local immutable name/wildcard bindings.
- SwiftSyntax has a matching feature-gated `eachKeyword` on tuple-pattern elements; the compiler forwards the language feature to SwiftParser for normal parser validation.
- Constraint generation treats the marked position as an expansion while giving the bound variable a tuple containing that expansion. Pattern coercion checks that the corresponding source component is an existing expansion and wraps its type as the local abstract tuple.
- `PackBindingInitialization` feeds the source's normal pack initialization loop into a separate abstract tuple buffer. It uses ordinary element initialization and cleanups, without assuming flat and nested tuple layouts are interchangeable.
- Feature detection and AST printing preserve the marker in exported inlinable bodies.

## Scope

The first implementation targets local `let` patterns, one marked name or wildcard per tuple level, and a source tuple whose pack component is already known. Fixed scalar elements may precede and/or follow it. An initializer is required.

It does not introduce arbitrary unknown-pack splitting, nonempty-pack constraints, local type-pack declarations, mutable pack bindings, recursive pack pattern matching, tuple extensions, or `pack.first`/`pack.last` properties. Named Regex capture tuple labels still have the separate invariant-generic matching limitation documented by the research probes.

This prototype uses the legacy C++ parser with SwiftSyntax round-trip/diagnostic validation enabled. The separate ParserASTGen AST-construction path does not yet transfer the marker and is not supported by this PoC. Full compiler-suite, cross-platform, noncopyable ownership, and release compatibility validation remain outside this local proof of concept.

## Validation record

Before the change, the built assertion-enabled compiler rejects `let (_, each tail)` and `let (each prefix, _)`; the baseline diagnostics are saved in `../pack-destructuring-poc/logs/baseline.log`.

Post-change validation on 2026-11-01, arm64 macOS:

- Assertion-enabled Swift 6.5-dev frontend rebuilt successfully, with matching local SwiftSyntax libraries.
- Five focused compiler fixtures passed: parser diagnostics, semantic typing and rejection, tuple executable behavior, Regex executable behavior, and module-interface/import round-trip. Local log: `focused.log`.
- Both executable fixtures passed again at `-O`. Local log: `optimized.log`.
- Eleven neighboring pack/receiver compiler fixtures passed. Local log: `neighbors.log`.
- Five new SwiftParser tests and 73 neighboring pattern/receiver tests passed. Local logs: `swift-parser-tests.log`, `swift-parser-neighbors.log`.
- All 16 syntax schema checks passed; all 46 generated Swift sources reproduce exactly. Local logs: `syntax-schema-tests.log`, `generated-source-check.log`.

The runtime fixtures verify empty/single/multiple elements, head/tail and middle positions, generic requirements, escaping closures, reference lifetimes, alignment, and exactly-once initializer evaluation. The Regex fixture constructs `Entry(count: 42, label: "swift")`, supports zero/single/optional captures, returns `nil` for no match, and propagates a throwing capture transform. Local output logs: `regex-demo-output.txt`, `destructuring-demo-output.txt`.

Logs are local artifacts under `../pack-destructuring-poc/logs`, outside this repository; the verification script regenerates them. These are focused local results, not full-suite or hosted-CI evidence. No pull request has been opened.
