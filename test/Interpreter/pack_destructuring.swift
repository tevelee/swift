// RUN: %target-run-simple-swift(-swift-version 6 -enable-experimental-feature PackDestructuring) | %FileCheck %s
// REQUIRES: executable_test
// REQUIRES: swift_feature_PackDestructuring

func dropFirst<Head, each Tail>(_ value: (Head, repeat each Tail))
  -> (repeat each Tail) {
  let (_, each tail) = value
  return (repeat each tail)
}

func dropLast<each Prefix, Last>(_ value: (repeat each Prefix, Last))
  -> (repeat each Prefix) {
  let (each prefix, _) = value
  return (repeat each prefix)
}

func middle<Head, each Middle, Last>(
  _ value: (Head, repeat each Middle, Last)
) -> (repeat each Middle) {
  let (_, each middle, _) = value
  return (repeat each middle)
}

func captureTail<Head, each Tail>(
  _ value: (Head, repeat each Tail)
) -> () -> (repeat each Tail) {
  let (_, each tail) = value
  return { (repeat each tail) }
}

final class Token { let value: Int; init(_ value: Int) { self.value = value } }

func producedTail<Head, each Tail>(
  _ make: () -> (Head, repeat each Tail)
) -> (repeat each Tail) {
  let (_, each tail) = make()
  return (repeat each tail)
}

func runDestructuringTests() {
  let empty: () = dropFirst((42))
  let single: String = dropFirst((42, "tail"))
  let multiple: (String, Bool) = dropFirst((42, "tail", true))
  print(empty, single, multiple)
  // CHECK: () tail ("tail", true)

  let emptyPrefix: () = dropLast((42))
  let singlePrefix: String = dropLast(("prefix", 42))
  let multiplePrefix: (String, Bool) = dropLast(("prefix", true, 42))
  print(emptyPrefix, singlePrefix, multiplePrefix)
  // CHECK-NEXT: () prefix ("prefix", true)

  let inner: (UInt64, UInt8) = middle((UInt8(1), UInt64.max, UInt8(2), false))
  print(inner.0 == UInt64.max, inner.1)
  // CHECK-NEXT: true 2

  let escaped = captureTail((0, "captured", true))
  print(escaped())
  // CHECK-NEXT: ("captured", true)

  weak var observed: Token?
  do {
    let token = Token(7)
    observed = token
    let tail: Token = dropFirst((0, token))
    print(tail === token, tail.value)
    // CHECK-NEXT: true 7
  }
  print(observed == nil)
  // CHECK-NEXT: true

  var calls = 0
  let once = producedTail {
    calls += 1
    return (0, "once", true)
  }
  print(calls, once)
  // CHECK-NEXT: 1 ("once", true)
}

runDestructuringTests()
