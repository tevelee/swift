# Receiver function types: implementation record

Revision 0.8 changes the primary design from an explicit closure binder to Kotlin-style receiver function types, `T.(A) -> R`. The [proposal](PITCH.md) is a draft, not an accepted Swift feature.

## Representation and parsing

SwiftSyntax's `FunctionTypeSyntax` has optional `receiver` and `period` children. Both SwiftParser and the compiler's C++ parser accept the new grammar behind `ClosureReceiverParameters`. ASTGen preserves the receiver through bridging.

`FunctionTypeRepr` records the receiver role separately from its argument list. Semantic function types place the receiver first in invocation order and mark that parameter in `ParameterTypeFlags`. Ordinary arguments follow it. This lets generic substitution and aliases preserve receiver intent without changing the ordinary argument passing convention.

The parameter marker is serialized in Swift modules, and the experimental module-format minor version is incremented. AST printing emits the dot notation. Mangling uses an experimental `YR` parameter annotation, with matching demangling/remangling support; this is not a reserved upstream mangling assignment.

Receiver and ordinary function types are distinct in constraint matching. Explicit adapter closures bridge them; no automatic function-value conversion is proposed in this revision.

## Contextual closure formation

The prototype recognizes a receiver context from an explicitly typed initializer or a directly referenced callable's callback type. It also accepts overload sets when all candidates identify a receiver callback with the same invocation arity. Only the receiver role is selected at this stage: the receiver's actual type remains available for constraint inference.

Before body precheck, it prepends an implicit `self` parameter to the closure's ordinary parameter list. Explicit names and `$0` therefore continue to identify the ordinary parameters after the receiver. The receiver-role query is separate from method-self identity.

This is a bounded contextual-typing implementation. General mixed receiver/ordinary overload sets, callback argument matching involving omitted defaults or reordered labels, and arbitrary member/higher-order callee expressions need solver-integrated contextual formation. They are not established by the direct-call fixtures. The language design describes their intended behavior; this POC does not claim complete contextual inference.

## Lookup and capture

The implementation reuses the previous receiver lookup machinery: lexical locals win, receiver membership is deferred until the type is known, and globals are considered only when neither viable nor unviable receiver members exist. An inaccessible or ill-typed member still shadows a global. Selecting a global discards the unused receiver base rather than creating an accidental capture.

Nested local functions inherit the receiver. Nested receiver closures select their own receiver. Capture provenance must reach a genuine receiver parameter through valid captures and optional unwrapping. An arbitrary variable merely named `self` is not sufficient.

The receiver is an invocation argument, not closure storage. Ordinary ownership and escape checking govern inout, borrowing, consuming, noncopyable, nonescapable, and actor-isolated arguments. Receiver lookup itself introduces no copy, retain, or isolation privilege.

## Validation

Verified locally on 2026-11-01:

| Check | Result |
| --- | --- |
| SwiftParser with raw-syntax validation | 2,762 tests, 3 skipped, zero failures; 25 receiver test methods |
| CodeGeneration schema | All 16 tests passed |
| Regenerated syntax sources | Five generated files reproduce exactly |
| Patched compiler and matching host standard library | Built on arm64 macOS with assertions |
| Receiver compiler fixtures | 19 passed: six contextual receiver-type fixtures plus 13 explicit-binder regression fixtures |
| Receiver AST unit tests | Both passed |
| Neighboring closure/parser/ownership regressions | Eight passed |
| Optimized runtime fixtures | All four passed |

The combined run is `receiver-poc/logs/receiver-function-verification.log`.

The exact local verification results are recorded in `~/projects/apple/receiver-poc/README.md` and its logs. Tests use the patched compiler and matching rebuilt host standard library on arm64 macOS. SwiftParser/schema tests separately use Xcode's compiler. Compiler-wide and cross-platform testing are outside this local POC.

New fixtures:

- `test/Constraints/receiver_function_types.swift`: contextual receiver binding, explicit storage, aliases, ordinary invocation, additional parameters, overload inference, noncopyable borrowing, and inout mutation; both C++ and ASTGen parser paths.
- `test/Constraints/receiver_function_isolation.swift`: actor isolation, Sendable captures, capture-free global fallback, and result builders.
- `test/SILOptimizer/receiver_function_ownership.swift` and `receiver_function_nonescapable.swift`: noncopyable ownership and nonescapable lifetime enforcement with contextual receivers.
- `test/Interpreter/receiver_function_types.swift`: actual invocation, mutation, and weak-capture release.
- `test/ModuleInterface/receiver_function_types.swift`: feature-guarded type printing, interface reconstruction, and an optimized client importing serialized receiver callback types.

The earlier explicit-binder implementation and its fixtures remain as an experimental regression baseline. Their passing results alone do not validate contextual receiver formation. The new proposal does not require adopting both syntaxes.

## Reproduction

Build the matching Swift and SwiftSyntax branches under `~/projects/apple` with the helper in `receiver-poc/build-compiler.sh`. Run `receiver-poc/verify-compiler.sh` for the selected compiler tests and `RECEIVER_TEST_FILTER=SwiftParserTest receiver-poc/test-parser.sh` for the parser suite.

The local build uses Xcode 27.2 beta 3's SDK and linker through per-process `DEVELOPER_DIR`; runtime tests additionally select that toolchain with `SWIFT_DRIVER_TEST_OPTIONS`. Do not supply Xcode as `--native-swift-tools-path`, because the new compiler must build its matching standard library. No global Xcode selection is changed.

## Before production integration

Complete solver-integrated contextual formation and diagnostic recovery, audit remaining type rewrites and runtime reflection, reserve the mangling/serialization representation upstream, and validate lifetime-dependent results, builders, isolation, and back deployment with the new contextual syntax. Benchmark overload-heavy examples and run the broader compiler and SourceKit suites. Optimized runtime checks are not a proof of general SIL equivalence.
