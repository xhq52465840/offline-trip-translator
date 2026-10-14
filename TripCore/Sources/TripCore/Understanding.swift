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
    /// 理解输出的目标语言（P3）：zh-Hans（默认，与改造前完全一致）或 en
    public var target: String
    public init(theirLanguageName: String = "印尼语", maxContextTurns: Int = 16, scene: String? = nil, target: String = "zh-Hans") {
        self.theirLanguageName = theirLanguageName; self.maxContextTurns = maxContextTurns; self.scene = scene; self.target = target
    }
    var isEnglish: Bool { target == "en" }

    /// 本地模型能输出「理解」的目标语言（P1：只有中文；P3 加英文）
    /// 本地模型能写提示词的目标语言（英文提示词保留，供评测工具 trip-prompt / eval_appfmt --target en 使用）
    public static func hasPrompt(target: String) -> Bool { target == "zh-Hans" || target == "en" }
    /// App 里实际启用本地理解的目标语言（计划 §5 按方向采用）。r7：s400 印→英 strict 97 < 基座 100 + 10，
    /// P9 的 mix3 s1000 也只有 107 且金额错 1 → 印→英不启用本地理解，走 Apple 翻译直译。将来某个检查点印→英达标后再加回 "en"。
    public static let localUnderstandingTargets: Set<String> = ["zh-Hans"]
    public static func supportsUnderstanding(target: String) -> Bool { localUnderstandingTargets.contains(target) }

    public var system: String {
        if isEnglish {
            return """
            You fix English translations in a travel conversation. The traveler reads English; the other person speaks \(theirLanguageName == "印尼语" ? "Indonesian" : theirLanguageName). Rewrite only the "Literal" line so it matches this conversation and what the original really means.
            Rules: translate slang and abbreviations correctly; use the given amount table for money and never convert amounts yourself; in haggling a bare number without unit may mean thousands of rupiah; make references explicit; no Indonesian words, no explanations; output one line of English only.
            """
        }
        return """
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
        if isEnglish { return userEnglish(context: context, source: source, literal: literal, glossary: glossary) }
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

extension PromptBuilder {
    /// 英文目标的 user 段（P3）：结构与中文版一一对应，金额写成 Rp 50,000
    func userEnglish(context: [ContextTurn], source: String, literal: String, glossary: [GlossaryHit]) -> String {
        let win = ContextWindow(maxTurns: maxContextTurns).build(context)
        var lines: [String] = []
        if let sc = scene { lines.append("Scene: \(sc)") }
        if let sum = win.summary { lines.append("Earlier: \(sum)") }
        lines += win.recent.map { t -> String in
            t.role == .them ? "Them: \(t.source) / English: \(t.zhDisplay ?? "")"
                            : (t.foreign.map { "Me: \(t.source) / They saw: \($0)" } ?? "Me: \(t.source)")
        }
        let amounts = AmountNormalizer.findAmounts(in: source).enumerated().map { "⟦N\($0.offset + 1)⟧\($0.element.original)=\($0.element.display(for: "en"))" }
        let words = glossary.prefix(8).map { "\($0.source) = \($0.zh)" }
        return """
        Conversation (in order):
        \(lines.isEmpty ? "(none)" : lines.joined(separator: "\n"))

        Amounts: \(amounts.isEmpty ? "none" : amounts.joined(separator: ", "))
        Words: \(words.isEmpty ? "none" : words.joined(separator: ", "))

        Original: \(source)
        Literal:
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

    public static func validate(output raw: String, literal: String, source: String, context: [ContextTurn], target: String = "zh-Hans") -> ValidationResult {
        var out = raw.components(separatedBy: .newlines).first ?? ""
        out = out.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'「」“”"))
        if out.isEmpty { return .rejected(.empty) }
        if target == "en" { return validateEnglish(out, literal: literal, source: source, context: context) }
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

extension OutputValidator {
    /// 英文输出校验（P3）：不能含汉字；不超过 60 个词；不能残留原文里的印尼语缩写；数字/金额必须来自原文。
    static let idSlang: Set<String> = ["rb", "jt", "udh", "udah", "gk", "gak", "nggak", "sy", "bs", "brp", "blm", "otw", "lg", "mnt", "bgt", "sdh", "pake", "aja", "kak", "dong", "yg"]
    static func validateEnglish(_ out: String, literal: String, source: String, context: [ContextTurn]) -> ValidationResult {
        let ns = out as NSString
        let full = NSRange(location: 0, length: ns.length)
        if hanRegex.numberOfMatches(in: out, range: full) > 0 { return .rejected(.foreignWord("汉字")) }
        let words = out.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init)
        if words.count > 60 { return .rejected(.tooLong) }
        if let w = words.first(where: { idSlang.contains($0) && $0 != "otw" }) { return .rejected(.foreignWord(w)) }
        let allowed = allowedValues(source: source, context: context)
        // 金额：英文写法（Rp 50,000 / 50k / 1.5 million / 2,600）；其余裸数字也必须出现在原文
        var covered: [NSRange] = []
        for m in AmountAnnotator.enOne.matches(in: out, range: full) {
            let s = ns.substring(with: m.range(at: 1))
            guard let v = AmountAnnotator.parseEnglish(s) else { continue }
            covered.append(m.range)
            let plain = Int(s.replacingOccurrences(of: ",", with: ""))
            if !allowed.contains(v) && !(plain != nil && sourceHasNumber(source, plain!)) { return .rejected(.amountMismatch(s)) }
        }
        for m in numRegex.matches(in: out, range: full) where !covered.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            let s = ns.substring(with: m.range)
            guard let d = Double(s) else { continue }
            if d == d.rounded(), allowed.contains(Int(d)) || sourceHasNumber(source, Int(d)) { continue }
            if source.contains(s) || source.contains(s.replacingOccurrences(of: ".", with: ",")) { continue }
            return .rejected(.amountMismatch(s))
        }
        let a = out.lowercased().filter { $0.isLetter || $0.isNumber }, b = literal.lowercased().filter { $0.isLetter || $0.isNumber }
        if a == b { return .unchanged }
        return .accepted(out)
    }
    static func sourceHasNumber(_ source: String, _ n: Int) -> Bool {
        let digits = source.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "")
        return digits.range(of: #"(?<!\d)\#(n)(?!\d)"#, options: .regularExpression) != nil
    }
}
