import Foundation
import XCTest
@testable import JevCore

final class HistoryStoreTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testPreservesOriginalAndDeduplicatesWithoutNormalizingWhitespace() throws {
        let store = try HistoryStore(directory: directory)
        let first = try XCTUnwrap(store.add(text: "  中文 👋\ncode\t", now: Date()))
        let second = try XCTUnwrap(store.add(text: first.text, sourceApp: "Editor", now: first.copiedAt.addingTimeInterval(1)))
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(second.sourceApp, "Editor")
        XCTAssertEqual(second.text, "  中文 👋\ncode\t")
        _ = try store.add(text: "中文 👋\ncode\t")
        XCTAssertEqual(store.entries.count, 2)
        let restored = try HistoryStore(directory: directory)
        XCTAssertEqual(restored.entries, store.entries)
    }

    func testRetentionBoundaryAndDuplicateRefresh() throws {
        let now = Date()
        let store = try HistoryStore(directory: directory, retention: 10)
        let first = try XCTUnwrap(store.add(text: "keep", now: now))
        _ = try store.add(text: "keep", now: now.addingTimeInterval(9))
        try store.prune(now: now.addingTimeInterval(10))
        XCTAssertEqual(store.entries.map(\.id), [first.id])
        try store.prune(now: now.addingTimeInterval(19))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.bytesUsed, 0)
    }

    func testCapacityEvictsOldestAndRejectsOversizedWithoutPartialText() throws {
        let store = try HistoryStore(directory: directory, maxBytes: 1_000)
        let first = try XCTUnwrap(store.add(text: String(repeating: "a", count: 400), now: Date()))
        _ = try store.add(text: String(repeating: "b", count: 400), now: Date().addingTimeInterval(1))
        XCTAssertLessThanOrEqual(store.bytesUsed, 1_000)
        XCTAssertFalse(store.entries.contains { $0.id == first.id })
        let before = store.entries
        XCTAssertNil(try store.add(text: String(repeating: "中", count: 1_000)))
        XCTAssertEqual(store.entries, before)
        XCTAssertLessThanOrEqual(store.bytesUsed, 1_000)
    }

    func testDuplicateUpdateWithinCapacityAndNoTemporaryFilesRemain() throws {
        let store = try HistoryStore(directory: directory, maxBytes: 800)
        let entry = try XCTUnwrap(store.add(text: String(repeating: "x", count: 300)))
        let updated = try XCTUnwrap(store.add(text: entry.text, now: Date().addingTimeInterval(1)))
        XCTAssertEqual(entry.id, updated.id)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertLessThanOrEqual(store.bytesUsed, 800)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(files.count, 1)
        XCTAssertFalse(files.contains { $0.hasSuffix(".tmp") })
    }

    func testStartupRemovesCorruptAndInterruptedRecords() throws {
        try Data("broken".utf8).write(to: directory.appendingPathComponent("bad.json"))
        try Data(repeating: 0, count: 100).write(to: directory.appendingPathComponent("interrupted.tmp"))
        let store = try HistoryStore(directory: directory)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.bytesUsed, 0)
    }

    func testRejectsTamperedRecordAndDoesNotFollowSymlink() throws {
        let store = try HistoryStore(directory: directory)
        let entry = try XCTUnwrap(store.add(text: "original"))
        let path = directory.appendingPathComponent(entry.id + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        object["text"] = "changed"
        try JSONSerialization.data(withJSONObject: object).write(to: path)
        let outside = directory.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try Data("outside".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link.json"), withDestinationURL: outside)
        let reopened = try HistoryStore(directory: directory)
        XCTAssertTrue(reopened.entries.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testSearchUnicodeAndDeleteClear() throws {
        let store = try HistoryStore(directory: directory)
        let entry = try XCTUnwrap(store.add(text: "杭州研发中心\nCafé HELLO 🌏"))
        XCTAssertEqual(store.search("杭州").map(\.id), [entry.id])
        XCTAssertEqual(store.search("cafe").map(\.id), [entry.id])
        XCTAssertEqual(store.search("hello").map(\.id), [entry.id])
        try store.delete(id: "../../outside")
        XCTAssertEqual(store.entries.count, 1)
        try store.delete(id: entry.id)
        XCTAssertTrue(store.entries.isEmpty)
        _ = try store.add(text: "new")
        try store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.bytesUsed, 0)
    }
}
