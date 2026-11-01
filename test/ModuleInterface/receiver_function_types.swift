// RUN: %empty-directory(%t)
// RUN: split-file %s %t
// RUN: %target-swift-emit-module-interface(%t/Receiver.swiftinterface) %t/library.swift -enable-experimental-feature ClosureReceiverParameters -module-name Receiver
// RUN: %FileCheck %s < %t/Receiver.swiftinterface
// RUN: %target-swift-typecheck-module-from-interface(%t/Receiver.swiftinterface) -module-name Receiver
// RUN: %target-swift-frontend -emit-module %t/library.swift -enable-experimental-feature ClosureReceiverParameters -module-name Receiver -o %t/Receiver.swiftmodule
// RUN: %target-swift-frontend -emit-sil -O %t/client.swift -I %t -enable-experimental-feature ClosureReceiverParameters -o %t/client.sil
// REQUIRES: swift_feature_ClosureReceiverParameters
// CHECK: $ClosureReceiverParameters
// CHECK: public typealias Inspector = Swift::String.() -> Swift::Int
// CHECK: public func inspect(_ body: Swift::String.() -> Swift::Int) -> Swift::Int
//--- library.swift
public typealias Inspector = String.() -> Int
public func inspect(_ body: String.() -> Int) -> Int { body("hello") }
public func configure(_ value: inout Int, _ body: (inout Int).() -> Void) {
  body(&value)
}
@inlinable public func receiverCount(_ value: String) -> Int {
  let body: String.() -> Int = { count }
  return body(value)
}
//--- client.swift
import Receiver
public func run() -> Int {
  let body: Inspector = { count }
  var value = 1
  configure(&value) { self += 1 }
  return inspect(body) + value + receiverCount("hello")
}
