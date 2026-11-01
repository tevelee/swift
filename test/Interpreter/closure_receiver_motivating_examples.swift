// RUN: %target-run-simple-swift(-swift-version 6 -enable-experimental-feature ClosureReceiverParameters) | %FileCheck %s
// REQUIRES: executable_test, swift_feature_ClosureReceiverParameters, objc_interop

// Executable counterparts of the pitch's four motivating examples. Named
// callbacks provide a behavioral reference for the receiver-binding spelling.
import Foundation

func configured<Value: ~Copyable>(
  _ value: consuming Value,
  _ body: (inout Value) throws -> Void
) rethrows -> Value {
  var result = consume value
  try body(&result)
  return consume result
}

func requestExamples(token: String?, isInteractive: Bool) {
  let endpoint = URL(string: "https://example.invalid/import")!
  let payload = Data("{}".utf8)
  let ordinary = configured(URLRequest(url: endpoint)) { request in
    request.httpMethod = "POST"
    request.httpBody = payload
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    request.timeoutInterval = isInteractive ? 15 : 60
  }
  let request = configured(URLRequest(url: endpoint)) { self in
    httpMethod = "POST"
    httpBody = payload
    setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token {
      setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    timeoutInterval = isInteractive ? 15 : 60
  }
  precondition(request == ordinary)
  precondition(request.httpMethod == "POST" && request.httpBody == payload)
  precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
  precondition(request.value(forHTTPHeaderField: "Authorization") == token.map { "Bearer \($0)" })
  precondition(request.timeoutInterval == (isInteractive ? 15 : 60))
}
requestExamples(token: "example-token", isInteractive: true)
requestExamples(token: nil, isInteractive: false)
print("request configuration: passed")
// CHECK: request configuration: passed

struct Record {
  let id: Int
  let kind: String
  let byteCount: Int
  let isValid: Bool
}
struct ImportReport: Equatable {
  var rejectedIDs: [Int] = []
  var acceptedCount = 0
  var totalBytes = 0
  var countsByKind: [String: Int] = [:]
  var largestRecord = 0
}
func reportExamples(_ records: [Record]) -> ImportReport {
  let ordinary = records.reduce(into: ImportReport()) { report, record in
    guard record.isValid else {
      report.rejectedIDs.append(record.id)
      return
    }
    report.acceptedCount += 1
    report.totalBytes += record.byteCount
    report.countsByKind[record.kind, default: 0] += 1
    report.largestRecord = max(report.largestRecord, record.byteCount)
  }
  let report = records.reduce(into: ImportReport()) { self, record in
    guard record.isValid else {
      rejectedIDs.append(record.id)
      return
    }
    acceptedCount += 1
    totalBytes += record.byteCount
    countsByKind[record.kind, default: 0] += 1
    largestRecord = max(largestRecord, record.byteCount)
  }
  precondition(report == ordinary)
  return report
}
let report = reportExamples([
  Record(id: 1, kind: "image", byteCount: 10, isValid: true),
  Record(id: 2, kind: "image", byteCount: 999, isValid: false),
  Record(id: 3, kind: "image", byteCount: 30, isValid: true),
  Record(id: 4, kind: "text", byteCount: 5, isValid: true),
])
precondition(report.rejectedIDs == [2] && report.acceptedCount == 3)
precondition(report.totalBytes == 45 && report.largestRecord == 30)
precondition(report.countsByKind == ["image": 2, "text": 1])
precondition(reportExamples([]) == ImportReport())
print("import accumulation: passed")
// CHECK-NEXT: import accumulation: passed

enum PacketError: Error { case payloadTooLarge }
struct PacketBuilder: ~Copyable {
  private var bytes: [UInt8] = []
  var count: Int { bytes.count }
  mutating func append(_ byte: UInt8) { bytes.append(byte) }
  mutating func appendBigEndian(_ value: UInt16) {
    append(UInt8(truncatingIfNeeded: value >> 8))
    append(UInt8(truncatingIfNeeded: value))
  }
  mutating func writeLength(_ length: Int, at offset: Int) throws {
    guard let byte = UInt8(exactly: length) else {
      throw PacketError.payloadTooLarge
    }
    bytes[offset] = byte
  }
  consuming func finish() -> [UInt8] { bytes }
}
func buildPacket(
  _ body: (inout PacketBuilder) throws -> Void
) rethrows -> [UInt8] {
  var builder = PacketBuilder()
  try body(&builder)
  return builder.finish()
}
func ordinaryPacket(version: UInt8, readings: [UInt16]) throws -> [UInt8] {
  try buildPacket { builder in
    builder.append(0xCA)
    builder.append(0xFE)
    builder.append(version)
    let lengthOffset = builder.count
    builder.append(0)
    let payloadStart = builder.count
    for reading in readings {
      builder.appendBigEndian(reading)
    }
    try builder.writeLength(builder.count - payloadStart, at: lengthOffset)
  }
}
func receiverPacket(version: UInt8, readings: [UInt16]) throws -> [UInt8] {
  try buildPacket { self in
    append(0xCA)
    append(0xFE)
    append(version)
    let lengthOffset = count
    append(0)
    let payloadStart = count
    for reading in readings {
      appendBigEndian(reading)
    }
    try writeLength(count - payloadStart, at: lengthOffset)
  }
}
let packet = try receiverPacket(version: 1, readings: [0x1234, 0xABCD])
let ordinaryPacketBytes = try ordinaryPacket(version: 1, readings: [0x1234, 0xABCD])
precondition(packet == ordinaryPacketBytes)
precondition(packet == [0xCA, 0xFE, 1, 4, 0x12, 0x34, 0xAB, 0xCD])
let emptyPacket = try receiverPacket(version: 2, readings: [])
precondition(emptyPacket == [0xCA, 0xFE, 2, 0])
for encode in [ordinaryPacket, receiverPacket] {
  do {
    _ = try encode(1, Array(repeating: 0, count: 128))
    preconditionFailure("oversized payload accepted")
  } catch PacketError.payloadTooLarge {}
}
print("noncopyable packet builder: passed")
// CHECK-NEXT: noncopyable packet builder: passed

struct SearchResult: Sendable, Equatable { let id: Int }
struct SearchIndex: Sendable {
  let term: String
  let result: SearchResult?
  func search(_ query: String) async -> SearchResult? {
    await Task.yield()
    return term == query ? result : nil
  }
}
func ordinarySearch(_ indexes: [SearchIndex], query: String) async -> SearchResult? {
  await withTaskGroup(
    of: SearchResult?.self, returning: SearchResult?.self
  ) { group in
    for index in indexes {
      group.addTask { await index.search(query) }
    }
    while let candidate = await group.next() {
      if let match = candidate {
        group.cancelAll()
        return match
      }
    }
    return nil
  }
}
func receiverSearch(_ indexes: [SearchIndex], query: String) async -> SearchResult? {
  await withTaskGroup(
    of: SearchResult?.self, returning: SearchResult?.self
  ) { self in
    for index in indexes {
      addTask { await index.search(query) }
    }
    while let candidate = await next() {
      if let match = candidate {
        cancelAll()
        return match
      }
    }
    return nil
  }
}
let indexes = [
  SearchIndex(term: "swift", result: nil),
  SearchIndex(term: "swift", result: SearchResult(id: 42)),
  SearchIndex(term: "swift", result: nil),
]
for search in [ordinarySearch, receiverSearch] {
  let match = await search(indexes, "swift")
  precondition(match == SearchResult(id: 42))
  let absent = await search(indexes, "absent")
  precondition(absent == nil)
  let empty = await search([], "swift")
  precondition(empty == nil)
}
print("task group coordination: passed")
// CHECK-NEXT: task group coordination: passed
