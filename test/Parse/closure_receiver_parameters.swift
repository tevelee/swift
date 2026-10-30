// RUN: %target-swift-frontend -parse -verify -enable-experimental-feature ClosureReceiverParameters %s
// REQUIRES: swift_feature_ClosureReceiverParameters

let shorthand = { self in self.value }
let typed = { (self: Int) in self }
let multiple = { before, self, after in self.value + before + after }
let borrowed = { (self: borrowing Int) in self }
let consumed = { (self: consuming Int) in self }
let mutable = { (self: inout Int) in self += 1 }
let escaped = { `self` in self.value }

let duplicate = { self, self in } // expected-error {{a closure can have only one receiver parameter}}

struct Owner {
  func configure() {
    _ = { [owner = self] self in owner.use(self) }
    _ = { [self] self in } // expected-error {{a receiver parameter and a capture cannot both bind 'self'}}
  }
}
