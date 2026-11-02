// RUN: %target-swift-frontend -parse -verify -enable-experimental-feature PackDestructuring %s
// REQUIRES: swift_feature_PackDestructuring

func patterns() {
  let (head, each tail) = value
  let (each prefix, last) = value
  let (_, each tail, _) = value
  let (_, each _) = value
  let (each, ordinary) = value
  let (`each`, escaped) = value

  var (_, each mutable) = value // expected-error {{pack destructuring currently requires a local 'let' binding}}
  let (each a, each b) = value // expected-error {{a tuple pattern can contain only one 'each' binding}}
  let (each all) = value // expected-error {{pack destructuring currently requires a fixed tuple element}}
}

struct Invalid {
  let (_, each stored) = value // expected-error {{pack destructuring currently requires a local 'let' binding}}
}
