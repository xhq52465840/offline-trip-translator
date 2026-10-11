import Foundation
#if canImport(Security)
import Security
#endif

/// 试用口径（决策 D3）：从「第一次真正翻译出一条消息」开始，24 小时内不限量。
/// 不从安装/下载算起，出发前在家下载、试几句也只是开始计时的那一刻才开始。
public enum TrialPolicy {
    public static let duration: TimeInterval = 24 * 3600
    /// 剩余不足这么多小时时横幅加「建议现在连网购买」
    public static let warnHours = 3
}

/// 持久化的试用记录（钥匙串）。consumed 只增不减：改系统时间不能把时间要回来。
public struct TrialRecord: Codable, Equatable, Sendable {
    public var startedAt: Date?
    public var consumed: TimeInterval = 0
    public var lastWall: Date?
    public var lastUptime: TimeInterval?
    public init(startedAt: Date? = nil, consumed: TimeInterval = 0, lastWall: Date? = nil, lastUptime: TimeInterval? = nil) {
        self.startedAt = startedAt; self.consumed = consumed; self.lastWall = lastWall; self.lastUptime = lastUptime
    }
    /// 推进已用时间：取墙钟增量与单调时钟（开机后时长）增量中较大者；墙钟倒退时用单调时钟；
    /// 重启后单调时钟归零且墙钟倒退时无法得知真实时长，记 0（对用户略宽松，但拿不回已用时间）。
    public mutating func advance(wall: Date, uptime: TimeInterval) {
        guard startedAt != nil else { return }
        if let lw = lastWall {
            let dw = wall.timeIntervalSince(lw)
            let du: TimeInterval? = lastUptime.flatMap { uptime >= $0 ? uptime - $0 : nil }
            consumed += max(0, dw, du ?? 0)
        }
        // 墙钟倒退时不把 lastWall 往回拨，避免之后再前进时重复计时以外的漏洞
        lastWall = max(lastWall ?? wall, wall); lastUptime = uptime
    }
}

public protocol TrialStore: AnyObject {
    func load() -> TrialRecord
    func save(_ r: TrialRecord)
}

public final class InMemoryTrialStore: TrialStore {
    private var r: TrialRecord
    public init(_ r: TrialRecord = TrialRecord()) { self.r = r }
    /// 已经用完 24 小时的记录（测试用）
    public static func expired() -> InMemoryTrialStore {
        InMemoryTrialStore(TrialRecord(startedAt: Date(timeIntervalSince1970: 0), consumed: TrialPolicy.duration))
    }
    public func load() -> TrialRecord { r }
    public func save(_ x: TrialRecord) { r = x }
}

#if canImport(Security)
/// 钥匙串存储（技术设计 v2 §15），仅本机，首次解锁后可读；卸载重装不清除（钥匙串保留）。
public final class KeychainTrialStore: TrialStore {
    private let service: String, account: String
    public init(service: String = "app.tripunderstand", account: String = "trial.v2") { self.service = service; self.account = account }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    public func load() -> TrialRecord {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let d = item as? Data,
              let r = try? JSONDecoder().decode(TrialRecord.self, from: d) else { return TrialRecord() }
        return r
    }
    public func save(_ r: TrialRecord) {
        guard let data = try? JSONEncoder().encode(r) else { return }
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}
#endif

/// 时间来源：墙钟 + 单调时钟（开机后时长）。测试可注入。
public protocol TrialTimeSource: Sendable {
    func wall() -> Date
    func uptime() -> TimeInterval
}
public struct SystemTrialTime: TrialTimeSource {
    public init() {}
    public func wall() -> Date { Date() }
    public func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

public enum EntitlementState: Equatable, Sendable {
    case notStarted                 // 还没翻译过任何一条
    case trial(remaining: TimeInterval)
    case expired
    case unlocked
}

public final class TrialCounter {
    private let store: TrialStore
    private let time: TrialTimeSource
    public var unlocked: Bool
    public init(store: TrialStore, unlocked: Bool = false, time: TrialTimeSource = SystemTrialTime()) {
        self.store = store; self.unlocked = unlocked; self.time = time
    }

    private func current() -> TrialRecord {
        var r = store.load()
        r.advance(wall: time.wall(), uptime: time.uptime())
        if r.startedAt != nil { store.save(r) }
        return r
    }

    public var state: EntitlementState {
        if unlocked { return .unlocked }
        let r = current()
        guard r.startedAt != nil else { return .notStarted }
        let left = TrialPolicy.duration - r.consumed
        return left > 0 ? .trial(remaining: left) : .expired
    }
    public var allowsFull: Bool { if case .expired = state { return false } else { return true } }

    /// 剩余小时（向上取整）；未开始/已买断为 nil；用完为 0。
    public var remainingHours: Int? {
        switch state {
        case .trial(let s): return Int((s / 3600).rounded(.up))
        case .expired: return 0
        default: return nil
        }
    }

    /// 每条完整消息成功时调用：第一次调用即开始 24 小时计时。买断后不计。
    public func recordCompleteTurn() {
        guard !unlocked else { return }
        var r = store.load()
        guard r.startedAt == nil else { return }
        r.startedAt = time.wall(); r.lastWall = time.wall(); r.lastUptime = time.uptime()
        store.save(r)
    }
}

/// 购买项（决策 D4，价格为提案，以 App Store Connect 为准）。
public enum PurchaseProduct: String, CaseIterable, Sendable {
    case tripPass = "pass.trip30"        // 单次旅行包：30 天非续期订阅（Non-Renewing Subscription）
    case lifetime = "unlock.lifetime"    // 终身买断：非消耗型
    public static let tripPassDays = 30
    public var proposedPriceCNY: Int { self == .tripPass ? 18 : 48 }
}

/// 购买记录 → 是否解锁、到期时间（非续期订阅需 App 自己算到期）。
public enum EntitlementResolver {
    public struct Txn: Equatable, Sendable {
        public var productID: String, purchaseDate: Date, revoked: Bool
        public init(productID: String, purchaseDate: Date, revoked: Bool = false) {
            self.productID = productID; self.purchaseDate = purchaseDate; self.revoked = revoked
        }
    }
    public enum Result: Equatable, Sendable { case none, lifetime, passUntil(Date) }
    public static func resolve(_ txns: [Txn], now: Date) -> Result {
        let valid = txns.filter { !$0.revoked }
        if valid.contains(where: { $0.productID == PurchaseProduct.lifetime.rawValue }) { return .lifetime }
        // 多次购买旅行包：从最早未过期的起算并顺延（第二次买在第一次到期前，则在其到期后再加 30 天）
        var until: Date?
        for t in valid.filter({ $0.productID == PurchaseProduct.tripPass.rawValue }).sorted(by: { $0.purchaseDate < $1.purchaseDate }) {
            let start = max(t.purchaseDate, until ?? t.purchaseDate)
            until = start.addingTimeInterval(TimeInterval(PurchaseProduct.tripPassDays) * 86400)
        }
        if let u = until, u > now { return .passUntil(u) }
        return .none
    }
}

/// 匿名计数开关（PRD v2 §15.2）：默认开启，可关闭；关闭时清空本机计数。
public final class MetricsSettings {
    private let defaults: UserDefaults
    private let key = "metrics.enabled"
    public private(set) var counters: [String: Int] = [:]
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var enabled: Bool {
        get { defaults.object(forKey: key) as? Bool ?? true }
        set { defaults.set(newValue, forKey: key); if !newValue { counters = [:] } }
    }
    public func increment(_ name: String) { if enabled { counters[name, default: 0] += 1 } }
}
