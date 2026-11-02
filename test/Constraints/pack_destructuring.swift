// RUN: %target-swift-frontend -typecheck -verify -enable-experimental-feature PackDestructuring %s
// REQUIRES: swift_feature_PackDestructuring

func tail<Head, each Tail>(_ value: (Head, repeat each Tail))
  -> (repeat each Tail) {
  let (head, each rest) = value
  let _: Head = head
  let typed: (repeat each Tail) = rest
  return (repeat each typed)
}

func prefix<each Prefix, Last>(_ value: (repeat each Prefix, Last))
  -> (repeat each Prefix) {
  let (each rest, last) = value
  let _: Last = last
  return (repeat each rest)
}

func preserveRequirements<Head, each Tail: Equatable>(
  _ value: (Head, repeat each Tail)
) -> Bool {
  let (_, each tail) = value
  for item in repeat each tail {
    if item != item { return false }
  }
  return true
}

func annotated<Head, each Tail>(_ value: (Head, repeat each Tail))
  -> (repeat each Tail) {
  let (_, each tail): (Head, repeat each Tail) = value
  return (repeat each tail)
}

func rejectScalar(_ value: (Int, String)) {
  let (_, each tail) = value // expected-error {{'each' binding must correspond to an existing tuple pack expansion}}
}
