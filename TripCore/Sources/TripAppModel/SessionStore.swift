import Foundation

public struct StoredSession: Codable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var theirLanguage: String
    /// 我方语言（P4，可选以兼容旧存档；nil = 中文）
    public var myLanguage: String?
    public var messages: [Message]
}

/// 会话持久化（技术设计 v2 §4）：原子写入、损坏备份、4 小时询问、30 天清理、清除本机对话。
public final class SessionStore {
    public let directory: URL
    private let fm = FileManager.default
    private let now: () -> Date
    public var current: URL { directory.appendingPathComponent("session-current.json") }

    public init(directory: URL, now: @escaping () -> Date = Date.init) {
        self.directory = directory; self.now = now
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public enum LoadResult: Equatable { case empty, restored(StoredSession), askContinue(StoredSession), corrupt }

    public func load() -> LoadResult {
        guard fm.fileExists(atPath: current.path) else { return .empty }
        do {
            let s = try decoder.decode(StoredSession.self, from: Data(contentsOf: current))
            if s.messages.isEmpty { return .empty }
            return now().timeIntervalSince(s.updatedAt) >= 4 * 3600 ? .askContinue(s) : .restored(s)
        } catch {
            let ts = Int(now().timeIntervalSince1970)
            try? fm.moveItem(at: current, to: directory.appendingPathComponent("session-corrupt-\(ts).json"))
            return .corrupt
        }
    }

    public func save(_ s: StoredSession) throws {
        var s = s; s.updatedAt = now()
        let data = try encoder.encode(s)
        try data.write(to: current, options: .atomic)
        var u = current; var v = URLResourceValues(); v.isExcludedFromBackup = true; try? u.setResourceValues(v)
        #if os(iOS)
        try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: current.path)
        #endif
    }

    /// 「继续」：刷新 updatedAt，避免每次启动都问。
    public func touch(_ s: StoredSession) throws { try save(s) }

    /// 新对话：默认把上一场归档（不可浏览，只为恢复）；勾选「同时删除上一场」则直接删除。
    public func startNew(theirLanguage: String, myLanguage: String? = nil, deletePrevious: Bool) throws -> StoredSession {
        if fm.fileExists(atPath: current.path) {
            if deletePrevious { try fm.removeItem(at: current) }
            else {
                let ts = Int(now().timeIntervalSince1970)
                try fm.moveItem(at: current, to: directory.appendingPathComponent("session-\(ts).json"))
            }
        }
        let s = StoredSession(id: UUID(), createdAt: now(), updatedAt: now(), theirLanguage: theirLanguage, myLanguage: myLanguage, messages: [])
        try save(s)
        return s
    }

    /// 清除本机对话：当前、归档、损坏备份全部删除。
    public func deleteAll() throws {
        for f in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where f.lastPathComponent.hasPrefix("session-") {
            try fm.removeItem(at: f)
        }
    }

    /// 启动时清理：归档超过 30 天、损坏备份超过 7 天。当前文件不删。
    public func cleanup() {
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for f in files where f != current && f.lastPathComponent.hasPrefix("session-") {
            let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now()
            let limit: TimeInterval = f.lastPathComponent.hasPrefix("session-corrupt-") ? 7 * 86400 : 30 * 86400
            if now().timeIntervalSince(d) > limit { try? fm.removeItem(at: f) }
        }
    }

    public func fileNames() -> [String] {
        ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    private var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
    private var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
