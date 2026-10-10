import Foundation

/// 多轮上下文窗口（技术设计 v2 §8.3，UX 改版）：整场对话都是上下文。
/// 超过 maxTurns 时：最近 maxTurns-1 条原样给模型，更早的压成一行「前情摘要」，
/// 摘要由代码确定性生成（首句 + 出现过的金额 + 条数），不额外调用模型，不增加时延。
public struct ContextWindow: Sendable {
    public var maxTurns: Int
    public var maxSummaryChars: Int
    public init(maxTurns: Int = 16, maxSummaryChars: Int = 120) { self.maxTurns = max(2, maxTurns); self.maxSummaryChars = maxSummaryChars }

    public struct Result: Equatable, Sendable {
        public var summary: String?
        public var recent: [ContextTurn]
    }

    public func build(_ turns: [ContextTurn]) -> Result {
        guard turns.count > maxTurns else { return Result(summary: nil, recent: turns) }
        let keep = maxTurns - 1
        let older = Array(turns.dropLast(keep))
        let recent = Array(turns.suffix(keep))
        var parts: [String] = []
        if let first = older.first {
            let zh = first.role == .them ? (first.zhDisplay ?? first.source) : first.source
            parts.append("开头\(first.role == .them ? "对方" : "我")说「\(zh)」")
        }
        var seen: [String] = []
        for t in older {
            let text = t.role == .them ? t.source : (t.foreign ?? "") + " " + t.source
            for a in AmountNormalizer.findAmounts(in: text) where !seen.contains(a.display) { seen.append(a.display) }
            for w in Self.zhAmounts(t.role == .them ? (t.zhDisplay ?? "") : t.source) where !seen.contains(w) { seen.append(w) }
        }
        if !seen.isEmpty { parts.append("提到过的金额：" + seen.suffix(6).joined(separator: "、")) }
        parts.append("共省略 \(older.count) 条")
        var s = parts.joined(separator: "；")
        if s.count > maxSummaryChars { s = String(s.prefix(maxSummaryChars - 1)) + "…" }
        return Result(summary: s, recent: recent)
    }

    static func zhAmounts(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?万"#)
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }
}
