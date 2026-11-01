// RUN: %target-typecheck-verify-swift -swift-version 6 -enable-experimental-feature ClosureReceiverParameters
// REQUIRES: swift_feature_ClosureReceiverParameters

func with<T, R>(_ value: T, _ body: (T) -> R) -> R { body(value) }
func answer() -> String { "global" }
func globalOnly() -> Int { 7 }
struct Empty {}
struct Token {}
struct Item {
  func answer() -> Int { 42 }
  private func hidden() -> Int { 1 } // expected-note {{'hidden()' declared here}}
}
func hidden() -> Int { 9 }

func lookup() {
  let _: Int = with(Item()) { self in answer() }
  let _: Int = with(Empty()) { self in globalOnly() }
  let _: Token = with(Empty()) { self in Token() }
  let _: Int = with(Item()) { self in Swift.max(1, 2) }
  let _: String = with(Item()) { self in answer() } // expected-error {{conflicting arguments to generic parameter 'R'}} expected-note {{inferred as 'String' from context}} expected-note {{inferred as 'Int' from closure return expression}}
  let _: Int = with(Item()) { self in hidden() } // expected-error {{'hidden' is inaccessible due to 'private' protection level}}
  let _: String = with(Item()) { self in
    func answer() -> String { "local" }
    return answer()
  }
  let _: String = with(Item()) { self in
    let result = answer()
    func answer() -> String { "forward local" }
    return result
  }
}

protocol Answering { func answer() -> Int }
extension Item: Answering {}
func generic<T: Answering>(_ value: T) -> Int {
  with(value) { self in answer() }
}

@dynamicMemberLookup
struct Dynamic {
  subscript(dynamicMember name: String) -> Int { 8 }
}
let dynamicValue = "global"
func dynamic() -> Int { with(Dynamic()) { self in dynamicValue } }

// Membership decisions must remain local to an overload's inferred receiver.
func choose(_ body: (Item) -> Int) -> Int { body(Item()) }
func choose(_ body: (Empty) -> String) -> String { body(Empty()) }
func overloads() {
  let _: Int = choose { self in answer() }
  let _: String = choose { self in answer() }
}

// A global-only nested closure must not capture the receiver merely because
// deferred lookup temporarily used it as a candidate base.
final class Reference {}
func callback() -> () -> Int {
  with(Reference()) { self in { globalOnly() } }
}

func localFunction() -> Int {
  with(Item()) { self in
    func nested() -> Int { answer() }
    return nested()
  }
}
