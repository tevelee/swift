// RUN: %target-typecheck-verify-swift -swift-version 6 -enable-experimental-feature ClosureReceiverParameters
// REQUIRES: swift_feature_ClosureReceiverParameters

func with<Value, Result>(_ value: Value, _ body: (Value) -> Result) -> Result {
  body(value)
}

struct Item {
  var value: Int
  func doubled() -> Int { value * 2 }
}

func update<Value>(_ value: inout Value, _ body: (inout Value) -> Void) {
  body(&value)
}

func inferredReceiver() {
  let result: Int = with(Item(value: 21)) { self in doubled() }
  _ = result
  let values: [Int] = [Item(value: 1), Item(value: 2)].map { self in value }
  _ = values
}

func localShadowing() {
  let value = 99
  let result: Int = with(Item(value: 1)) { self in value + self.value }
  _ = result
}

func mutateReceiver() {
  var item = Item(value: 1)
  update(&item) { self in value += 1 }
}

struct Owner {
  var value: Int
  var ownerOnly: Int

  func configure() {
    _ = with(Item(value: 21)) { self in value }
    _ = with(Item(value: 21)) { [owner = self] self in value + owner.value }
    _ = with(Item(value: 21)) { self in ownerOnly } // expected-error {{value of type 'Item' has no member 'ownerOnly'}}
    // Existing escaped spelling keeps lexical outer-instance lookup.
    _ = with(Item(value: 21)) { `self` in value }
  }
}

func escaping(_ body: @escaping () -> Void) {}

final class Request {
  func finish() {}
}

func nestedCaptures(_ request: Request) {
  with(request) { self in
    escaping { [self] in finish() }
    escaping { [weak self] in
      guard let self else { return }
      finish()
    }
    escaping { finish() } // expected-error {{requires explicit use of 'self'}}
  }
}

// An escaping receiver closure receives its argument on each invocation.
let callback: (Request) -> Void = { self in finish() }
