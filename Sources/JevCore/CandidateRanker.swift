import Foundation

public enum CandidateRanker {
    /// 先保留最近两条，再填充与字段相关的记录；不依赖网络或模型。
    public static func shortlist(entries: [ClipboardEntry], context: String, limit: Int = 6) -> [ClipboardEntry] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        let recent = entries.sorted {
            $0.copiedAt == $1.copiedAt ? $0.id < $1.id : $0.copiedAt > $1.copiedAt
        }.filter { seen.insert($0.id).inserted }
        var selected = Array(recent.prefix(min(2, limit)))
        let recentIDs = Set(selected.map(\.id))
        let ranked = recent.filter { !recentIDs.contains($0.id) }.map { ($0, score(text: $0.text, context: context)) }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.copiedAt != $1.0.copiedAt { return $0.0.copiedAt > $1.0.copiedAt }
            return $0.0.id < $1.0.id
        }
        selected.append(contentsOf: ranked.prefix(limit - selected.count).map(\.0))
        return selected
    }

    /// 纯相关性排序供基线评测使用，不含最近两条保留位。
    public static func ranked(entries: [ClipboardEntry], context: String) -> [ClipboardEntry] {
        var seen = Set<String>()
        return entries.map { ($0, score(text: $0.text, context: context)) }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.copiedAt != $1.0.copiedAt { return $0.0.copiedAt > $1.0.copiedAt }
            return $0.0.id < $1.0.id
        }.map(\.0).filter { seen.insert($0.id).inserted }
    }

    public static func score(text: String, context: String) -> Double {
        let query = context.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let body = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let queryTokens = tokens(query)
        let bodyTokens = tokens(String(body.prefix(8_192)))
        let overlap = queryTokens.intersection(bodyTokens)
        var value = Double(overlap.count) / max(1, sqrt(Double(bodyTokens.count)))
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["email", "e-mail", "邮箱", "邮件"].contains(where: query.contains),
           trimmed.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil { value += 4 }
        if ["url", "website", "link", "网站", "链接", "网址"].contains(where: query.contains),
           let url = URL(string: trimmed), ["https", "http"].contains(url.scheme ?? ""), url.host != nil { value += 4 }
        if !query.isEmpty, body.contains(query) { value += 2 }
        return value
    }

    /// 英文单词和连续汉字双字片段共享 token 集合，避免依赖系统分词版本。
    static func tokens(_ text: String) -> Set<String> {
        var result = Set<String>()
        var latin = ""
        var chinese: [Unicode.Scalar] = []
        func flushLatin() {
            if !latin.isEmpty { result.insert(latin); latin = "" }
        }
        func flushChinese() {
            if chinese.count == 1 { result.insert(String(chinese[0])) }
            if chinese.count > 1 {
                for index in 1..<chinese.count {
                    result.insert(String(chinese[index - 1]) + String(chinese[index]))
                }
            }
            chinese = []
        }
        for scalar in text.unicodeScalars {
            let isChinese = (0x3400...0x9FFF).contains(scalar.value) || (0x20000...0x2FA1F).contains(scalar.value)
            if isChinese {
                flushLatin()
                chinese.append(scalar)
            } else if CharacterSet.alphanumerics.contains(scalar) {
                flushChinese()
                latin.unicodeScalars.append(scalar)
            } else {
                flushLatin()
                flushChinese()
            }
        }
        flushLatin()
        flushChinese()
        return result
    }
}
