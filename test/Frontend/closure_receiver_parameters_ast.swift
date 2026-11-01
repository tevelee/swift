// RUN: %target-swift-frontend -dump-parse -enable-experimental-feature ClosureReceiverParameters %s | %FileCheck %s
// RUN: %if swift_feature_ParserASTGen %{ %target-swift-frontend -dump-parse -enable-experimental-feature ClosureReceiverParameters -enable-experimental-feature ParserASTGen %s | %FileCheck %s %}
// REQUIRES: swift_feature_ClosureReceiverParameters

// Receiver selection must agree between ASTGen and the C++ parser.

// CHECK-LABEL: pattern_named "shorthand"
// CHECK: closure_expr{{.*}}receiver_parameter
let shorthand = { self in self.value }

// CHECK-LABEL: pattern_named "typed"
// CHECK: closure_expr{{.*}}receiver_parameter
let typed = { (self: Item) in self.value }

// CHECK-LABEL: pattern_named "middle"
// CHECK: closure_expr{{.*}}receiver_parameter
let middle = { before, self, after in self.value + before + after }

// CHECK-LABEL: pattern_named "escaped"
// CHECK-NOT: closure_expr{{.*}}receiver_parameter
let escaped = { `self` in self.value }

// CHECK-LABEL: pattern_named "ordinary"
// CHECK-NOT: closure_expr{{.*}}receiver_parameter
let ordinary = { item in item.value }
