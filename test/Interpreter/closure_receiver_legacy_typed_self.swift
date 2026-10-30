// RUN: %target-run-simple-swift(-swift-version 6) | %FileCheck %s
// REQUIRES: executable_test

// No ClosureReceiverParameters flag: the previously accepted typed spelling
// must retain lexical outer-instance lookup rather than opt into new semantics.
struct LegacyItem { var value: Int }

func legacyWith<T, R>(_ value: T, _ body: (T) -> R) -> R { body(value) }

struct LegacyOwner {
  var value = -1

  func run() {
    print(legacyWith(LegacyItem(value: 42)) { (self: LegacyItem) in value })
    // CHECK: -1
    print(legacyWith(LegacyItem(value: 42)) { (self: LegacyItem) in self.value })
    // CHECK-NEXT: 42
  }
}

LegacyOwner().run()
