import Foundation
import TripCore

/// 界面文案（自检报告 v3 §2.2 B3、§2.4 T1），集中在这里便于审校与测试。
public enum Copy {
    public static let homeTitle = "开始对话"
    /// 首页副标题：突出差异（离线 + 懂上下文 + 金额可信）
    public static let homeSubtitle = "没网也能懂司机、商贩在说什么，金额不出错"
    /// 金额由代码换算的说明（演示页 / 购买页 / 金额胶囊长按提示）
    public static let amountTrust = "金额由程序按固定规则换算（如 50rb = 5万印尼盾），不靠 AI 猜；人民币按你设置的汇率估算。"
    public static func downloadAdvice(eta: String?) -> String {
        "建议出发前在家用 Wi‑Fi 下载" + (eta.map { "，\($0)" } ?? "") + "。可以锁屏，会在后台继续。"
    }
}

/// 下载剩余时间估算（自检报告 v3 U4）。未测到速度前按 5 MB/s（家用 Wi‑Fi 保守值）估。
public struct DownloadETA: Sendable {
    public static let assumedBytesPerSecond: Double = 5_000_000
    public var window: TimeInterval
    private var samples: [(t: Date, bytes: Int64)] = []
    public init(window: TimeInterval = 10) { self.window = window }

    public mutating func record(bytes: Int64, at t: Date) {
        if let last = samples.last, bytes < last.bytes { samples = [] }        // 切镜像/重下：重新测
        samples.append((t, bytes))
        samples.removeAll { t.timeIntervalSince($0.t) > window }
    }

    /// 实测速度（字节/秒）；样本跨度不足 2 秒返回 nil
    public var measuredBytesPerSecond: Double? {
        guard let f = samples.first, let l = samples.last, l.t.timeIntervalSince(f.t) >= 2 else { return nil }
        return Double(l.bytes - f.bytes) / l.t.timeIntervalSince(f.t)
    }

    public static func minutes(remaining: Int64, bytesPerSecond: Double) -> Int {
        guard bytesPerSecond > 0 else { return Int.max }
        return max(1, Int((Double(remaining) / bytesPerSecond / 60).rounded(.up)))
    }

    /// 「约 4 分钟」/「约 1 小时 10 分钟」；速度为 0 时「网速很慢，建议换个 Wi‑Fi」
    public func text(remaining: Int64) -> String {
        let measured = measuredBytesPerSecond
        let bps = measured ?? Self.assumedBytesPerSecond
        if bps < 1_000 { return "网速很慢，建议换个 Wi‑Fi" }
        let m = Self.minutes(remaining: remaining, bytesPerSecond: bps)
        let s = m >= 60 ? "约 \(m / 60) 小时\(m % 60 == 0 ? "" : " \(m % 60) 分钟")" : "约 \(m) 分钟"
        return measured == nil ? "Wi‑Fi 下\(s)" : "还要\(s)"
    }
}

/// 场景卡片按最近使用排序（自检报告 v3 X9）。未用过的保持默认顺序。
public struct RecentScenes: Codable, Equatable, Sendable {
    public private(set) var recent: [Scenario] = []
    public var maxCount = 6
    public init(recent: [Scenario] = []) { self.recent = recent }
    public mutating func use(_ s: Scenario) {
        recent.removeAll { $0 == s }; recent.insert(s, at: 0)
        if recent.count > maxCount { recent.removeLast(recent.count - maxCount) }
    }
    public func ordered(_ all: [Scenario] = Scenario.allCases) -> [Scenario] {
        recent.filter(all.contains) + all.filter { !recent.contains($0) }
    }
}

/// 复制后的提示（自检报告 v3 §1.1）：iOS 不能自动切回上一个 App，只能提示。
public enum CopyHint {
    public static func text(scene: Scenario?) -> String {
        switch scene {
        case .ride: return "已复制，回到 Grab / Gojek 聊天里粘贴发送"
        case .delivery: return "已复制，回到外卖 App 的骑手聊天里粘贴"
        default: return "已复制，可以粘贴到聊天里发送"
        }
    }
}

/// 出示页的金额原文行（自检报告 v3 X8）：让对方看到他熟悉的写法「Rp 50.000」。
public enum PresentContent {
    public static func amountLine(foreign: String, source: String) -> String? {
        let chips = Money.chips(in: foreign, rate: nil)
        let list = (chips.isEmpty ? Money.chips(in: source, rate: nil) : chips).map(\.rupiah)
        return list.isEmpty ? nil : list.joined(separator: " · ")
    }
}
