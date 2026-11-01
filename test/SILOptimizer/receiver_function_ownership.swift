// RUN: %target-swift-frontend -emit-sil -verify -swift-version 6 -enable-experimental-feature ClosureReceiverParameters %s -o /dev/null
// REQUIRES: swift_feature_ClosureReceiverParameters

struct Resource: ~Copyable {
  var identifier: Int
  borrowing func inspect() -> Int { identifier }
  consuming func close() -> Int { identifier }
}

func withBorrowed<Value: ~Copyable & ~Escapable, Result: ~Copyable>(
  _ value: borrowing Value,
  _ body: (borrowing Value).() -> Result
) -> Result {
  body(value)
}

func configured<Value: ~Copyable>(
  _ value: consuming Value,
  _ body: (inout Value).() -> Void
) -> Value {
  var result = consume value
  body(&result)
  return consume result
}

func useNoncopyable() {
  let resource = Resource(identifier: 7)
  _ = withBorrowed(resource) { inspect() }
  let updated = configured(consume resource) { identifier += 1 }
  _ = updated.inspect()
}

func rejectBorrowedConsumption(_ resource: borrowing Resource) {
  _ = withBorrowed(resource) { close() } // expected-error {{'self' is borrowed and cannot be consumed}} expected-note {{consumed here}}
}

// A stored callback need not capture any particular nonescapable argument.
func makeCounter() -> (borrowing Span<Int>).() -> Int {
  { count }
}

@available(macOS 26.0, iOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
func inspectSpan(_ values: [Int]) -> Int {
  withBorrowed(values.span) { count }
}
