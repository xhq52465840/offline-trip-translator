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
    /// 界面上的语言名（跟随界面语言，P7）
    public static func displayName(_ id: String) -> String {
        if L10n.isEnglish {
            switch id { case "id": return "Indonesian"; case "en": return "English"; case "zh-Hans": return "Chinese"; default: return id }
        }
        return chineseName(id)
    }
    /// 中文提示词里用的语言名（与界面语言无关）
    public static func chineseName(_ id: String) -> String {
        switch id { case "id": return "印尼语"; case "en": return "英语"; case "zh-Hans": return "中文"; default: return id } // i18n-ok
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

/// 界面语言（P7）：zh-Hans 或 en。App 启动时按系统语言 / App 内设置写入；模型层文案据此选择。
public enum L10n {
    nonisolated(unsafe) public static var uiLanguage: String = "zh-Hans"
    public static var isEnglish: Bool { uiLanguage == "en" }
    /// 中文原文即键；英文表见 L10nTable.swift（由 i18n/strings.json 生成，scripts/i18n.py 校验）
    public static func t(_ zh: String) -> String { isEnglish ? (L10nTable.en[zh] ?? zh) : zh }
    /// 只用 %@（参数一律先转成 String），避免格式符类型不匹配崩溃
    public static func f(_ zh: String, _ args: String...) -> String { String(format: t(zh), arguments: args.map { $0 as NSString }) }
    /// 系统语言 / App 内设置 → 界面语言：中文系统用中文，其余用英文
    public static func resolve(preferred: [String], override: String?) -> String {
        if let o = override, o == "zh-Hans" || o == "en" { return o }
        return (preferred.first ?? "zh-Hans").lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
    }
}
