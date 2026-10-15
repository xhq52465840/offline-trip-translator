import Foundation
import TripCore

/// v4 金额卡片：对话里最醒目的元素。数字全部来自程序解析（AmountNormalizer / FXFormatter），不来自模型。
/// 附加条件（不含运费、每人…）来自关键词规则。
public struct MoneyCard: Equatable, Sendable {
    public let lines: [AmountChip]
    public let conditions: [String]
    public let fromPartner: Bool

    public var header: String { fromPartner ? L10n.t("对方报价") : L10n.t("我说的金额") }
    /// 第三行：口语读法 + 条件
    public func detail(for chip: AmountChip) -> String {
        ([chip.chinese] + conditions).joined(separator: " · ")
    }
    /// VoiceOver 整卡朗读：「对方报价 5万印尼盾，约 ¥19，不含运费」
    public var accessibilityText: String {
        let sep = L10n.isEnglish ? ", " : "，"
        let body = lines.map { ([$0.chinese] + [$0.cny].compactMap { $0 }).joined(separator: sep) }.joined(separator: sep)
        return ([header + " " + body] + conditions).joined(separator: sep)
    }

    public static func make(chips: [AmountChip], source: String, fromPartner: Bool) -> MoneyCard? {
        guard !chips.isEmpty else { return nil }
        return MoneyCard(lines: chips, conditions: conditions(in: source), fromPartner: fromPartner)
    }

    /// 关键词 → 条件（id / en / zh）。顺序固定，去重。
    static var rules: [(keys: [String], label: String)] { [
        (["belum termasuk ongkos", "belum termasuk ongkir", "blm termasuk ongkir", "belum sama ongkir", "not including delivery", "excluding delivery", "excl. shipping", "不含运费", "不含车费"], L10n.t("不含运费")), // i18n-ok
        (["sudah termasuk ongkir", "termasuk ongkos", "free ongkir", "gratis ongkir", "including delivery", "含运费", "包邮"], L10n.t("含运费")), // i18n-ok
        (["per orang", "/orang", "per person", "每人", "一人"], L10n.t("每人")), // i18n-ok
        (["per malam", "/malam", "per night", "每晚"], L10n.t("每晚")), // i18n-ok
        (["per jam", "/jam", "per hour", "每小时"], L10n.t("每小时")), // i18n-ok
        (["per kg", "/kg", "sekilo", "per kilo", "每公斤"], L10n.t("每公斤")), // i18n-ok
        (["belum termasuk pajak", "belum termasuk ppn", "plus tax", "+ tax", "不含税"], L10n.t("不含税")), // i18n-ok
        (["harga pas", "udah pas", "sudah pas", "fixed price", "实价", "不还价"], L10n.t("不还价")), // i18n-ok
    ] }
    public static func conditions(in source: String) -> [String] {
        let s = source.lowercased()
        var out: [String] = []
        for r in rules where r.keys.contains(where: { s.contains($0) }) {
            // 「含运费」规则会被「不含运费」误命中，先排除
            if r.label == L10n.t("含运费") && out.contains(L10n.t("不含运费")) { continue }
            let t = r.label
            if !out.contains(t) { out.append(t) }
        }
        return out
    }
}
