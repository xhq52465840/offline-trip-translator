import Foundation
import TripCore

/// 金额胶囊：「Rp 50.000 ≈ ¥21.7」。汇率离线、可在设置里手动改（不联网取汇率）。
public struct AmountChip: Equatable, Sendable, Identifiable {
    public var id: String { rupiah }
    public let idr: Int
    public let rupiah: String      // Rp 50.000
    public let chinese: String     // 5万印尼盾
    public let cny: String?        // ≈ ¥21.7
}

public struct ExchangeRate: Equatable, Codable, Sendable {
    /// 1 人民币 = idrPerCny 印尼盾
    public var idrPerCny: Double
    public var updatedNote: String
    public static let `default` = ExchangeRate(idrPerCny: 2300, updatedNote: "示例汇率，请在设置里按实际修改")
    public init(idrPerCny: Double, updatedNote: String) { self.idrPerCny = idrPerCny; self.updatedNote = updatedNote }
}

public enum Money {
    public static func rupiah(_ v: Int) -> String {
        let s = String(v)
        var out = ""
        for (i, ch) in s.reversed().enumerated() { if i > 0 && i % 3 == 0 { out.append(".") }; out.append(ch) }
        return "Rp " + String(out.reversed())
    }

    public static func cny(_ idr: Int, rate: ExchangeRate?) -> String? {
        guard let r = rate, r.idrPerCny > 0 else { return nil }
        let y = Double(idr) / r.idrPerCny
        if y < 100 { return String(format: "≈ ¥%.1f", y) }
        return "≈ ¥\(Int(y.rounded()))"
    }

    public static func chip(_ idr: Int, rate: ExchangeRate?) -> AmountChip {
        AmountChip(idr: idr, rupiah: rupiah(idr), chinese: ChineseAmountFormatter.format(idr) + "印尼盾", cny: cny(idr, rate: rate))
    }

    /// 从一句原文（印尼语/英语）里找出金额并生成胶囊；去重，保持出现顺序。
    public static func chips(in text: String, rate: ExchangeRate?) -> [AmountChip] {
        var seen = Set<Int>(); var out: [AmountChip] = []
        for m in AmountNormalizer.findAmounts(in: text) {
            for v in m.values where v >= 100 && !seen.contains(v) { seen.insert(v); out.append(chip(v, rate: rate)) }
        }
        return out
    }
}
