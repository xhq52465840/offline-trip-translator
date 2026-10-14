import Foundation

public enum Role: String, Codable, Sendable { case them, me }

public struct ContextTurn: Equatable, Sendable {
    public var role: Role
    public var source: String
    public var zhDisplay: String?
    /// 我的话翻成对方语言后的文本（多轮上下文里两种语言都给模型看）
    public var foreign: String?
    public init(role: Role, source: String, zhDisplay: String? = nil, foreign: String? = nil) {
        self.role = role; self.source = source; self.zhDisplay = zhDisplay; self.foreign = foreign
    }
}

public struct GlossaryHit: Equatable, Sendable {
    public var source: String, zh: String
    public init(source: String, zh: String) { self.source = source; self.zh = zh }
}

/// 提示词构建（技术设计 v2 §8.2）。
public struct PromptBuilder: Sendable {
    public var theirLanguageName: String
    public var maxContextTurns: Int
    /// 场景（打车 / 砍价 / 点餐 / 酒店 / 问价），写进上下文帮助消歧
    public var scene: String?
    public init(theirLanguageName: String = "印尼语", maxContextTurns: Int = 16, scene: String? = nil) {
        self.theirLanguageName = theirLanguageName; self.maxContextTurns = maxContextTurns; self.scene = scene
    }

    /// 本地模型能输出「理解」的目标语言（P1：只有中文；P3 加英文）
    public static func supportsUnderstanding(target: String) -> Bool { target == "zh-Hans" }

    public var system: String {
        """
        你是旅行对话的中文译文修正器。游客是中国人，对方说\(theirLanguageName)。只修改「字面」这句中文，让它符合这场对话和原文真实意思。
        规则：缩写俚语译对；金额用给出的换算表，不要自己换算；讲价上下文里没有单位的数字可能是「千」，写成「万」；把指代说清楚；不要写外语单词，不要解释；只输出一行中文。
        """
    }

    /// 超长时保留最早 1 条 + 最近的（技术设计 1.1 §8.3 沿用）。
    public func trimmed(_ ctx: [ContextTurn]) -> [ContextTurn] {
        guard ctx.count > maxContextTurns, maxContextTurns >= 2 else { return ctx }
        return [ctx[0]] + ctx.suffix(maxContextTurns - 1)
    }

    public func user(context: [ContextTurn], source: String, literal: String, glossary: [GlossaryHit]) -> String {
        let win = ContextWindow(maxTurns: maxContextTurns).build(context)
        var lines: [String] = []
        if let sc = scene { lines.append("场景：\(sc)") }
        if let sum = win.summary { lines.append("前情摘要：\(sum)") }
        lines += win.recent.map { t -> String in
            t.role == .them ? "对方：\(t.source) ／ 中文：\(t.zhDisplay ?? "")"
                            : (t.foreign.map { "我：\(t.source) ／ 对方看到：\($0)" } ?? "我：\(t.source)")
        }
        let amounts = AmountNormalizer.findAmounts(in: source).enumerated().map { "⟦N\($0.offset + 1)⟧\($0.element.original)=\($0.element.display)" }
        let words = glossary.prefix(8).map { "\($0.source) = \($0.zh)" }
        return """
        这场对话（时间顺序）：
        \(lines.isEmpty ? "（无）" : lines.joined(separator: "\n"))

        金额：\(amounts.isEmpty ? "无" : amounts.joined(separator: ", "))
        词：\(words.isEmpty ? "无" : words.joined(separator: ", "))

        对方原文：\(source)
        字面：
        \(literal)
        """
    }
}

public enum ValidationResult: Equatable, Sendable {
    case accepted(String)
    case unchanged
    case rejected(Reason)
    public enum Reason: Equatable, Sendable { case empty, tooLong, foreignWord(String), amountMismatch(String) }
}

/// 输出校验（技术设计 v2 §5.3、§8.2）。
public enum OutputValidator {
    static let hanRegex = try! NSRegularExpression(pattern: #"\p{Han}"#)
    static let latinRegex = try! NSRegularExpression(pattern: #"[A-Za-z]{4,}"#)
    static let wanRegex = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*万"#)
    static let numRegex = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#)

    public static func normalize(_ s: String) -> String {
        s.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.symbols.contains($0) }
            .map(String.init).joined()
    }

    /// 允许出现的金额数值集合。
    public static func allowedValues(source: String, context: [ContextTurn]) -> Set<Int> {
        var set = Set(AmountNormalizer.findAmounts(in: source).flatMap(\.values))
        let hasMoneyContext = !set.isEmpty || context.contains { !AmountNormalizer.findAmounts(in: $0.source).isEmpty }
        for n in AmountNormalizer.bareNumbers(in: source) {
            set.insert(n)
            if hasMoneyContext { set.insert(n * 1_000) }
        }
        return set
    }

    public static func validate(output raw: String, literal: String, source: String, context: [ContextTurn]) -> ValidationResult {
        var out = raw.components(separatedBy: .newlines).first ?? ""
        out = out.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'「」“”"))
        if out.isEmpty { return .rejected(.empty) }
        let ns = out as NSString
        let full = NSRange(location: 0, length: ns.length)
        if hanRegex.numberOfMatches(in: out, range: full) > 80 { return .rejected(.tooLong) }
        for m in latinRegex.matches(in: out, range: full) {
            let w = ns.substring(with: m.range)
            if source.range(of: w, options: .caseInsensitive) == nil { return .rejected(.foreignWord(w)) }
        }
        // 金额交叉校验
        let allowed = allowedValues(source: source, context: context)
        var covered: [NSRange] = []
        for m in wanRegex.matches(in: out, range: full) {
            covered.append(m.range)
            let s = ns.substring(with: m.range).replacingOccurrences(of: " ", with: "")
            guard let v = ChineseAmountFormatter.parse(s), allowed.contains(v) else { return .rejected(.amountMismatch(s)) }
        }
        for m in numRegex.matches(in: out, range: full) where !covered.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            let s = ns.substring(with: m.range)
            guard let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { continue }
            let v = NSDecimalNumber(decimal: d).intValue
            if NSDecimalNumber(decimal: d).doubleValue != Double(v) || !allowed.contains(v) { return .rejected(.amountMismatch(s)) }
        }
        if normalize(out) == normalize(literal) { return .unchanged }
        return .accepted(out)
    }
}
