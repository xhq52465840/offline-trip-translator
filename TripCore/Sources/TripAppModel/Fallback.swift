import Foundation
import TripCore

/// 系统翻译不可用时的本地模型直译（整体审查 G1）。
/// 场景：国行 / 某些地区的 iPhone 没有 Apple 印尼语语言包（unsupported），或语言包还没装好。
/// 提示词与训练回放（finetune/data/build_replay.py）相同，s400 在印→中、印→英上见过这类格式；其他方向是基座能力，质量较低。
/// 金额安全不变：Conversation 先把金额换成占位符再翻译，之后由程序还原，模型不碰数字。
public final class LocalModelTranslator: Translating {
    let engine: LLMEngine
    public init(engine: LLMEngine) { self.engine = engine }

    static let names = ["zh-Hans": ("简体中文", "Chinese"), "id": ("印尼语", "Indonesian"), "en": ("英语", "English")] // i18n-ok

    public static func messages(_ text: String, from: String, to: String) -> [ChatMessage] {
        let f = names[from] ?? (from, from), t = names[to] ?? (to, to)
        if to == "zh-Hans" {
            return [ChatMessage(.system, "你是翻译助手。只输出译文一行，不要解释。"), ChatMessage(.user, "把下面的\(f.0)翻译成\(t.0)：\n\(text)")] // i18n-ok
        }
        return [ChatMessage(.system, "You are a translator. Output only the translation on one line, no explanation."),
                ChatMessage(.user, "Translate the following \(f.1) into \(t.1):\n\(text)")]
    }

    public func translate(_ text: String, from: String, to: String) async throws -> String {
        guard engine.isLoaded else { throw LLMError.notLoaded }
        let out = try await engine.complete(Self.messages(text, from: from, to: to), options: GenerationOptions(maxTokens: 160, stopAtNewline: true))
        let line = out.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !line.isEmpty else { throw LLMError.decodeFailed(0) }
        return line
    }
}

/// 先用 Apple 翻译；该方向不支持或失败时改用本地模型（计划 §7 风险 1：降级需在界面标注）。
public final class FallbackTranslator: Translating {
    let primary: Translating, fallback: Translating, probe: LanguagePackProbing
    /// 最近一次各方向是否用了本地模型（"id>zh-Hans" → true），界面据此标注「本机模型翻译」
    public private(set) var usedFallback: [String: Bool] = [:]
    public init(primary: Translating, fallback: Translating, probe: LanguagePackProbing) {
        self.primary = primary; self.fallback = fallback; self.probe = probe
    }
    public func translate(_ text: String, from: String, to: String) async throws -> String {
        let key = "\(from)>\(to)"
        if await probe.translationStatus(from: from, to: to) != .unsupported {
            do { let r = try await primary.translate(text, from: from, to: to); usedFallback[key] = false; return r }
            catch { /* 语言包没装好 / 系统出错 → 走本地模型 */ }
        }
        let r = try await fallback.translate(text, from: from, to: to)
        usedFallback[key] = true
        return r
    }
}
