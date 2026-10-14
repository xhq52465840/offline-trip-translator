import Foundation

/// 换算目标币种（PRD v2 §7.9）：中文用户 → 人民币；英文（及其他）界面 → 美元。
public enum TargetCurrency: String, Codable, Sendable, CaseIterable {
    case cny, usd
    /// idr：印尼语用户，不给印尼盾加注（反向把 ¥/$ 换成 Rp）（P2）
    case idr
    /// 按语言选：zh* → 人民币；id/in* → 印尼盾（不加注）；其余 → 美元
    public static func forLocale(_ identifier: String) -> TargetCurrency {
        let l = identifier.lowercased()
        if l.hasPrefix("zh") { return .cny }
        if l.hasPrefix("id") || l.hasPrefix("in") { return .idr }
        return .usd
    }
    public var symbol: String { switch self { case .cny: return "¥"; case .usd: return "$"; case .idr: return "Rp " } }
}

/// 汇率表（以印尼盾计）。数量级永远来自代码解析出的整数印尼盾；汇率只影响小数点后的精度。
public struct FXRates: Codable, Equatable, Sendable {
    public var idrPerCNY: Double
    public var idrPerUSD: Double
    /// 汇率日期（yyyy-MM-dd），界面显示「汇率 2026-10-12」
    public var date: String
    public var source: String

    /// 内置默认汇率：ECB 参考汇率（经 Frankfurter API，api.frankfurter.dev），2026-10-12：
    /// 1 USD = 17920 IDR，1 USD = 6.6928 CNY → 1 CNY ≈ 2677.5 IDR。
    public static let bundled = FXRates(idrPerCNY: 17920.0 / 6.6928, idrPerUSD: 17920, date: "2026-10-12",
                                        source: "ECB reference rates via Frankfurter (api.frankfurter.dev)")
    /// 在线更新与内置值偏差超过这个比例即拒绝（防止接口错/单位错导致数量级错误）
    public static let maxDeviation = 0.30

    public init(idrPerCNY: Double, idrPerUSD: Double, date: String, source: String) {
        self.idrPerCNY = idrPerCNY; self.idrPerUSD = idrPerUSD; self.date = date; self.source = source
    }

    public func idrPer(_ c: TargetCurrency) -> Double { switch c { case .cny: return idrPerCNY; case .usd: return idrPerUSD; case .idr: return 1 } }

    /// 候选汇率是否可信：为正、有限、且与内置值相差不超过 30%。
    public static func isSane(_ cand: FXRates, reference: FXRates = .bundled) -> Bool {
        for c in [TargetCurrency.cny, .usd] {
            let v = cand.idrPer(c), r = reference.idrPer(c)
            guard v.isFinite, v > 0, abs(v - r) / r <= maxDeviation else { return false }
        }
        return true
    }

    /// 解析 Frankfurter 返回：{"base":"USD","date":"2026-10-12","rates":{"CNY":6.69,"IDR":17920}}
    public static func parseFrankfurter(_ data: Data) -> FXRates? {
        struct R: Decodable { let base: String; let date: String; let rates: [String: Double] }
        guard let r = try? JSONDecoder().decode(R.self, from: data), r.base == "USD",
              let idr = r.rates["IDR"], let cny = r.rates["CNY"], cny > 0 else { return nil }
        return FXRates(idrPerCNY: idr / cny, idrPerUSD: idr, date: r.date, source: "ECB via Frankfurter")
    }
    public static let refreshURL = URL(string: "https://api.frankfurter.dev/v1/latest?from=USD&symbols=IDR,CNY")!
}

/// 印尼盾 → 目标币种的格式化。只做除法，不做任何数量级推断。
public enum FXFormatter {
    /// 数值：≥100 取整；10–100 取整；<10 一位小数；<0.1 显示 "<0.1"
    public static func amount(_ idr: Int, to c: TargetCurrency, rates: FXRates) -> String {
        let v = Double(idr) / rates.idrPer(c)
        let s: String
        if v < 0.1 { s = "<0.1" }
        else if v < 10 { s = String(format: "%.1f", v) }
        else { s = grouped(Int(v.rounded())) }
        return c.symbol + s
    }
    public static func grouped(_ n: Int) -> String {
        let s = String(n); var out = ""
        for (i, ch) in s.reversed().enumerated() { if i > 0 && i % 3 == 0 { out.append(",") }; out.append(ch) }
        return String(out.reversed())
    }
    /// 「约 ¥45」/「≈ $5.6」；区间「约 ¥11–15」
    public static func approx(_ idr: Int, upper: Int? = nil, to c: TargetCurrency, rates: FXRates) -> String {
        let pre = c == .cny ? "约 " : "≈ "
        if c == .idr { return pre + "Rp " + RupiahFormatter.grouped(idr, sep: ".") }
        guard let u = upper else { return pre + amount(idr, to: c, rates: rates) }
        return pre + amount(idr, to: c, rates: rates) + "–" + String(amount(u, to: c, rates: rates).dropFirst())
    }
}

/// 在显示文本里给金额加换算注释（确定性，不经 LLM）。
public enum AmountAnnotator {
    /// 印尼语/英语原文：「Harganya Rp 100.000」→「Harganya Rp 100.000（约 ¥37）」
    public static func annotateSource(_ text: String, to c: TargetCurrency, rates: FXRates) -> String {
        guard c != .idr else { return text }
        var out = text
        for m in AmountNormalizer.findAmounts(in: text).reversed() where m.value >= 100 {
            out.insert(contentsOf: "（\(FXFormatter.approx(m.value, upper: m.upperValue, to: c, rates: rates))）", at: m.range.upperBound)
        }
        return out
    }

    private static let zhRange = try! NSRegularExpression(pattern: #"(\d+(?:\.\d+)?万?)\s*(?:–|-|—|到|至|~)\s*(\d+(?:\.\d+)?万?)"#)
    private static let zhOne = try! NSRegularExpression(pattern: #"(?<![\d.])(\d+(?:\.\d+)?万|\d{3,})(?![\d.万])"#)

    /// 中文显示行（模型输出或字面翻译）：只给**原文里确实存在**的金额加注释——数值与 `allowed`（来自代码解析的原文金额）完全相等才加。
    /// 模型写错的数量级（如原文 5万写成 50万）不会被加注释，也就不会把错误「坐实」。
    public static func annotateChinese(_ text: String, allowed: Set<Int>, to c: TargetCurrency, rates: FXRates) -> String {
        guard !allowed.isEmpty, c != .idr else { return text }
        var out = text
        var done: [NSRange] = []
        let ns = text as NSString
        var inserts: [(Int, String)] = []
        for m in zhRange.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let a = ns.substring(with: m.range(at: 1)), b = ns.substring(with: m.range(at: 2))
            // 区间共享单位：「3–4万」中 3 也是万
            let aFull = (!a.hasSuffix("万") && b.hasSuffix("万")) ? a + "万" : a
            guard let lo = ChineseAmountFormatter.parse(aFull), let hi = ChineseAmountFormatter.parse(b),
                  lo < hi, allowed.contains(lo), allowed.contains(hi) else { continue }
            inserts.append((m.range.location + m.range.length, "（\(FXFormatter.approx(lo, upper: hi, to: c, rates: rates))）"))
            done.append(m.range)
        }
        for m in zhOne.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if done.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
            guard let v = ChineseAmountFormatter.parse(ns.substring(with: m.range(at: 1))), allowed.contains(v), v >= 100 else { continue }
            inserts.append((m.range.location + m.range.length, "（\(FXFormatter.approx(v, to: c, rates: rates))）"))
        }
        for (loc, s) in inserts.sorted(by: { $0.0 > $1.0 }) {
            let idx = String.Index(utf16Offset: loc, in: out)
            out.insert(contentsOf: s, at: idx)
        }
        return out
    }

    // 英文显示行里的金额：Rp 100,000 / 100,000 / 100k / 1.5 million / 30,000–40,000
    private static let enOne = try! NSRegularExpression(
        pattern: #"(?<![\w.,])(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?\s*(?:k|thousand|million|mil)|\d{3,})(?![\w,]*\d)(?![A-Za-z])"#, options: [.caseInsensitive])
    static func parseEnglish(_ s: String) -> Int? {
        let t = s.lowercased().replacingOccurrences(of: " ", with: "")
        for (suf, mul) in [("thousand", 1_000.0), ("million", 1_000_000.0), ("mil", 1_000_000.0), ("k", 1_000.0)] where t.hasSuffix(suf) {
            guard let d = Double(t.dropLast(suf.count)) else { return nil }
            return Int((d * mul).rounded())
        }
        return Int(t.replacingOccurrences(of: ",", with: ""))
    }

    /// 英文显示行（P2）：规则同 annotateChinese——只给与原文解析值完全相等的数字加注，区间只在两端都相等时加。
    public static func annotateEnglish(_ text: String, allowed: Set<Int>, to c: TargetCurrency, rates: FXRates) -> String {
        guard !allowed.isEmpty, c != .idr else { return text }
        let ns = text as NSString
        let ms = enOne.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var inserts: [(Int, String)] = []
        // 插入点越过紧跟的币种词：「50 thousand rupiah (≈ $2.8)」
        let suffix = try! NSRegularExpression(pattern: #"^\s*(?:rupiahs?|IDR)(?![A-Za-z])"#, options: [.caseInsensitive])
        func end(_ r: NSRange) -> Int {
            let rest = NSRange(location: r.upperBound, length: ns.length - r.upperBound)
            if let m = suffix.firstMatch(in: text, range: rest) { return m.range.upperBound }
            return r.upperBound
        }
        var i = 0
        while i < ms.count {
            let m = ms[i]
            guard let v = parseEnglish(ns.substring(with: m.range(at: 1))) else { i += 1; continue }
            // 区间：两个匹配之间只有 - – — to
            if i + 1 < ms.count {
                let gapR = NSRange(location: m.range.upperBound, length: ms[i + 1].range.location - m.range.upperBound)
                let gap = ns.substring(with: gapR).trimmingCharacters(in: .whitespaces).lowercased()
                if ["-", "–", "—", "to"].contains(gap), let hi = parseEnglish(ns.substring(with: ms[i + 1].range(at: 1))) {
                    if allowed.contains(v), allowed.contains(hi), v < hi {
                        inserts.append((end(ms[i + 1].range), " (\(FXFormatter.approx(v, upper: hi, to: c, rates: rates)))"))
                    }
                    i += 2; continue
                }
            }
            if allowed.contains(v), v >= 100 { inserts.append((end(m.range), " (\(FXFormatter.approx(v, to: c, rates: rates)))")) }
            i += 1
        }
        var out = text
        for (loc, s) in inserts.sorted(by: { $0.0 > $1.0 }) { out.insert(contentsOf: s, at: String.Index(utf16Offset: loc, in: out)) }
        return out
    }

    /// 按查看者语言选择注释方式（P2）
    public static func annotateDisplay(_ text: String, lang: String, allowed: Set<Int>, to c: TargetCurrency, rates: FXRates) -> String {
        if lang.hasPrefix("zh") { return annotateChinese(text, allowed: allowed, to: c, rates: rates) }
        if lang == "en" { return annotateEnglish(text, allowed: allowed, to: c, rates: rates) }
        return text
    }

    /// 原文金额集合（含区间上下限）
    public static func allowedValues(source: String) -> Set<Int> {
        Set(AmountNormalizer.findAmounts(in: source).flatMap(\.values))
    }
}

/// 反方向（我说人民币）：「200块」「¥200」「200元」「200人民币」→ 印尼盾约值，用于我方气泡注释。
public enum CNYParser {
    private static let re = try! NSRegularExpression(pattern: #"(?:[¥￥]\s*(\d+(?:\.\d+)?)(万)?|(\d+(?:\.\d+)?)(万)?\s*(?:块钱|块|元|人民币|rmb|RMB))"#)
    public static func find(in text: String) -> [Double] {
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let g = m.range(at: 1).location != NSNotFound ? 1 : 3
            guard let d = Double(ns.substring(with: m.range(at: g))) else { return nil }
            return m.range(at: g + 1).location != NSNotFound ? d * 10_000 : d
        }
    }
    /// 「（约 Rp 535.000）」，四舍五入到千
    public static func idrNote(_ cny: Double, rates: FXRates) -> String {
        let idr = Int((cny * rates.idrPerCNY / 1000).rounded()) * 1000
        return "约 Rp " + String(String(max(idr, 1000)).reversed().enumerated().map { i, ch in (i > 0 && i % 3 == 0 ? "." : "") + String(ch) }.joined().reversed())
    }
}

/// 反方向（P2）：文本里的人民币 / 美元金额 → 约多少印尼盾。
public enum ForeignCashParser {
    private static let usd = try! NSRegularExpression(pattern: #"(?:(?:US)?\$\s*(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*(?:dollars?|bucks|USD)(?![A-Za-z]))"#, options: [.caseInsensitive])
    public static func findUSD(in text: String) -> [Double] {
        let ns = text as NSString
        return usd.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let g = m.range(at: 1).location != NSNotFound ? 1 : 2
            return Double(ns.substring(with: m.range(at: g)))
        }
    }
    /// 「¥200≈Rp 536.000」/「$20≈Rp 358,000」；英文用逗号分组，其余用点
    public static func notes(in text: String, lang: String, rates: FXRates) -> [String] {
        let sep: Character = lang == "en" ? "," : "."
        func rp(_ idr: Double) -> String { "Rp " + RupiahFormatter.grouped(max(1000, Int((idr / 1000).rounded()) * 1000), sep: sep) }
        func num(_ d: Double) -> String { d == d.rounded() ? FXFormatter.grouped(Int(d)) : String(d) }
        let c = CNYParser.find(in: text).map { "¥\(num($0))≈" + rp($0 * rates.idrPerCNY) }
        let u = findUSD(in: text).map { "$\(num($0))≈" + rp($0 * rates.idrPerUSD) }
        return c + u
    }
}
