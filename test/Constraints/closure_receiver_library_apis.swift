// RUN: %target-typecheck-verify-swift -typo-correction-limit 0 -swift-version 6 -enable-experimental-feature ClosureReceiverParameters
// RUN: %if swift_feature_ParserASTGen %{ %target-typecheck-verify-swift -typo-correction-limit 0 -swift-version 6 -enable-experimental-feature ClosureReceiverParameters -enable-experimental-feature ParserASTGen %}
// REQUIRES: swift_feature_ClosureReceiverParameters

// Receiver selection belongs to the literal, not the API or function type.
// All signatures in this fixture are ordinary Swift callback types.
func withValue<T, R>(_ value: T, _ body: (T) throws -> R) rethrows -> R {
  try body(value)
}

func configured<T: ~Copyable>(
  _ value: consuming T, _ body: (inout T) throws -> Void
) rethrows -> T {
  var result = consume value
  try body(&result)
  return consume result
}

struct Document {
  var title: String
  var lines: [String] = []
  mutating func append(_ line: String) { lines.append(line) }
}
struct Theme { var separator: String }

typealias Render = (Document, Theme) -> String
let render: Render = { self, theme in title + theme.separator }
let explicitRender: Render = { document, theme in
  document.title + theme.separator
}
let receiverLast: (Theme, Document) -> String = { theme, self in
  title + theme.separator
}

@MainActor func libraryComposition(_ document: Document, _ theme: Theme) {
  let _: String = render(document, theme)
  let _: Render = explicitRender
  let _: Render = render

  let callbackAPI: (Document, (Document) throws -> String) throws -> String = withValue
  let _: String = try! callbackAPI(document) { self in title }

  let _: [String] = [document].map { self in title }
  let _: String? = Optional(document).map { self in title }
  let _: Document = ["first", "second"].reduce(into: document) {
    self, line in append(line)
  }
  let _: Document = configured(document) { self in
    title = "configured"
    append("body")
  }

  // Ordinary closures keep ordinary lookup even with the feature enabled.
  _ = withValue(document) { _ in title } // expected-error {{cannot find 'title' in scope}}
  _ = document.render(theme) // expected-error {{value of type 'Document' has no member 'render'}}
}

// Selecting self does not opt out of standard mutation diagnostics.
func immutableReceiver(_ document: Document) {
  withValue(document) { self in
    title = "invalid" // expected-error {{cannot assign to property: 'self' is a 'let' constant}}
  }
}

func taskGroupReceiver() async -> Int {
  await withTaskGroup(of: Int.self) { self in
    addTask { 20 }
    addTask { 22 }
    var total = 0
    for await value in self { total += value }
    return total
  }
}

func streamReceiver() -> AsyncStream<Int> {
  AsyncStream { self in
    yield(21)
    yield(42)
    finish()
  }
}

// The receiver is supplied at invocation, not captured during formation.
func makeRenderer() -> Render {
  { self, theme in title + theme.separator }
}

// Receiver selection does not introduce an @receiver attribute.
let rejectedMarker: (Document) -> String = { @receiver value in value.title } // expected-error {{'@receiver' is not supported on a closure}}
