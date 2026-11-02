// RUN: %target-run-simple-swift(-swift-version 6 -enable-experimental-feature PackDestructuring) | %FileCheck %s
// REQUIRES: executable_test
// REQUIRES: swift_feature_PackDestructuring
// REQUIRES: string_processing

import RegexBuilder

func decode<each Capture, Model>(
  _ regex: Regex<(Substring, repeat each Capture)>,
  in input: String,
  using make: (repeat each Capture) -> Model
) throws -> Model? {
  guard let match = try regex.wholeMatch(in: input) else { return nil }
  let (_, each captures) = match.output
  return make(repeat each captures)
}

struct Entry { let count: Int; let label: Substring }
struct Single { let count: Int }
struct Empty {}
struct OptionalEntry { let digits: Substring? }
struct CaptureError: Error {}

func testRegexDestructuring() throws {
  let regex = Regex {
    TryCapture { OneOrMore(.digit) } transform: { Int($0) }
    "-"
    Capture { OneOrMore(.word) }
  }
  let entry = try decode(regex, in: "42-swift", using: Entry.init)!
  print(entry.count, entry.label)
  // CHECK: 42 swift
  print(try decode(regex, in: "invalid", using: Entry.init) == nil)
  // CHECK-NEXT: true

  let number = Regex {
    TryCapture { OneOrMore(.digit) } transform: { Int($0) }
  }
  print(try decode(number, in: "7", using: Single.init)!.count)
  // CHECK-NEXT: 7
  print(try decode(Regex { "plain" }, in: "plain", using: Empty.init) != nil)
  // CHECK-NEXT: true

  let optional = Regex {
    "x"
    Optionally { Capture { OneOrMore(.digit) } }
  }
  print(try decode(optional, in: "x", using: OptionalEntry.init)!.digits == nil)
  // CHECK-NEXT: true
  print(try decode(optional, in: "x42", using: OptionalEntry.init)!.digits!)
  // CHECK-NEXT: 42

  let throwing = Regex {
    TryCapture { "x" } transform: { (_: Substring) -> Int? in
      throw CaptureError()
    }
  }
  do {
    _ = try decode(throwing, in: "x", using: Single.init)
    print("unexpected success")
  } catch is CaptureError {
    print("capture error propagated")
    // CHECK-NEXT: capture error propagated
  }
}

try testRegexDestructuring()
