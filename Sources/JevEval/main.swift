import Foundation
import JevCore

// 将冻结评测集通过产品实际召回实现，避免另写一套近似基线。
struct CaseInput: Decodable {
    struct Item: Decodable { let id: String; let text: String; let copied_at: Double }
    let id: String
    let context: [String: String]
    let history: [Item]
}

do {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let cases = try JSONDecoder().decode([CaseInput].self, from: input)
    var output: [[String: Any]] = []
    for item in cases {
        let entries = item.history.map {
            ClipboardEntry(id: $0.id, text: $0.text, copiedAt: Date(timeIntervalSince1970: $0.copied_at), sourceApp: nil, sourceBundleID: nil, contentHash: "")
        }
        let context = ["field_label", "nearby_text", "selected_text", "window_title"].compactMap { item.context[$0] }.joined(separator: " ")
        let shortlist = CandidateRanker.shortlist(entries: entries, context: context)
        let ranked = CandidateRanker.ranked(entries: entries, context: context)
        output.append(["id": item.id, "candidates": shortlist.map { ["id": $0.id, "text": $0.text] }, "retrieval_id": ranked.first?.id ?? "none"])
    }
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]))
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
