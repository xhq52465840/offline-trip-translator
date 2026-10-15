import Foundation
import TripCore

/// v4 单按钮「按住说话」：自动决定这一句是谁说的（决定听写语言）。
/// 规则：轮流说话 —— 上一句是对方 → 这次是我；上一句是我 → 这次是对方；空对话 → 我先开口。
/// 用户可在按钮旁手动换边（forced），或在气泡上「说错人了」重说。
public enum TalkRouter {
    public static func predict(messages: [Message], forced: TalkTarget? = nil) -> TalkTarget {
        if let forced { return forced }
        guard let last = messages.last(where: { $0.status != .trialBlocked }) else { return .me }
        return last.role == .them ? .me : .them
    }

    /// 听写结果明显是另一方的语言（例如按「我」听写却得到印尼语文字）→ 改判。只在两种语言文字体系可区分时生效。
    public static func resolve(_ predicted: TalkTarget, text: String, myLanguage: String, theirLanguage: String) -> TalkTarget {
        guard let g = LanguageGuess.guess(text) else { return predicted }
        let me = Lang.normalize(myLanguage), them = Lang.normalize(theirLanguage)
        if predicted == .me, g == them, g != me { return .them }
        if predicted == .them, g == me, g != them { return .me }
        return predicted
    }

    /// 按钮下面的小字：告诉用户这次按住听谁
    public static func caption(_ t: TalkTarget, myLanguage: String, theirLanguage: String) -> String {
        t == .me ? L10n.f("这次听我说%@ · 松手翻译", Lang.displayName(myLanguage))
                 : L10n.f("这次听对方说%@ · 松手翻译", Lang.displayName(theirLanguage))
    }
    public static func switchLabel(_ t: TalkTarget) -> String { t == .me ? L10n.t("换成对方说") : L10n.t("换成我说") }
}
