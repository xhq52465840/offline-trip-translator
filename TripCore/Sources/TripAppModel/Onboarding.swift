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
    public static func rows(status: PrepareStatus, theirLanguages: [String]) -> [PrepareRow] {
        func r(_ item: PrepareItem) -> Readiness { status.items[item] ?? .checking }
        var out = [PrepareRow(id: "zh-speech", title: "中文听写", state: text(r(.touristSpeech)), actionable: actionable(r(.touristSpeech)))]
        for l in theirLanguages {
            let name = Lang.displayName(l)
            out.append(PrepareRow(id: "\(l)-mt", title: "\(name)翻译", state: text(r(.translation(l))), actionable: actionable(r(.translation(l)))))
            out.append(PrepareRow(id: "\(l)-speech", title: "\(name)听写", state: text(r(.speech(l))), actionable: actionable(r(.speech(l)))))
        }
        out.append(PrepareRow(id: "model", title: "理解能力", state: text(r(.understander)), actionable: actionable(r(.understander))))
        return out
    }

    static func actionable(_ r: Readiness) -> Bool {
        switch r { case .ready, .checking, .unavailable, .downloading: return false; default: return true }
    }

    public static func size(_ b: Int64?) -> String {
        guard let b, b > 0 else { return "" }
        let gb = Double(b) / 1_000_000_000
        return gb >= 1 ? String(format: "约 %.1f GB", gb) : String(format: "约 %.0f MB", Double(b) / 1_000_000)
    }

    public static func text(_ r: Readiness) -> String {
        switch r {
        case .ready: return "已就绪"
        case .checking: return "检查中"
        case .needsDownload(let b): let s = size(b); return s.isEmpty ? "需要下载" : "需要下载 · \(s)"
        case .downloading(let p): return "下载中 \(Int((p * 100).rounded()))%"
        case .paused(let p): return "已暂停 \(Int((p * 100).rounded()))%"
        case .notEnoughSpace(let n): let s = size(n); return s.isEmpty ? "空间不够" : "空间不够，还需要\(s)"
        case .verifyFailed: return "下载的文件不完整，请重试"
        case .unavailable(let s): return s
        }
    }

    public static func cellularPrompt(bytes: Int64) -> String { "当前不是 Wi‑Fi，要用流量下载\(size(bytes))吗？" }
}

/// 示例演示页数据（审核用，不调用模型；PRD v2 §17 R1）。
public enum DemoScript {
    public struct Line: Identifiable, Sendable { public let id = UUID(); public let role: Role; public let source: String; public let literal: String; public let understood: String }
    public static let lines: [Line] = [
        Line(role: .them, source: "50rb belum termasuk ongkos", literal: "5万还没有包括费用", understood: "5万，不含车费"),
        Line(role: .me, source: "太贵了，能不能便宜一点", literal: "Terlalu mahal, bisa lebih murah?", understood: "Terlalu mahal, bisa lebih murah?"),
        Line(role: .them, source: "yang tadi 40 saja", literal: "刚才的40就行", understood: "刚才那个价格，4万就行"),
    ]
}
