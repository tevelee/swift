// RUN: %target-swift-frontend -emit-sil -verify -swift-version 6 -enable-experimental-feature ClosureReceiverParameters %s -o /dev/null
// REQUIRES: swift_feature_ClosureReceiverParameters

struct CapturedResource: ~Copyable {
  var identifier: Int
  borrowing func inspect() -> Int { identifier }
  consuming func close() -> Int { identifier }
}

// A fresh consuming invocation argument may be moved into owned captured
// storage. The returned ordinary repeatable closure can borrow that storage.
func makeOwnedInspector() -> (consuming CapturedResource) -> () -> Int {
  { (self: consuming CapturedResource) in
    { [owned = consume self] in owned.inspect() }
  }
}

// Giving an invocation argument receiver syntax does not make a borrow owned.
func rejectEscapingBorrow() -> (borrowing CapturedResource) -> () -> Int {
  { (self: borrowing CapturedResource) in // expected-error {{'self' cannot be captured by an escaping closure since it is a borrowed parameter}}
    { self.inspect() } // expected-note {{closure capturing 'self' here}}
  }
}

// Formation-time transfer does not make a repeatable closure one-shot.
func rejectRepeatedConsumption() -> (consuming CapturedResource) -> () -> Int {
  { (self: consuming CapturedResource) in
    { [owned = consume self] in owned.close() } // expected-error {{'owned' cannot be consumed when captured by an escaping closure}}
  }
}

func rejectEscapingAccess() -> (inout Int) -> () -> Int {
  { (self: inout Int) in // expected-note {{parameter 'self' is declared 'inout'}}
    { self } // expected-error {{escaping closure captures 'inout' parameter 'self'}} expected-note {{captured here}}
  }
}
