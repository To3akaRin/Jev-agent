import CryptoKit
import Foundation

public struct ClipboardEntry: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let text: String
    public var copiedAt: Date
    public var sourceApp: String?
    public var sourceBundleID: String?
    public let contentHash: String

    public init(id: String = UUID().uuidString, text: String, copiedAt: Date = Date(), sourceApp: String? = nil, sourceBundleID: String? = nil, contentHash: String? = nil) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.contentHash = contentHash ?? Self.hash(text)
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// 专用历史目录，同一个实例由调用方串行访问。容量按文件逻辑字节计算。
public final class HistoryStore {
    public private(set) var entries: [ClipboardEntry] = []
    public let directory: URL
    public let maxBytes: Int
    public let retention: TimeInterval
    private let files = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    public var bytesUsed: Int {
        // 将未知文件也计入限额，不能因为没有加载为记录而忽略已占用空间。
        guard let urls = try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return 0 }
        return urls.reduce(0) { total, url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true, values?.isRegularFile == true else { return total }
            return total + (values?.fileSize ?? 0)
        }
    }

    public init(directory: URL, maxBytes: Int = 20_000_000, retention: TimeInterval = 259_200) throws {
        guard maxBytes > 0, retention > 0, retention.isFinite else {
            throw HistoryError.invalidConfiguration
        }
        self.directory = directory
        self.maxBytes = maxBytes
        self.retention = retention
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let urls = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .fileSizeKey])
        for url in urls {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true || url.pathExtension == "tmp" {
                try files.removeItem(at: url)
                continue
            }
            guard url.pathExtension == "json" else { continue }
            guard (values.fileSize ?? 0) <= maxBytes,
                  let data = try? Data(contentsOf: url),
                  let entry = try? JSONDecoder().decode(ClipboardEntry.self, from: data),
                  UUID(uuidString: entry.id) != nil,
                  url.deletingPathExtension().lastPathComponent == entry.id,
                  !entry.text.isEmpty,
                  entry.copiedAt.timeIntervalSinceReferenceDate.isFinite,
                  entry.contentHash == ClipboardEntry.hash(entry.text) else {
                try files.removeItem(at: url)
                continue
            }
            entries.append(entry)
        }
        sortEntries()
        // 中断的历史版本可能留下重复正文，启动时只保留最近记录。
        var hashes = Set<String>()
        for entry in entries {
            if !hashes.insert(entry.contentHash).inserted { try delete(id: entry.id) }
        }
        try prune()
    }

    @discardableResult
    public func add(text: String, sourceApp: String? = nil, sourceBundleID: String? = nil, now: Date = Date()) throws -> ClipboardEntry? {
        guard !text.isEmpty, now.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let hash = ClipboardEntry.hash(text)
        let existing = entries.first { $0.contentHash == hash && $0.text == text }
        let entry = ClipboardEntry(id: existing?.id ?? UUID().uuidString, text: text, copiedAt: now, sourceApp: sourceApp, sourceBundleID: sourceBundleID, contentHash: hash)
        let data = try encoder.encode(entry)
        // 超大单条不得驱逐已有记录，也不得截断原文。
        guard data.count <= maxBytes else { return nil }
        try prune(now: now)
        // 先为完整临时文件预留空间，写入峰值同样不超过限额。
        while bytesUsed > maxBytes - data.count {
            guard let oldest = entries.last else { return nil }
            try delete(id: oldest.id)
        }
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        defer { try? files.removeItem(at: temporary) }
        try data.write(to: temporary, options: [.withoutOverwriting])
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        let destination = fileURL(entry.id)
        // POSIX rename 在同目录原子替换，避免 Foundation replaceItem 的备份副本。
        let status = temporary.path.withCString { source in
            destination.path.withCString { target in rename(source, target) }
        }
        guard status == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        sortEntries()
        return entry
    }

    public func prune(now: Date = Date()) throws {
        for entry in entries where now.timeIntervalSince(entry.copiedAt) >= retention {
            try delete(id: entry.id)
        }
        while bytesUsed > maxBytes, let oldest = entries.last {
            try delete(id: oldest.id)
        }
    }

    public func delete(id: String) throws {
        // 只接受已经加载的 ID，外部字符串不能构造路径逃逸。
        guard entries.contains(where: { $0.id == id }) else { return }
        let path = fileURL(id)
        if files.fileExists(atPath: path.path) { try files.removeItem(at: path) }
        entries.removeAll { $0.id == id }
    }

    public func clear() throws {
        for entry in entries { try delete(id: entry.id) }
    }

    public func search(_ query: String) -> [ClipboardEntry] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return entries }
        return entries.filter {
            $0.text.range(of: normalized, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || ($0.sourceApp?.range(of: normalized, options: [.caseInsensitive, .diacriticInsensitive]) != nil)
        }
    }

    private func fileURL(_ id: String) -> URL { directory.appendingPathComponent(id + ".json") }
    private func sortEntries() {
        entries.sort { $0.copiedAt == $1.copiedAt ? $0.id < $1.id : $0.copiedAt > $1.copiedAt }
    }
}

public enum HistoryError: Error { case invalidConfiguration }
