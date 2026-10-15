import Foundation
import TripCore

/// v4 状态条（替代阻断弹窗）：对话页顶部一行，非就绪时出现；就绪 / 离线已就绪时不显示。
/// 任何状态下快捷句、金额卡片、Apple 翻译都照常可用。
public struct StatusBar: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case modelPreparing(percent: Int?)   // 理解能力下载中 / 未下载
        case packMissing(String)             // 某语言 Apple 离线包没下载
        case nothingReady                    // 翻译和理解都没就绪
        case waitingNetwork                  // 需要下载但没网
    }
    public let kind: Kind
    public var text: String {
        switch kind {
        case .modelPreparing(let p?): return L10n.f("理解能力准备中 %@%%", String(p))
        case .modelPreparing(nil): return L10n.t("理解能力未下载 · 点这里下载")
        case .packMissing(let l): return L10n.f("%@离线包未下载 · 去下载", Lang.displayName(l))
        case .nothingReady: return L10n.t("暂时不能翻译 · 可以先用快捷句")
        case .waitingNetwork: return L10n.t("连上网后自动继续下载")
        }
    }
    /// 警示色（不只靠颜色：文字本身说明状态）
    public var isWarning: Bool { kind == .nothingReady }
    public var tappable: Bool { kind != .waitingNetwork }

    /// 由准备状态计算；nil = 不显示。
    public static func compute(status: PrepareStatus, partner: String, online: Bool) -> StatusBar? {
        let model = status.items[.understander] ?? .checking
        let pack = status.items[.translation(partner)] ?? .checking
        let modelOK = model == .ready
        let packOK: Bool = { if pack == .ready { return true }; if case .unavailable = pack { return true }; return false }()
        if modelOK && packOK { return nil }
        if !modelOK && !packOK && pack != .checking { return online ? StatusBar(kind: .nothingReady) : StatusBar(kind: .waitingNetwork) }
        if !packOK, pack != .checking { return online ? StatusBar(kind: .packMissing(partner)) : StatusBar(kind: .waitingNetwork) }
        switch model {
        case .downloading(let p): return StatusBar(kind: .modelPreparing(percent: Int((p * 100).rounded())))
        case .paused(let p): return StatusBar(kind: .modelPreparing(percent: Int((p * 100).rounded())))
        case .checking, .unavailable: return nil
        default: return online ? StatusBar(kind: .modelPreparing(percent: nil)) : StatusBar(kind: .waitingNetwork)
        }
    }
}
