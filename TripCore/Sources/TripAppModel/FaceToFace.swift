import Foundation
import TripCore

/// v4 面对面分屏的内容：上半屏（倒置）用对方语言显示最新一句 + 金额；下半屏用我的语言。
/// 金额只用程序解析出的数字。
public struct FaceToFaceContent: Equatable, Sendable {
    public let partnerLabel: String?     // 对方语言：「Dia bilang:」/「Saya:」
    public let partnerText: String?
    public let partnerAmounts: [String]  // 「Rp 40.000」
    public let myLabel: String?
    public let myText: String?
    public let lastMessageID: UUID?
    public let lastRole: Role?

    public static func make(messages: [Message], myLanguage: String, theirLanguage: String) -> FaceToFaceContent {
        guard let last = messages.last(where: { $0.status == .ready || ($0.role == .them && $0.status != .trialBlocked) }) else {
            return FaceToFaceContent(partnerLabel: nil, partnerText: nil, partnerAmounts: [], myLabel: nil, myText: nil, lastMessageID: nil, lastRole: nil)
        }
        let mine = last.role == .me
        let pText = mine ? (last.foreign ?? "") : last.source
        let amounts = Money.chips(in: mine ? (last.foreign ?? "") : last.source, rate: nil).map(\.rupiah)
        let mText = mine ? last.source : last.mainLine
        return FaceToFaceContent(partnerLabel: partnerLabel(mine: mine, lang: theirLanguage), partnerText: pText.isEmpty ? nil : pText,
                                 partnerAmounts: amounts,
                                 myLabel: mine ? L10n.t("我说：") : L10n.t("对方说："),
                                 myText: mText, lastMessageID: last.id, lastRole: last.role)
    }

    /// 上半屏标签用对方的语言（与界面语言无关）
    public static func partnerLabel(mine: Bool, lang: String) -> String {
        switch (Lang.normalize(lang), mine) {
        case ("id", true): return "Dia bilang:"
        case ("id", false): return "Anda bilang:"
        case ("en", true): return "They said:"
        case ("en", false): return "You said:"
        case (_, true): return "对方说：" // i18n-ok
        default: return "您说：" // i18n-ok
        }
    }
    /// 上半屏空状态
    public static func partnerEmpty(lang: String) -> String {
        switch Lang.normalize(lang) {
        case "id": return "Silakan bicara"
        case "en": return "Please speak"
        default: return "请说话" // i18n-ok
        }
    }
}
