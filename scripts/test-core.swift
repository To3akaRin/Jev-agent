import Foundation

// Command Line Tools 不含 XCTest 时使用的真实核心自检，不替代 CI 中的 XCTest。
@main
struct CoreChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }
    static func unwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw Failure(description: "Expected non-nil record") }
        return value
    }
    static func run(_ name: String, _ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
        print("PASS \(name)")
    }
    static func entry(_ id: Int, _ text: String) -> ClipboardEntry {
        ClipboardEntry(id: String(id), text: text, copiedAt: Date(timeIntervalSince1970: Double(id)))
    }
    static func main() throws {
        print("Core checks: standalone Swift harness (XCTest unavailable)")
        try run("original Unicode text, duplicate refresh, reload") { root in
            let store = try HistoryStore(directory: root)
            let now = Date()
            let first = try unwrap(store.add(text: "  中文 👋\ncode\t", now: now))
            let second = try unwrap(store.add(text: first.text, sourceApp: "Editor", now: now.addingTimeInterval(1)))
            try check(first.id == second.id && store.entries.count == 1, "Duplicate must preserve ID")
            try check(second.text == "  中文 👋\ncode\t" && second.sourceApp == "Editor", "Original content changed")
            _ = try store.add(text: "中文 👋\ncode\t")
            let restored = try HistoryStore(directory: root)
            try check(restored.entries == store.entries && store.entries.count == 2, "Reload mismatch")
        }
        try run("retention boundary and refresh") { root in
            let now = Date()
            let store = try HistoryStore(directory: root, retention: 10)
            _ = try store.add(text: "keep", now: now)
            _ = try store.add(text: "keep", now: now.addingTimeInterval(9))
            try store.prune(now: now.addingTimeInterval(10))
            try check(store.entries.count == 1, "Refresh ignored")
            try store.prune(now: now.addingTimeInterval(19))
            try check(store.entries.isEmpty && store.bytesUsed == 0, "Boundary did not expire")
        }
        try run("capacity eviction and oversized rejection") { root in
            let store = try HistoryStore(directory: root, maxBytes: 1_000)
            let first = try unwrap(store.add(text: String(repeating: "a", count: 400)))
            _ = try store.add(text: String(repeating: "b", count: 400), now: Date().addingTimeInterval(1))
            try check(store.bytesUsed <= 1_000 && !store.entries.contains { $0.id == first.id }, "Capacity failed")
            let before = store.entries
            let rejected = try store.add(text: String(repeating: "中", count: 1_000))
            try check(rejected == nil && before == store.entries, "Oversized input changed history")
        }
        try run("duplicate atomic write space") { root in
            let store = try HistoryStore(directory: root, maxBytes: 800)
            let first = try unwrap(store.add(text: String(repeating: "x", count: 300)))
            let second = try unwrap(store.add(text: first.text, now: Date().addingTimeInterval(1)))
            let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
            try check(first.id == second.id && store.entries.count == 1 && store.bytesUsed <= 800, "Duplicate capacity failed")
            try check(files.count == 1 && !files[0].hasSuffix(".tmp"), "Temporary file leaked")
        }
        try run("corruption, temporary file and tamper recovery") { root in
            try Data("broken".utf8).write(to: root.appendingPathComponent("bad.json"))
            try Data(repeating: 0, count: 100).write(to: root.appendingPathComponent("interrupted.tmp"))
            let store = try HistoryStore(directory: root)
            try check(store.bytesUsed == 0, "Corruption not removed")
            let first = try unwrap(store.add(text: "original"))
            let url = root.appendingPathComponent(first.id + ".json")
            var obj = try unwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            obj["text"] = "tampered"
            try JSONSerialization.data(withJSONObject: obj).write(to: url)
            let restored = try HistoryStore(directory: root)
            try check(restored.entries.isEmpty && restored.bytesUsed == 0, "Tampered record accepted")
        }
        try run("symlink and foreign ID boundaries") { root in
            let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
            try Data("outside".utf8).write(to: outside)
            defer { try? FileManager.default.removeItem(at: outside) }
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.json"), withDestinationURL: outside)
            let store = try HistoryStore(directory: root)
            try store.delete(id: "../" + outside.lastPathComponent)
            try check(FileManager.default.fileExists(atPath: outside.path) && store.entries.isEmpty, "Escaped history directory")
        }
        try run("Unicode search, delete and clear") { root in
            let store = try HistoryStore(directory: root)
            let first = try unwrap(store.add(text: "杭州研发中心\nCafé HELLO 🌏"))
            for query in ["杭州", "cafe", "hello", "🌏"] { try check(store.search(query).map(\.id) == [first.id], "Search missed \(query)") }
            try store.delete(id: first.id)
            try check(store.entries.isEmpty, "Delete failed")
            _ = try store.add(text: "new")
            try store.clear()
            try check(store.entries.isEmpty && store.bytesUsed == 0, "Clear failed")
        }
        try run("English field recall and recent two") { _ in
            let entries = [entry(1, "dev@example.com"), entry(2, "old"), entry(3, "noise"), entry(4, "latest")]
            try check(CandidateRanker.shortlist(entries: entries, context: "Email address", limit: 3).map(\.id) == ["4", "3", "1"], "Email recall failed")
            try check(CandidateRanker.ranked(entries: entries, context: "Email address").first?.id == "1", "Pure relevance baseline failed")
        }
        try run("Chinese bigrams and URL field recall") { _ in
            let entries = [entry(1, "杭州研发中心"), entry(2, "https://example.com"), entry(3, "noise"), entry(4, "new")]
            try check(CandidateRanker.shortlist(entries: entries, context: "研发中心地址", limit: 3).last?.id == "1", "Chinese recall failed")
            try check(CandidateRanker.shortlist(entries: entries, context: "网站链接 URL", limit: 3).last?.id == "2", "URL recall failed")
        }
        try run("limits, deduplicated IDs and empty context") { _ in
            let entries = [entry(1, "one"), entry(2, "two"), entry(2, "two")]
            try check(CandidateRanker.shortlist(entries: entries, context: "", limit: 6).count == 2, "Duplicate IDs")
            try check(CandidateRanker.shortlist(entries: entries, context: "", limit: 0).isEmpty, "Limit zero")
            try check(CandidateRanker.shortlist(entries: entries, context: "", limit: 1).map(\.id) == ["2"], "Limit one")
        }
        print("10 core checks passed")
    }
}
