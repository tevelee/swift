// RUN: %empty-directory(%t)
// RUN: split-file %s %t
// RUN: %target-swift-emit-module-interface(%t/PackDestructuringLibrary.swiftinterface) %t/library.swift -enable-experimental-feature PackDestructuring -module-name PackDestructuringLibrary
// RUN: %target-swift-typecheck-module-from-interface(%t/PackDestructuringLibrary.swiftinterface) -module-name PackDestructuringLibrary
// RUN: %FileCheck %s < %t/PackDestructuringLibrary.swiftinterface
// RUN: %target-swift-frontend -emit-module %t/library.swift -enable-experimental-feature PackDestructuring -module-name PackDestructuringLibrary -o %t/PackDestructuringLibrary.swiftmodule
// RUN: %target-swift-frontend -emit-sil -O %t/client.swift -I %t -o %t/client.sil
// REQUIRES: swift_feature_PackDestructuring

// CHECK: #if compiler(>=5.3) && $PackDestructuring
// CHECK: @inlinable public func dropFirst
// CHECK: let (_, each tail) = value

//--- library.swift
@inlinable public func dropFirst<Head, each Tail>(
  _ value: (Head, repeat each Tail)
) -> (repeat each Tail) {
  let (_, each tail) = value
  return (repeat each tail)
}

//--- client.swift
import PackDestructuringLibrary
public func tail() -> String { dropFirst((1, "tail")) }
