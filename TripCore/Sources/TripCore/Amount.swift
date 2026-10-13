import Foundation

/// 一处被识别的金额。
public struct AmountMatch: Equatable, Sendable {
    public var original: String      // 原文片段，如 "50rb"
    public var value: Int            // 换算后的数值，如 50000
    public var display: String       // 中文显示，如 "5万"
    public var range: Range<String.Index>
    /// 区间上限（如 "30-40 ribu" 的 40000）；单个金额为 nil。value 为下限。
    public var upperValue: Int?
    public init(original: String, value: Int, display: String, range: Range<String.Index>, upperValue: Int? = nil) {
        self.original = original; self.value = value; self.display = display; self.range = range; self.upperValue = upperValue
    }
    /// 涉及的所有数值（区间为上下限）
    public var values: [Int] { upperValue.map { [value, $0] } ?? [value] }
}

/// 中文金额格式（技术设计 v2 §5.1）。
public enum ChineseAmountFormatter {
    public static func format(_ value: Int) -> String {
        if value < 10_000 { return String(value) }
        if value % 10_000 == 0 { return "\(value / 10_000)万" }
        // 精确保留小数并去掉末尾 0，如 175000 -> 17.5万
        var frac = value % 10_000
        var digits = 4
        while frac % 10 == 0 { frac /= 10; digits -= 1 }
        let fracStr = String(frac)
        let padded = String(repeating: "0", count: max(0, digits - fracStr.count)) + fracStr
        return "\(value / 10_000).\(padded)万"
    }

    /// 把中文金额字符串解析回数值，如 "17.5万" -> 175000，"9500" -> 9500。
    public static func parse(_ s: String) -> Int? {
        if s.hasSuffix("万") {
            guard let d = Decimal(string: String(s.dropLast()), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            return NSDecimalNumber(decimal: d * 10_000).intValue
        }
        return Int(s)
    }
}

/// 印尼语 / 英语金额俗写解析（技术设计 v2 §5.1、§5.2）。
public enum AmountNormalizer {
    // 1) 带单位：数字可以是千分位（50.000）或小数（1,5 / 2.5）
    private static let unitPattern = #"(?<![\w.,])(\d{1,3}(?:\.\d{3})+|\d+(?:[.,]\d+)?)\s*(ribu|rbu|rb|juta|jt|k)(?![A-Za-z])"#
    // 2) 不带单位的千分位整数：50.000、1.500.000
    private static let thousandsPattern = #"(?<![\w.,])(\d{1,3}(?:\.\d{3})+)(?![\d.,]*\d)"#

    // 0) 区间：30-40 ribu / 6-7rb / 30rb-40rb / 30 s/d 40 ribu / Rp 30.000–40.000（单位共享，取后一个单位）
    private static let num = #"(\d{1,3}(?:\.\d{3})+|\d+(?:[.,]\d+)?)"#
    private static let unitAlt = #"(ribu|rbu|rb|juta|jt|k)"#
    private static let sep = #"\s*(?:-|–|—|~|s/d|s\.d\.?|sampai|hingga|to)\s*(?:Rp\.?\s*)?"#
    private static let rangeUnitRegex = try! NSRegularExpression(
        pattern: #"(?<![\w.,])"# + num + #"\s*"# + unitAlt + "?" + sep + num + #"\s*"# + unitAlt + #"(?![A-Za-z])"#, options: [.caseInsensitive])
    private static let rangeGroupedRegex = try! NSRegularExpression(
        pattern: #"(?<![\w.,])(\d{1,3}(?:\.\d{3})+)"# + sep + #"(\d{1,3}(?:\.\d{3})+)(?![\d.,]*\d)"#, options: [.caseInsensitive])

    /// 区间中文写法：3万–4万
    public static func rangeDisplay(_ lo: Int, _ hi: Int) -> String { "\(ChineseAmountFormatter.format(lo))–\(ChineseAmountFormatter.format(hi))" }

    // 3) 带货币前缀的整数：Rp 5000 / Rp5000 / IDR 50,000（英文逗号千分位，仅在有 Rp/IDR 前缀时认）
    private static let prefixedRegex = try! NSRegularExpression(
        pattern: #"(?:Rp\.?|IDR)\s*(\d{1,3}(?:,\d{3})+|\d{1,3}(?:\.\d{3})+|\d{3,})(?![\d.,]*\d)(?!\s*(?:ribu|rbu|rb|juta|jt|k)(?![A-Za-z]))"#, options: [.caseInsensitive])

    private static let unitRegex = try! NSRegularExpression(pattern: unitPattern, options: [.caseInsensitive])
    private static let thousandsRegex = try! NSRegularExpression(pattern: thousandsPattern, options: [])

    static func multiplier(_ unit: String) -> Int {
        switch unit.lowercased() {
        case "rb", "rbu", "ribu", "k": return 1_000
        case "jt", "juta": return 1_000_000
        default: return 1
        }
    }

    /// 数字部分 -> Decimal。含「.ddd」分组的视为千分位；否则逗号或点是小数点。
    static func number(_ s: String) -> Decimal? {
        let isGrouped = s.range(of: #"^\d{1,3}(\.\d{3})+$"#, options: .regularExpression) != nil
        let cleaned = isGrouped ? s.replacingOccurrences(of: ".", with: "") : s.replacingOccurrences(of: ",", with: ".")
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func findAmounts(in text: String) -> [AmountMatch] {
        let ns = text as NSString
        var results: [AmountMatch] = []
        var taken: [NSRange] = []
        let all = NSRange(location: 0, length: ns.length)
        func overlaps(_ r: NSRange) -> Bool { taken.contains { NSIntersectionRange($0, r).length > 0 } }
        func addRange(_ m: NSTextCheckingResult, lo: Decimal, hi: Decimal) {
            let l = NSDecimalNumber(decimal: lo).intValue, h = NSDecimalNumber(decimal: hi).intValue
            guard l > 0, l < h, let r = Range(m.range, in: text) else { return }
            results.append(AmountMatch(original: ns.substring(with: m.range), value: l, display: rangeDisplay(l, h), range: r, upperValue: h))
            taken.append(m.range)
        }
        for m in rangeUnitRegex.matches(in: text, range: all) {
            let u2 = ns.substring(with: m.range(at: 4))
            let u1 = m.range(at: 2).location == NSNotFound ? u2 : ns.substring(with: m.range(at: 2))
            guard let a = number(ns.substring(with: m.range(at: 1))), let b = number(ns.substring(with: m.range(at: 3))) else { continue }
            addRange(m, lo: a * Decimal(multiplier(u1)), hi: b * Decimal(multiplier(u2)))
        }
        for m in rangeGroupedRegex.matches(in: text, range: all) where !overlaps(m.range) {
            guard let a = number(ns.substring(with: m.range(at: 1))), let b = number(ns.substring(with: m.range(at: 2))) else { continue }
            addRange(m, lo: a, hi: b)
        }
        for m in unitRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) where !overlaps(m.range) {
            let numStr = ns.substring(with: m.range(at: 1))
            let unit = ns.substring(with: m.range(at: 2))
            guard let n = number(numStr) else { continue }
            let v = NSDecimalNumber(decimal: n * Decimal(multiplier(unit))).intValue
            guard let r = Range(m.range, in: text) else { continue }
            results.append(AmountMatch(original: ns.substring(with: m.range), value: v, display: ChineseAmountFormatter.format(v), range: r))
            taken.append(m.range)
        }
        for m in prefixedRegex.matches(in: text, range: all) where !overlaps(m.range(at: 1)) {
            let numStr = ns.substring(with: m.range(at: 1))
            guard let v = Int(numStr.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")), let r = Range(m.range(at: 1), in: text) else { continue }
            results.append(AmountMatch(original: numStr, value: v, display: ChineseAmountFormatter.format(v), range: r))
            taken.append(m.range(at: 1))
        }
        for m in thousandsRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
            let numStr = ns.substring(with: m.range(at: 1))
            guard let n = number(numStr), let r = Range(m.range, in: text) else { continue }
            let v = NSDecimalNumber(decimal: n).intValue
            results.append(AmountMatch(original: numStr, value: v, display: ChineseAmountFormatter.format(v), range: r))
        }
        return results.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// 占位化：把金额换成 ⟦N1⟧…，返回带占位文本和占位表。
    public static func placeholderize(_ text: String) -> (text: String, table: [String: AmountMatch]) {
        let matches = findAmounts(in: text)
        var out = text
        var table: [String: AmountMatch] = [:]
        for (i, m) in matches.enumerated().reversed() {
            let key = "⟦N\(i + 1)⟧"
            table[key] = m
            out.replaceSubrange(m.range, with: key)
        }
        return (out, table)
    }

    /// 回填：把译文中的占位换成中文金额。占位丢失或重复时返回 nil（调用方回退原文翻译）。
    public static func restore(_ translated: String, table: [String: AmountMatch]) -> String? {
        var out = translated
        for (key, m) in table {
            let count = out.components(separatedBy: key).count - 1
            guard count == 1 else { return nil }
            out = out.replacingOccurrences(of: key, with: m.display)
        }
        return out
    }

    /// 原文中所有裸数字（不含已识别金额），用于校验。
    public static func bareNumbers(in text: String) -> [Int] {
        var t = text
        for m in findAmounts(in: text).reversed() { t.replaceSubrange(m.range, with: " ") }
        let re = try! NSRegularExpression(pattern: #"\d+"#)
        let ns = t as NSString
        return re.matches(in: t, range: NSRange(location: 0, length: ns.length)).compactMap { Int(ns.substring(with: $0.range)) }
    }
}
