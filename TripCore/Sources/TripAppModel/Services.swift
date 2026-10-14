import Foundation
import TripCore

/// 系统翻译语言包状态（对应 Translation 框架 LanguageAvailability.Status：installed / supported / unsupported）。
public enum PackStatus: Equatable, Sendable { case installed, supported, unsupported }

/// 平台服务抽象。App 层用 Translation / Speech 框架实现，测试用假实现。
public protocol LanguagePackProbing: AnyObject {
    func translationStatus(from: String, to: String) async -> PackStatus
    func speechReadiness(locale: String) async -> Readiness
}

public protocol Translating: AnyObject {
    func translate(_ text: String, from: String, to: String) async throws -> String
}

public enum Lang {
    /// 默认「我方语言」（三语改造 P1：每一方都可以是 zh-Hans / id / en）
    public static let tourist = "zh-Hans"
    public static let all = ["zh-Hans", "id", "en"]
    public static func normalize(_ id: String) -> String {
        let l = id.lowercased()
        if l.hasPrefix("zh") { return "zh-Hans" }
        if l.hasPrefix("id") || l.hasPrefix("in") { return "id" }
        if l.hasPrefix("en") { return "en" }
        return id
    }
    public static func speechLocale(_ id: String) -> String {
        switch id { case "id": return "id-ID"; case "en": return "en-US"; case "zh-Hans": return "zh-CN"; default: return id }
    }
    public static func displayName(_ id: String) -> String {
        switch id { case "id": return "印尼语"; case "en": return "英语"; case "zh-Hans": return "中文"; default: return id }
    }
}

/// 一条消息从 from 语言到 to 语言怎么处理（三语改造 P1，P3 扩展理解目标）。
public enum LangRoute: Equatable, Sendable {
    case same                       // 同语：原文直接显示，不翻译
    case translate                  // 只用翻译（Apple Translation）
    case translateAndUnderstand     // 翻译 + 本地模型按上下文理解（对方是印尼语/英语口语，目标是 zh 或 en）
    public static func route(from: String, to: String) -> LangRoute {
        let f = Lang.normalize(from), t = Lang.normalize(to)
        if f == t { return .same }
        if PromptBuilder.supportsUnderstanding(target: t) && f != "zh-Hans" { return .translateAndUnderstand }
        return .translate
    }
}
