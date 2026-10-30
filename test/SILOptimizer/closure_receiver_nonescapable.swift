// RUN: not %target-swift-frontend -emit-sil -swift-version 6 -enable-experimental-feature ClosureReceiverParameters %s -o /dev/null 2>&1 | %FileCheck %s
// REQUIRES: swift_feature_ClosureReceiverParameters

// Receiving a nonescapable invocation argument is legal. Returning another
// closure that captures that invocation's receiver must retain the ordinary
// lifetime error; the receiver role must not promote the span into ownership.
func escapeView() -> (borrowing Span<Int>) -> () -> Int {
  { self in { self.count } }
}

// CHECK: error: lifetime-dependent variable 'self' escapes its scope
