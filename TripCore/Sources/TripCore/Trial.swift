import Foundation
#if canImport(Security)
import Security
#endif

public enum TrialPolicy {
    public static let freeCompleteTurns = 30
    public static let bannerThreshold = 5
}

public protocol TrialStore: AnyObject {
    func loadUsed() -> Int
    func saveUsed(_ n: Int)
}

public final class InMemoryTrialStore: TrialStore {
    private var used: Int
    public init(used: Int = 0) { self.used = used }
    public func loadUsed() -> Int { used }
    public func saveUsed(_ n: Int) { used = n }
}

#if canImport(Security)
/// 钥匙串存储（技术设计 v2 §15），仅本机，首次解锁后可读。
public final class KeychainTrialStore: TrialStore {
    private let service: String, account: String
    public init(service: String = "app.tripunderstand", account: String = "trial.used") { self.service = service; self.account = account }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    public func loadUsed() -> Int {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let d = item as? Data, let s = String(data: d, encoding: .utf8) else { return 0 }
        return Int(s) ?? 0
    }
    public func saveUsed(_ n: Int) {
        let data = Data(String(n).utf8)
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

public enum EntitlementState: Equatable, Sendable { case trial(remaining: Int), unlocked }

public final class TrialCounter {
    private let store: TrialStore
    public var unlocked: Bool
    public let limit: Int
    public init(store: TrialStore, unlocked: Bool = false, limit: Int = TrialPolicy.freeCompleteTurns) {
        self.store = store; self.unlocked = unlocked; self.limit = limit
    }
    public var used: Int { store.loadUsed() }
    public var state: EntitlementState { unlocked ? .unlocked : .trial(remaining: max(0, limit - used)) }
    public var allowsFull: Bool { unlocked || used < limit }
    /// 横幅：nil 不显示；0 为用尽。
    public var bannerRemaining: Int? {
        guard case .trial(let r) = state, r <= TrialPolicy.bannerThreshold else { return nil }
        return r
    }
    /// 只在完整消息成功时调用。买断后不计数。
    public func recordCompleteTurn() {
        guard !unlocked, used < limit else { return }
        store.saveUsed(used + 1)
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
