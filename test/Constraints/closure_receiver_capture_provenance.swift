// RUN: %target-typecheck-verify-swift -swift-version 6 -verify-additional-prefix swift6- -enable-experimental-feature ClosureReceiverParameters
// RUN: %target-typecheck-verify-swift -swift-version 5 -verify-additional-prefix swift5- -enable-experimental-feature ClosureReceiverParameters
// REQUIRES: swift_feature_ClosureReceiverParameters

func with<T, R>(_ value: T, _ body: (T) -> R) -> R { body(value) }
func immediate<T>(_ body: () -> T) -> T { body() }
struct Item { var number = 1 }
func rejectUnrelatedBindings(_ other: Item) {
  let invoke: (() -> Int) -> Int = immediate
  with(Item()) { self in
    _ = invoke { [self = other] in // expected-note {{variable other than 'self' captured here}}
      number // expected-swift6-error {{requires explicit use of 'self'}} expected-swift5-warning {{requires explicit use of 'self'}}
    }
    do {
      let `self` = other
      _ = invoke { [self] in // expected-swift5-note {{variable other than 'self' captured here}}
        number // expected-swift6-error {{requires explicit use of 'self'}} expected-swift5-warning {{requires explicit use of 'self'}} expected-swift6-note {{reference 'self.' explicitly}}
      }
    }
  }
}

final class Box { var number = 1 }
func acceptCaptureChain(_ box: Box) -> () -> Int {
  with(box) { self in
    { [weak self] in
      guard let self else { return 0 }
      return immediate { [self] in number }
    }
  }
}
