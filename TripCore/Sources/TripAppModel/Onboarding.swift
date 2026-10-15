import Foundation
import TripCore

/// 首次准备 / 准备页的行（PRD v2 §9）。
public struct PrepareRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var state: String
    public var actionable: Bool
}

public enum PrepareRows {
    public static func rows(status: PrepareStatus, theirLanguages: [String], myLanguage: String = Lang.tourist) -> [PrepareRow] {
        func r(_ item: PrepareItem) -> Readiness { status.items[item] ?? .checking }
        let myId = myLanguage == Lang.tourist ? "zh-speech" : "\(myLanguage)-my-speech"
        var out = [PrepareRow(id: myId, title: L10n.f("%@听写", Lang.displayName(myLanguage)), state: text(r(.touristSpeech)), actionable: actionable(r(.touristSpeech)))]
        for l in theirLanguages where l != myLanguage {
            let name = Lang.displayName(l)
            out.append(PrepareRow(id: "\(l)-mt", title: L10n.f("%@翻译", name), state: text(r(.translation(l))), actionable: actionable(r(.translation(l)))))
            out.append(PrepareRow(id: "\(l)-speech", title: L10n.f("%@听写", name), state: text(r(.speech(l))), actionable: actionable(r(.speech(l)))))
        }
        out.append(PrepareRow(id: "model", title: L10n.t("理解能力"), state: text(r(.understander)), actionable: actionable(r(.understander))))
        return out
    }

    static func actionable(_ r: Readiness) -> Bool {
        switch r { case .ready, .checking, .unavailable, .downloading: return false; default: return true }
    }

    public static func size(_ b: Int64?) -> String {
        guard let b, b > 0 else { return "" }
        let gb = Double(b) / 1_000_000_000
        return gb >= 1 ? L10n.f("约 %@ GB", String(format: "%.1f", gb)) : L10n.f("约 %@ MB", String(format: "%.0f", Double(b) / 1_000_000))
    }

    public static func text(_ r: Readiness) -> String {
        switch r {
        case .ready: return L10n.t("已就绪")
        case .checking: return L10n.t("检查中")
        case .needsDownload(let b): let s = size(b); return s.isEmpty ? L10n.t("需要下载") : L10n.f("需要下载 · %@", s)
        case .downloading(let p): return L10n.f("下载中 %@%%", String(Int((p * 100).rounded())))
        case .paused(let p): return L10n.f("已暂停 %@%%", String(Int((p * 100).rounded())))
        case .notEnoughSpace(let n): let s = size(n); return s.isEmpty ? L10n.t("空间不够") : L10n.f("空间不够，还需要%@", s)
        case .verifyFailed: return L10n.t("下载的文件不完整，请重试")
        case .unavailable(let s): return s
        }
    }

    public static func cellularPrompt(bytes: Int64) -> String { L10n.f("当前不是 Wi‑Fi，要用流量下载%@吗？", size(bytes)) }
}

/// 示例演示页数据（审核用，不调用模型；PRD v2 §17 R1）。
public enum DemoScript {
    public struct Line: Identifiable, Sendable { public let id = UUID(); public let role: Role; public let source: String; public let literal: String; public let understood: String }
    /// 示例对话（跟随界面语言，P7）
    public static var lines: [Line] { L10n.isEnglish ? linesEnglish : linesChinese }
    static let linesEnglish: [Line] = [
        Line(role: .them, source: "50rb belum termasuk ongkos", literal: "Rp 50,000 not including fees", understood: "Rp 50,000, fare not included"),
        Line(role: .me, source: "Too expensive, can you go lower?", literal: "Terlalu mahal, bisa lebih murah?", understood: "Terlalu mahal, bisa lebih murah?"),
        Line(role: .them, source: "yang tadi 40 saja", literal: "the earlier 40 only", understood: "The earlier price, Rp 40,000 is fine"),
    ]
    static let linesChinese: [Line] = [
        Line(role: .them, source: "50rb belum termasuk ongkos", literal: "5万还没有包括费用", understood: "5万，不含车费"), // i18n-ok
        Line(role: .me, source: "太贵了，能不能便宜一点", literal: "Terlalu mahal, bisa lebih murah?", understood: "Terlalu mahal, bisa lebih murah?"), // i18n-ok
        Line(role: .them, source: "yang tadi 40 saja", literal: "刚才的40就行", understood: "刚才那个价格，4万就行"), // i18n-ok
    ]
}

/// v4 首次打开：只选「我说 / 对方说」，点开始后后台下载。这里是默认值与互斥规则（有单测）。
public enum FirstLaunch {
    /// 我方跟随系统语言（zh/en/id，其他 → 中文）；对方默认印尼语（我方是印尼语时默认中文）
    public static func defaults(preferred: [String]) -> (me: String, them: String) {
        let l = Lang.normalize(preferred.first ?? Lang.tourist)
        let me = Lang.all.contains(l) ? l : Lang.tourist
        return (me, me == "id" ? "zh-Hans" : "id")
    }
    /// 选了与另一方相同的语言 → 把另一方换成剩下的默认语言
    public static func pick(me: String, them: String, changed: TalkTarget) -> (me: String, them: String) {
        guard me == them else { return (me, them) }
        if changed == .me { return (me, me == "id" ? "zh-Hans" : "id") }
        return (them == "zh-Hans" ? "id" : "zh-Hans", them)
    }
    public static func downloadLine(bytes: Int64?) -> String {
        let s = PrepareRows.size(bytes)
        return s.isEmpty ? L10n.t("理解能力") : L10n.f("理解能力 %@", s)
    }
}
