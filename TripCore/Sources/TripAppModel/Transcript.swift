import Foundation
import TripCore

/// 聊天式记录的一行（UX 改版）：两种语言都显示，带金额胶囊、理解结果、时间。
public struct BubbleRow: Identifiable, Equatable, Sendable {
    public enum Side: Equatable, Sendable { case leading, trailing }   // 对方在左 / 我在右（从阅读者视角）
    public let id: UUID
    public let side: Side
    public let primary: String         // 阅读者的语言（大字）
    public let secondary: String?      // 另一种语言（小字）
    public let note: String?           // 「字面：…」或「已按上下文理解」
    public let chips: [AmountChip]
    public let time: String
    public let pending: Bool
}

public enum Viewer: Sendable { case me, partner }

public enum Transcript {
    public static func time(_ d: Date, tz: TimeZone = .current) -> String {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz
        let h = c.component(.hour, from: d), m = c.component(.minute, from: d)
        return String(format: "%02d:%02d", h, m)
    }

    /// viewer = .me：中文为主；viewer = .partner：对方语言为主（面对面模式上半屏，旋转 180°）。
    public static func rows(_ messages: [Message], viewer: Viewer, rate: ExchangeRate?, fx: FXContext? = nil, lang: String = Lang.tourist, tz: TimeZone = .current) -> [BubbleRow] {
        messages.compactMap { m in
            if m.status == .trialBlocked && viewer == .partner { return nil }
            let mine = m.role == .me
            let side: BubbleRow.Side = (mine == (viewer == .me)) ? .trailing : .leading
            let chipSource = mine ? (m.foreign ?? "") : m.source
            let chips: [AmountChip]
            if let fx, viewer == .me { chips = Money.chips(in: chipSource, fx: fx) } else { chips = Money.chips(in: chipSource, rate: viewer == .me ? rate : nil) }
            let primary: String, secondary: String?, note: String?
            switch (viewer, mine) {
            case (.me, true):
                primary = m.source; secondary = m.foreign
                note = m.showBackTranslation ? m.backTranslation.map { L10n.f("对方看到的意思：%@", $0) } : nil
            case (.me, false):
                primary = m.mainLine; secondary = m.source
                note = m.literalLine
            case (.partner, true):
                primary = m.foreign ?? "…"; secondary = m.source; note = nil
            case (.partner, false):
                primary = m.source; secondary = m.display ?? m.literal; note = nil
            }
            // 金额换算注释（PRD v2 §7.9）：只给阅读者是我的一侧加；数量级来自代码解析，不来自模型
            var p = primary, sec = secondary, nt = note
            if let fx, viewer == .me {
                if mine {
                    sec = sec.map { AmountAnnotator.annotateSource($0, to: fx.currency, rates: fx.rates) }
                    let notes = ForeignCashParser.notes(in: m.source, lang: lang, rates: fx.rates)
                    if !notes.isEmpty {
                        nt = [nt, notes.joined(separator: lang.hasPrefix("zh") ? "，" : ", ")].compactMap { $0 }.joined(separator: "\n")
                    }
                } else {
                    p = AmountAnnotator.annotateDisplay(p, lang: lang, allowed: AmountAnnotator.allowedValues(source: m.source), to: fx.currency, rates: fx.rates)
                    sec = sec.map { AmountAnnotator.annotateSource($0, to: fx.currency, rates: fx.rates) }
                    // 对方说了 ¥ / $（如对方是中国人或美国人、我方是印尼语）：反向标注 Rp
                    let notes = ForeignCashParser.notes(in: m.source, lang: lang, rates: fx.rates)
                    if fx.currency == .idr, !notes.isEmpty { nt = [nt, notes.joined(separator: ", ")].compactMap { $0 }.joined(separator: "\n") }
                }
            }
            return BubbleRow(id: m.id, side: side, primary: p, secondary: sec, note: nt, chips: chips,
                             time: time(m.createdAt, tz: tz), pending: m.status == .translating)
        }
    }
}

/// 触感反馈事件 → 系统反馈类型（UI 层映射到 UIImpactFeedbackGenerator / UINotificationFeedbackGenerator）
public enum HapticEvent: Sendable { case recordStart, recordCancel, sent, understood, failed }
public enum HapticKind: Equatable, Sendable { case impactMedium, impactLight, success, warning, error }
public extension HapticEvent {
    var kind: HapticKind {
        switch self {
        case .recordStart: return .impactMedium
        case .recordCancel: return .warning
        case .sent: return .impactLight
        case .understood: return .success
        case .failed: return .error
        }
    }
}
