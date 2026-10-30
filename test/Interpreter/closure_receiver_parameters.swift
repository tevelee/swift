// RUN: %target-run-simple-swift(-swift-version 6 -enable-experimental-feature ClosureReceiverParameters) | %FileCheck %s
// REQUIRES: executable_test
// REQUIRES: swift_feature_ClosureReceiverParameters

func with<Value, Result>(_ value: Value, _ body: (Value) -> Result) -> Result {
  body(value)
}

struct Item { var value: Int }

func runReceiverTests() {
  let item = Item(value: 21)
  print(with(item) { self in value * 2 })
  // CHECK: 42
  do {
    let value = 99
    print(with(item) { self in value + self.value })
    // CHECK-NEXT: 120
    print([Item(value: 1), Item(value: 2)].map { self in value == 99 ? self.value : 0 })
    // CHECK-NEXT: [1, 2]
  }
}

final class Request {
  var callback: (() -> Void)?
  func finish() {}
}

func runCaptureTests() {
  weak var observed: Request?
  do {
    let request = Request()
    observed = request
    with(request) { self in callback = { [self] in finish() } }
  }
  print(observed != nil)
  // CHECK-NEXT: true
  observed?.callback = nil
  print(observed == nil)
  // CHECK-NEXT: true

  do {
    let request = Request()
    observed = request
    with(request) { self in callback = { [weak self] in self?.finish() } }
  }
  print(observed == nil)
  // CHECK-NEXT: true
}

runReceiverTests()
runCaptureTests()

struct OwnedToken: ~Copyable {
  var value: Int
  borrowing func inspect() -> Int { value }
}

func runOwnedCaptureTests() {
  let makeInspector: (consuming OwnedToken) -> () -> Int = {
    (self: consuming OwnedToken) in
    { [owned = consume self] in owned.inspect() }
  }
  let inspect = makeInspector(OwnedToken(value: 7))
  print(inspect(), inspect())
  // CHECK-NEXT: 7 7
}

runOwnedCaptureTests()
