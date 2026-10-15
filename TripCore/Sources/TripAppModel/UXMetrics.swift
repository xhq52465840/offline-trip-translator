import Foundation

/// v4 成功指标（docs/交互改版方案_v4.md §7）：只在本机计数，不上传。用户可在「设置 → 使用统计」查看 / 复制。
public final class UXMetrics {
    public enum Event: String, CaseIterable, Sendable {
        case voiceTurn, quickReply, wrongSpeaker, faceToFace, starterTap
    }
    private let d: UserDefaults
    private let prefix = "uxm."
    public init(defaults: UserDefaults = .standard) { d = defaults }

    public func count(_ e: Event) -> Int { d.integer(forKey: prefix + e.rawValue) }
    public func record(_ e: Event) { d.set(count(e) + 1, forKey: prefix + e.rawValue) }

    public var firstLaunchAt: Date? { d.object(forKey: prefix + "firstLaunch") as? Date }
    public var firstTranslationAt: Date? { d.object(forKey: prefix + "firstTranslation") as? Date }
    public func markFirstLaunch(_ t: Date) { if firstLaunchAt == nil { d.set(t, forKey: prefix + "firstLaunch") } }
    public func markFirstTranslation(_ t: Date) { if firstLaunchAt != nil && firstTranslationAt == nil { d.set(t, forKey: prefix + "firstTranslation") } }

    /// 首次打开 → 第一次翻译的秒数（目标中位数 < 30 秒）
    public var secondsToFirstTranslation: Int? {
        guard let a = firstLaunchAt, let b = firstTranslationAt else { return nil }
        return max(0, Int(b.timeIntervalSince(a).rounded()))
    }
    /// 「说错人了」纠正率 = 纠正次数 / 语音轮数（目标 < 10%）
    public var wrongSpeakerRate: Double? {
        let v = count(.voiceTurn); return v == 0 ? nil : Double(count(.wrongSpeaker)) / Double(v)
    }
    /// 可复制的纯文本摘要（TestFlight 反馈用）
    public var summary: String {
        var lines = Event.allCases.map { "\($0.rawValue)=\(count($0))" }
        lines.append("secondsToFirstTranslation=\(secondsToFirstTranslation.map(String.init) ?? "-")")
        lines.append("wrongSpeakerRate=\(wrongSpeakerRate.map { String(format: "%.2f", $0) } ?? "-")")
        return lines.joined(separator: "\n")
    }
}

public extension ContextReplies {
    /// 空对话时的三句大号示例（点一下就发送）
    static var starters: [Phrase] {
        [Phrase("多少钱？", id: "Berapa harganya?", en: "How much is it?"), // i18n-ok
         Phrase("请带我去这个地址", id: "Tolong antar saya ke alamat ini", en: "Please take me to this address"), // i18n-ok
         tooExpensive]
    }
}
