// RUN: %target-run-simple-swift(-swift-version 6 -enable-experimental-feature ClosureReceiverParameters) | %FileCheck %s
// REQUIRES: executable_test, swift_feature_ClosureReceiverParameters

func with<T, R>(_ value: T, _ body: (T) -> R) -> R { body(value) }
func answer() -> Int { -1 }
func globalOnly() -> Int { 7 }
struct Item { func answer() -> Int { 42 } }
struct Empty {}

print(with(Item()) { self in answer() })
// CHECK: 42
print(with(Empty()) { self in answer() })
// CHECK-NEXT: -1
print(with(Item()) { self in
  func nested() -> Int { answer() }
  return nested()
})
// CHECK-NEXT: 42

final class Box { var number = 21 }
weak var observed: Box?
@MainActor func makeCallback() -> () -> Int {
  let box = Box()
  observed = box
  return with(box) { self in { globalOnly() } }
}
let callback = makeCallback()
print(observed == nil)
print(callback())
// CHECK-NEXT: true
// CHECK-NEXT: 7

@resultBuilder
struct Sum {
  static func buildBlock(_ values: Int...) -> Int { values.reduce(0, +) }
}
func build(_ box: Box, @Sum _ body: (Box) -> Int) -> Int { body(box) }
print(build(Box()) { self in
  number
  number
})
// CHECK-NEXT: 42
