# Receiver function types: experimental POC

The [proposal](ClosureReceiverParameters/PITCH.md) now uses Kotlin-style receiver
function types as its primary design:

```swift
func with<T, R>(_ value: T, _ body: T.() throws -> R) rethrows -> R {
  try body(value)
}
let length = with("hello") { count }
let callback: String.(Int) -> Int = { extra in count + extra }
let result = callback("hello", 2)
```

Enable the sketch with `-enable-experimental-feature ClosureReceiverParameters`.
Build the matching [SwiftSyntax branch](https://github.com/tevelee/swift-syntax/tree/feature/closure-receiver-parameters)
together with this compiler branch.

The receiver is the first invocation argument. It is not captured when the
function value is formed. Its marker survives aliases and serialization;
ordinary and receiver function types are distinct. An adapter closure explicitly
bridges them. Ownership-qualified receivers use `(inout T).() -> R`,
`(borrowing T).() -> R`, or `(consuming T).() -> R`.

The [implementation record](ClosureReceiverParameters/IMPLEMENTATION.md)
describes the representation, contextual-typing boundary, test fixtures, and
remaining work. In particular, the current POC handles explicit type contexts
and direct callback calls; it does not claim complete contextual inference for
arbitrary callees or mixed receiver/ordinary overloads. The earlier explicit
binder remains only as an experimental regression baseline.

Local verification on 2026-11-01 passed all 19 receiver/compiler fixtures,
two receiver AST tests, eight neighboring regressions, and four optimized
runtime fixtures. SwiftParser separately passed 2,762 tests with three skips;
all 16 schema tests passed and generated sources reproduced exactly.

## Compiler checks

After building the compiler and matching host standard library:

```sh
utils/run-test --build skip --build-dir <swift-build-directory> \
  test/Constraints/receiver_function_types.swift \
  test/Interpreter/receiver_function_types.swift \
  test/ModuleInterface/receiver_function_types.swift
```

Run the interpreter fixture in optimized mode as well. The local reproduction
scripts and full evidence log are under `~/projects/apple/receiver-poc`.
