// RUN: %empty-directory(%t)
// RUN: split-file %s %t
// RUN: %target-swift-emit-module-interface(%t/Receiver.swiftinterface) %t/library.swift -enable-experimental-feature ClosureReceiverParameters -module-name Receiver
// RUN: %target-swift-typecheck-module-from-interface(%t/Receiver.swiftinterface) -module-name Receiver
// RUN: %FileCheck %s < %t/Receiver.swiftinterface
// RUN: %target-swift-frontend -emit-module %t/library.swift -enable-experimental-feature ClosureReceiverParameters -module-name Receiver -o %t/Receiver.swiftmodule
// RUN: %target-swift-frontend -emit-sil -O %t/client.swift -I %t -o %t/client.sil
// REQUIRES: swift_feature_ClosureReceiverParameters

// CHECK: #if compiler(>=5.3) && $ClosureReceiverParameters
// CHECK: @inlinable public func receiverCount
// CHECK: { self in count }
// CHECK: #if compiler(>=5.3) && $ClosureReceiverParameters
// CHECK: @_alwaysEmitIntoClient public func clientCount
// CHECK: { self in count }

//--- library.swift
@inlinable public func with<T, R>(_ value: T, _ body: (T) -> R) -> R {
  body(value)
}

@inlinable public func receiverCount(_ value: String) -> Int {
  with(value) { self in count }
}

@_alwaysEmitIntoClient public func clientCount(_ value: String) -> Int {
  with(value) { self in count }
}

//--- client.swift
import Receiver
public func counts(_ value: String) -> Int {
  receiverCount(value) + clientCount(value)
}
