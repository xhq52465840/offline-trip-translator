import Foundation

/// 剪贴板提示（PRD v2 §7.6）：回到前台只判断有没有文字（hasStrings），点了才读（PasteButton）。
@MainActor
public final class ClipboardHint {
    public private(set) var visible = false
    public private(set) var notice: String?
    private var dismissedChangeCount: Int?
    private var lastChangeCount: Int?

    public init() {}

    /// scenePhase == .active 时调用。changeCount 来自 UIPasteboard.changeCount（读取不会触发授权）。
    public func onForeground(hasStrings: Bool, changeCount: Int) {
        lastChangeCount = changeCount
        visible = hasStrings && changeCount != dismissedChangeCount
    }

    public func dismiss() { dismissedChangeCount = lastChangeCount; visible = false }

    /// 用户点了 PasteButton 后拿到的文本。返回要收进对话的文本；重复则返回 nil 并给出提示。
    public func accept(_ text: String, lastSource: String?) -> String? {
        visible = false
        dismissedChangeCount = lastChangeCount
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if let l = lastSource, l == t { notice = "这句已经在对话里了"; return nil }
        notice = t.count > 500 ? "只保留前 500 字" : nil
        return String(t.prefix(500))
    }
}
