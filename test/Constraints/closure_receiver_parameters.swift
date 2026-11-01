// RUN: %target-typecheck-verify-swift -swift-version 6 -enable-experimental-feature ClosureReceiverParameters
// RUN: %target-typecheck-verify-swift -swift-version 5 -enable-experimental-feature ClosureReceiverParameters
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
  let total: Int = [Item(value: 1), Item(value: 2)].reduce(0) {
    total, self in total + value
  }
  _ = total
}

func localShadowing() {
  let value = 99
  let result: Int = with(Item(value: 1)) { self in value + self.value }
  _ = result
}

func receiverNameShadowing() {
  with(Item(value: 1)) { self in
    with(Item(value: 2)) { `self` in
      _ = self.value // An ordinary explicit access is still valid.
      _ = doubled() // expected-error {{implicit receiver lookup is unavailable because 'self' is shadowed}}
    }
    do {
      let `self` = Item(value: 3)
      _ = self.value
      _ = doubled() // expected-error {{implicit receiver lookup is unavailable because 'self' is shadowed}}
    }
    _ = doubled() // The selected receiver remains available outside the shadow.
  }
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

class Base {
  func ping() {}
}

class Derived: Base {
  func lexicalTypeAndSuperclass() {
    with(Item(value: 1)) { self in
      // Self remains the enclosing declaration's type, not Item.
      let _: Self.Type = Self.self
      super.ping() // expected-error {{'super' cannot be used in the scope of a closure receiver parameter}}
    }
    with(Item(value: 1)) { self in
      escaping { [self] in
        super.ping() // expected-error {{'super' cannot be used in the scope of a closure receiver parameter}}
      }
    }
  }
}
