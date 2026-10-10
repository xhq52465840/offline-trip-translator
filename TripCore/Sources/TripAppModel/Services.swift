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
    public static let tourist = "zh-Hans"
    public static func speechLocale(_ id: String) -> String {
        switch id { case "id": return "id-ID"; case "en": return "en-US"; case "zh-Hans": return "zh-CN"; default: return id }
    }
    public static func displayName(_ id: String) -> String {
        switch id { case "id": return "印尼语"; case "en": return "英语"; default: return id }
    }
}
