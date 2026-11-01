// RUN: %target-typecheck-verify-swift -swift-version 6 -enable-experimental-feature ClosureReceiverParameters
// RUN: %if swift_feature_ParserASTGen %{ %target-typecheck-verify-swift -swift-version 6 -enable-experimental-feature ClosureReceiverParameters -enable-experimental-feature ParserASTGen %}
// REQUIRES: swift_feature_ClosureReceiverParameters

struct Item { var count: Int }
func with<T, R>(_ value: T, _ body: T.() throws -> R) rethrows -> R {
  try body(value)
}
let count: Int = with(Item(count: 42)) { count }
let callback: Item.() -> Int = { count }
let result: Int = callback(Item(count: 42))
typealias Action = Item.() -> Int
let aliased: Action = { self.count }
let extra: Item.(Int) -> Int = { offset in count + offset }
let summed = extra(Item(count: 40), 2)
func forwarded(_ body: @escaping Action) -> Action { body }
let stored = forwarded(callback)
let storedResult = stored(Item(count: 42))

struct Other { var count: String }
func choose(_ body: Item.() -> Int) -> Int { body(Item(count: 42)) }
func choose(_ body: Other.() -> String) -> String { body(Other(count: "value")) }
let chosen: Int = choose { count }

struct Resource: ~Copyable { var count: Int }
func inspect<T: ~Copyable, R>(_ value: borrowing T,
                            _ body: (borrowing T).() -> R) -> R {
  body(value)
}
func inspectResource(_ resource: borrowing Resource) -> Int {
  inspect(resource) { count }
}

func configure<T>(_ value: inout T, _ body: (inout T).() -> Void) {
  body(&value)
}
func mutation() {
  var item = Item(count: 1)
  configure(&item) { count += 1 }
}

let ordinary: (Item) -> Int = { $0.count }
let invalidOrdinary: (Item) -> Int = callback // expected-error {{cannot convert value of type 'Item.() -> Int' to specified type '(Item) -> Int'}}
let invalidReceiver: Item.() -> Int = ordinary // expected-error {{cannot convert value of type '(Item) -> Int' to specified type 'Item.() -> Int'}}
let adapted: Item.() -> Int = { ordinary(self) }
let adaptedBack: (Item) -> Int = { item in callback(item) }
let anonymous: Item.(Int) -> Int = { count + $0 }
