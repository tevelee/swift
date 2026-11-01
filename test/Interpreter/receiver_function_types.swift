// RUN: %target-run-simple-swift(-swift-version 6 -enable-experimental-feature ClosureReceiverParameters) | %FileCheck %s
// REQUIRES: executable_test, swift_feature_ClosureReceiverParameters

func with<T, R>(_ value: T, _ body: T.() throws -> R) rethrows -> R {
  try body(value)
}
struct Item { var count: Int }
let callback: Item.(Int) -> Int = { delta in count + delta }
print(callback(Item(count: 40), 2))
// CHECK: 42
print(with("hello") { count })
// CHECK-NEXT: 5
func configure<T>(_ value: inout T, _ body: (inout T).() -> Void) {
  body(&value)
}
var item = Item(count: 0)
configure(&item) { count = 42 }
print(item.count)
// CHECK-NEXT: 42

final class Box {
  var count = 7
  var action: (() -> Int)?
}
@MainActor func weakCapture() {
  var box: Box? = Box()
  let action: () -> Int = with(box!) {
    { [weak self] in
      guard let self else { return -1 }
      return count
    }
  }
  print(action())
  box = nil
  print(action())
}
weakCapture()
// CHECK-NEXT: 7
// CHECK-NEXT: -1
