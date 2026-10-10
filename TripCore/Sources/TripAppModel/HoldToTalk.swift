import Foundation

/// 听写服务抽象。App 层用 SpeechAnalyzer（iOS 26）或 SFSpeechRecognizer（本机识别）实现。
public protocol Transcribing: AnyObject {
    func start(locale: String) async throws
    /// 结束录音并返回最终文本（没有 final 时用最后一条 partial）。
    func finish() async -> String
    func cancel()
}

public enum TalkTarget: Sendable { case them, me }

/// 按住说话（PRD v2 §7.5）：0.3 秒才开始、上滑约 80 点取消、最长 30 秒、进入后台取消。
@MainActor
public final class HoldToTalk {
    public enum Phase: Equatable, Sendable { case idle, pressing, recording(TalkTarget), cancelZone(TalkTarget), recognizing }
    public enum Outcome: Equatable, Sendable { case none, cancelled, empty, text(String, TalkTarget), failed }

    public private(set) var phase: Phase = .idle
    public private(set) var feedback: String?
    public static let minPress: TimeInterval = 0.3
    public static let cancelDistance: Double = 80
    public static let maxDuration: TimeInterval = 30

    private let transcriber: Transcribing
    private var pressedAt: Date?
    private var target: TalkTarget = .them
    private var locale = ""
    public var onChange: (() -> Void)?

    public init(transcriber: Transcribing) { self.transcriber = transcriber }

    public var buttonTitle: (them: String, me: String) {
        switch phase {
        case .recording(.them), .cancelZone(.them): return ("松手翻译，上滑取消", "按住说中文")
        case .recording(.me), .cancelZone(.me): return ("按住听对方", "松手翻译，上滑取消")
        default: return ("按住听对方", "按住说中文")
        }
    }

    public func press(_ t: TalkTarget, locale: String, at now: Date) {
        guard phase == .idle else { return }
        target = t; self.locale = locale; pressedAt = now; feedback = nil
        phase = .pressing; onChange?()
    }

    /// 由 UI 定时器在按下 0.3 秒后调用；未到时间则不开始。
    public func tick(at now: Date) async -> Outcome? {
        guard let p = pressedAt else { return nil }
        let held = now.timeIntervalSince(p)
        if phase == .pressing, held >= Self.minPress {
            do { try await transcriber.start(locale: locale); phase = .recording(target); onChange?() }
            catch { reset(); return .failed }
        }
        if case .recording = phase, held >= Self.maxDuration + Self.minPress { return await release(at: now) }
        return nil
    }

    /// 手指垂直位移（向上为负）。
    public func drag(dy: Double) {
        switch phase {
        case .recording(let t) where -dy > Self.cancelDistance: phase = .cancelZone(t); onChange?()
        case .cancelZone(let t) where -dy <= Self.cancelDistance: phase = .recording(t); onChange?()
        default: break
        }
    }

    public func release(at now: Date) async -> Outcome {
        defer { reset() }
        switch phase {
        case .pressing, .idle: return .none                         // 不足 0.3 秒
        case .cancelZone:
            transcriber.cancel(); feedback = "已取消"; return .cancelled
        case .recording(let t):
            phase = .recognizing; onChange?()
            let text = await transcriber.finish().trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { feedback = "没听清，按住再说一次"; return .empty }
            return .text(String(text.prefix(500)), t)
        case .recognizing: return .none
        }
    }

    public func enterBackground() {
        if phase != .idle { transcriber.cancel(); reset() }
    }

    private func reset() { phase = .idle; pressedAt = nil; onChange?() }
}
