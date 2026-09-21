import Foundation
import XCTest
@testable import JevCore

final class CandidateRankerTests: XCTestCase {
    private func entry(_ id: Int, _ text: String) -> ClipboardEntry {
        ClipboardEntry(id: String(id), text: text, copiedAt: Date(timeIntervalSince1970: Double(id)), sourceApp: nil, sourceBundleID: nil, contentHash: "hash")
    }
    func testKeepsRecentTwoAndRecallsRelevantOlderEntries() {
        let entries = [entry(1, "dev@example.com"), entry(2, "old unrelated"), entry(3, "another"), entry(4, "noise"), entry(5, "newer"), entry(6, "latest")]
        let result = CandidateRanker.shortlist(entries: entries, context: "Email address", limit: 3)
        XCTAssertEqual(result.map(\.id), ["6", "5", "1"])
    }
    func testChineseBigramsAndURLRecognition() {
        let entries = [entry(1, "杭州研发中心"), entry(2, "https://example.com"), entry(3, "noise"), entry(4, "new")]
        XCTAssertEqual(CandidateRanker.shortlist(entries: entries, context: "研发中心地址", limit: 3).last?.id, "1")
        XCTAssertEqual(CandidateRanker.shortlist(entries: entries, context: "网站链接 URL", limit: 3).last?.id, "2")
    }
    func testLimitsEmptyContextAndUniqueIDs() {
        let entries = [entry(1, "one"), entry(2, "two"), entry(2, "two")]
        XCTAssertEqual(CandidateRanker.shortlist(entries: entries, context: "", limit: 6).count, 2)
        XCTAssertTrue(CandidateRanker.shortlist(entries: entries, context: "", limit: 0).isEmpty)
        XCTAssertEqual(CandidateRanker.shortlist(entries: entries, context: "", limit: 1).map(\.id), ["2"])
    }
}
