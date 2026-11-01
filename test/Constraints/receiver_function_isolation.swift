// RUN: %target-typecheck-verify-swift -swift-version 6 -enable-experimental-feature ClosureReceiverParameters
// REQUIRES: swift_feature_ClosureReceiverParameters

func with<T, R>(_ value: T, _ body: T.() -> R) -> R { body(value) }
actor Worker {
  var number = 1 // expected-note {{property declared here}}
}
func rejectActorAccess(_ worker: Worker) -> Int {
  with(worker) { number } // expected-error {{actor-isolated property 'number' can not be referenced from a nonisolated context}}
}
func withIsolated<R>(_ value: isolated Worker, _ body: (isolated Worker).() -> R) -> R {
  body(value)
}
func isolatedAccess(_ worker: isolated Worker) -> Int {
  withIsolated(worker) { number }
}

final class Box { // expected-note {{class 'Box' does not conform to the 'Sendable' protocol}}
  var number = 1
}
func rejectSendableCapture(_ box: Box) -> @Sendable () -> Int {
  with(box) {
    { @Sendable [self] in number } // expected-error {{capture of 'self' with non-Sendable type 'Box' in a '@Sendable' closure}}
  }
}
func globalOnly() -> Int { 1 }
func noCapture(_ box: Box) -> @Sendable () -> Int {
  with(box) { { @Sendable in globalOnly() } }
}

@resultBuilder
struct Sum {
  static func buildBlock(_ values: Int...) -> Int { values.reduce(0, +) }
}
func build(_ item: Box, @Sum _ body: Box.() -> Int) -> Int { body(item) }
func builder(_ box: Box) -> Int {
  build(box) {
    number
    number
  }
}
