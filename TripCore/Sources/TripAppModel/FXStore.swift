import Foundation
import TripCore

/// 当前换算上下文：汇率 + 目标币种（PRD v2 §7.9）。
public struct FXContext: Equatable, Sendable {
    public var rates: FXRates
    public var currency: TargetCurrency
    public init(rates: FXRates, currency: TargetCurrency) { self.rates = rates; self.currency = currency }

    public static let staleDays = 30
    /// 汇率日期距今天数（日期无法解析时按很旧处理）
    public func ageDays(now: Date) -> Int {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: rates.date) else { return Int.max }
        return max(0, Int(now.timeIntervalSince(d) / 86_400))
    }
    /// 汇率说明行：「汇率 2026-10-12（ECB）」；超过 30 天加警告
    public func caption(now: Date) -> String {
        let base = L10n.f("汇率 %@，换算为约值", rates.date)
        guard ageDays(now: now) > Self.staleDays else { return base }
        return L10n.f("⚠️ 汇率已超过 %@ 天（%@），联网后自动更新", String(Self.staleDays), rates.date)
    }
    public func isStale(now: Date) -> Bool { ageDays(now: now) > Self.staleDays }
}

/// 汇率存储与在线刷新（只在有网时；不上传任何用户数据，只 GET 公共汇率接口）。
public final class FXStore {
    private let defaults: UserDefaults
    private let key = "fx.rates.v1", attemptKey = "fx.lastAttempt"
    /// 两次尝试最少间隔（启动 / 回前台时检查）
    public static let minInterval: TimeInterval = 6 * 3600
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// 已存的在线汇率（合理且不比内置旧）否则内置值
    public var current: FXRates {
        guard let d = defaults.data(forKey: key), let r = try? JSONDecoder().decode(FXRates.self, from: d),
              FXRates.isSane(r), r.date >= FXRates.bundled.date else { return .bundled }
        return r
    }

    public func shouldRefresh(now: Date, online: Bool) -> Bool {
        guard online else { return false }
        let last = defaults.object(forKey: attemptKey) as? Date
        return last.map { now.timeIntervalSince($0) >= Self.minInterval } ?? true
    }

    public enum RefreshResult: Equatable { case updated(FXRates), rejected, failed, skipped }

    /// fetch：App 用 URLSession 实现；测试注入假数据。超过 30% 偏差的结果被拒绝，继续用旧值。
    public func refresh(now: Date, online: Bool, fetch: (URL) async throws -> Data) async -> RefreshResult {
        guard shouldRefresh(now: now, online: online) else { return .skipped }
        defaults.set(now, forKey: attemptKey)
        guard let data = try? await fetch(FXRates.refreshURL) else { return .failed }
        guard let r = FXRates.parseFrankfurter(data), FXRates.isSane(r) else { return .rejected }
        defaults.set(try? JSONEncoder().encode(r), forKey: key)
        return .updated(r)
    }
}
