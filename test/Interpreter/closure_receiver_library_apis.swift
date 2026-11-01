// RUN: %target-run-simple-swift(-swift-version 6 -enable-experimental-feature ClosureReceiverParameters) | %FileCheck %s
// REQUIRES: executable_test, swift_feature_ClosureReceiverParameters

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

let original = Document(title: "draft")
let ready = configured(original) { self in
  title = "ready"
  append("intro")
}
print(original.title, ready.title, ready.lines.count)
// CHECK: draft ready 1

let combined = ["body", "end"].reduce(into: ready) { self, line in
  append(line)
}
print(combined.lines.joined(separator: ","))
// CHECK-NEXT: intro,body,end
print([original, ready].map { self in title }.joined(separator: ","))
// CHECK-NEXT: draft,ready
print(Optional(ready).map { self in title } ?? "absent")
print(Optional<Document>.none.map { self in title } ?? "absent")
// CHECK-NEXT: ready
// CHECK-NEXT: absent

typealias Render = (Document, String) -> String
func makeRenderer() -> Render { { self, suffix in title + suffix } }
let renderer = makeRenderer()
print(renderer(original, "!"), renderer(ready, "?"))
// CHECK-NEXT: draft! ready?
let ordinaryRenderer: Render = { value, suffix in value.title + suffix }
print(ordinaryRenderer(ready, "."))
// CHECK-NEXT: ready.

struct TextBuilder {
  var text = ""
  mutating func append(_ value: String) { text += value }
}
func buildText(_ body: (inout TextBuilder) -> Void) -> String {
  configured(TextBuilder(), body).text
}
print(buildText { self in
  append("scoped")
  append(" builder")
})
// CHECK-NEXT: scoped builder

struct Resource: ~Copyable {
  var identifier: Int
}
let resource = configured(Resource(identifier: 7)) { self in identifier += 1 }
print(resource.identifier)
// CHECK-NEXT: 8

enum Failure: Error { case stopped }
do {
  _ = try configured(original) { self in
    title = "unfinished"
    throw Failure.stopped
  }
} catch {
  print(original.title)
}
// CHECK-NEXT: draft

// Reference semantics are preserved, including mutation before a throw.
final class Box { var value = 1 }
let box = Box()
do {
  _ = try configured(box) { self in
    value = 2
    throw Failure.stopped
  }
} catch {
  print(box.value)
}
// CHECK-NEXT: 2

let total = await withTaskGroup(of: Int.self) { self in
  addTask { 20 }
  addTask { 22 }
  var sum = 0
  for await value in self { sum += value }
  return sum
}
print(total)
// CHECK-NEXT: 42

let stream = AsyncStream<Int> { self in
  yield(10)
  yield(20)
  finish()
}
var streamTotal = 0
for await value in stream { streamTotal += value }
print(streamTotal)
// CHECK-NEXT: 30
