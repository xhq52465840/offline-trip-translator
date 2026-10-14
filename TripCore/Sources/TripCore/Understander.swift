import Foundation

public extension PromptBuilder {
    /// 固定少样本（来自 model_eval/run.py）。
    public static let fewShot: [(user: String, assistant: String)] = [
        ("这场对话（时间顺序）：\n对方：harga 30rb ／ 中文：价格3万\n我：太贵了\n\n金额：无\n词：无\n\n对方原文：yang tadi 25 aja\n字面：\n刚才的25就行", "刚才那个价格2.5万就行"),
        ("这场对话（时间顺序）：\n（无）\n\n金额：无\n词：无\n\n对方原文：udh sampe blm?\n字面：\nudh sampe blm？", "已经到了吗？"),
    ]

    /// 英文目标少样本（P3），与中文两条一一对应
    public static let fewShotEnglish: [(user: String, assistant: String)] = [
        ("Conversation (in order):\nThem: harga 30rb / English: the price is Rp 30,000\nMe: Too expensive\n\nAmounts: none\nWords: none\n\nOriginal: yang tadi 25 aja\nLiteral:\nthe earlier 25 only", "The earlier price, Rp 25,000, is fine"),
        ("Conversation (in order):\n(none)\n\nAmounts: none\nWords: none\n\nOriginal: udh sampe blm?\nLiteral:\nudh arrive blm?", "Have you arrived yet?"),
    ]
    public static func fewShot(for target: String) -> [(user: String, assistant: String)] { target == "en" ? fewShotEnglish : fewShot }

    /// 可缓存的前缀：system + 少样本。
    public var prefixMessages: [ChatMessage] {
        [ChatMessage(.system, system)] + Self.fewShot(for: target).flatMap { [ChatMessage(.user, $0.user), ChatMessage(.assistant, $0.assistant)] }
    }

    func messages(context: [ContextTurn], source: String, literal: String, glossary: [GlossaryHit] = []) -> [ChatMessage] {
        prefixMessages + [ChatMessage(.user, user(context: context, source: source, literal: literal, glossary: glossary))]
    }
}

/// 理解一句对方消息：生成 + 校验 + 超时（技术设计 v2 §8、§9）。
public final class Understander: @unchecked Sendable {
    public let engine: LLMEngine
    public var builder: PromptBuilder
    public var timeout: TimeInterval
    public var options: GenerationOptions

    public init(engine: LLMEngine, builder: PromptBuilder = .init(), timeout: TimeInterval = 1.6, options: GenerationOptions = .init()) {
        self.engine = engine; self.builder = builder; self.timeout = timeout; self.options = options
    }

    public func warmUp() async throws { try await engine.warmUp(prefix: builder.prefixMessages) }

    public enum Outcome: Equatable, Sendable {
        case replaced(String)
        case keepLiteral(reason: String)
    }

    public func understand(context: [ContextTurn], source: String, literal: String, glossary: [GlossaryHit] = []) async -> Outcome {
        let msgs = builder.messages(context: context, source: source, literal: literal, glossary: glossary)
        let engine = self.engine, options = self.options
        let raw: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                var out = ""
                do { for try await p in engine.generate(msgs, options: options) { out += p } } catch { return nil }
                return Task.isCancelled ? nil : out
            }
            group.addTask { [timeout] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let raw else { return .keepLiteral(reason: "timeoutOrError") }
        switch OutputValidator.validate(output: raw, literal: literal, source: source, context: context, target: builder.target) {
        case .accepted(let s): return .replaced(s)
        case .unchanged: return .keepLiteral(reason: "unchanged")
        case .rejected(let r): return .keepLiteral(reason: "\(r)")
        }
    }
}
