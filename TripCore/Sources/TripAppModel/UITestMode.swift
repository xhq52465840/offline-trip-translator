import Foundation
import TripCore

/// 模拟器 / XCUITest 用的启动模式（只在 DEBUG 构建里由 App 读取）。
/// 启动参数 `-UITestMode mock-ready` 或环境变量 `UITEST_MODE=mock-ready`。
/// 注入 MockEngine + 假翻译 + 假就绪状态，不需要 1.1 GB 下载，也不需要 Apple Translation 语言包。
public enum UITestMode: String, CaseIterable, Sendable {
    /// 全部就绪：直接进首页/对话
    case mockReady = "mock-ready"
    /// 已完成过引导但模型缺失：每次启动出现阻断弹窗
    case mockNotReady = "mock-not-ready"
    /// 首次启动：显示引导页
    case mockOnboarding = "mock-onboarding"

    public static let argument = "-UITestMode"
    public static let envKey = "UITEST_MODE"
    /// 独立的 UserDefaults 域，每次启动清空，避免污染真实数据
    public static let defaultsSuite = "app.tripunderstand.uitest"

    public static func from(arguments: [String], environment: [String: String]) -> UITestMode? {
        if let i = arguments.firstIndex(of: argument), i + 1 < arguments.count, let m = UITestMode(rawValue: arguments[i + 1]) { return m }
        return environment[envKey].flatMap(UITestMode.init(rawValue:))
    }

    public var onboardingCompleted: Bool { self != .mockOnboarding }
    public var modelReadiness: Readiness { self == .mockReady ? .ready : .needsDownload(bytes: 1_117_320_736) }
    public var packStatus: PackStatus { self == .mockReady ? .installed : .supported }
    public var speechReadiness: Readiness { self == .mockReady ? .ready : .needsDownload(bytes: nil) }

    /// 假翻译表（mock 模式下的「系统翻译」）。未命中时返回带标记的原文，便于 UI 测试断言。
    public static let fakeTranslations: [String: String] = [
        "⟦N1⟧ belum termasuk ongkos": "⟦N1⟧还没有包括费用",
        "Pak, saya sudah di lobi": "先生，我已经在大堂了",
        "Harganya Rp ⟦N1⟧ kak": "价格是⟦N1⟧",
        "太贵了": "Terlalu mahal",
        "Terlalu mahal": "太贵了",
    ]
    /// 按目标语言的假翻译（P4：三语 UI 测试）；键为「目标语言|原文」，未命中再查旧表
    public static let fakeTranslationsByTarget: [String: String] = [
        "en|Harganya Rp ⟦N1⟧ kak": "The price is ⟦N1⟧",
        "en|太贵了": "Too expensive",
        "en|Terlalu mahal": "Too expensive",
        "id|Too expensive": "Terlalu mahal",
        "zh-Hans|Too expensive": "太贵了",
        "en|Pak, saya sudah di lobi": "Sir, I'm already in the lobby",
    ]
    public static func fakeTranslate(_ text: String, to: String? = nil) -> String {
        if let to, let v = fakeTranslationsByTarget["\(to)|\(text)"] { return v }
        return fakeTranslations[text] ?? "〔mock〕\(text)"
    }
    /// 启动参数：预置一条带金额的对方消息（UI 测试截图金额换算）
    public static let seedAmountArgument = "-UITestSeedAmount"
    /// 启动参数：`-UITestLangs en,zh-Hans` 指定「我方,对方」语言（P4）
    public static let langsArgument = "-UITestLangs"
    public static let seedAmountText = "Harganya Rp 100.000 kak"
    /// MockEngine 的固定理解输出
    public static let fakeUnderstanding = "5万，不含车费"
    public static let fakeUnderstandingEnglish = "The price is Rp 100,000"
    /// 按提示词语言选假理解输出
    public static func fakeUnderstanding(for msgs: [ChatMessage]) -> String {
        (msgs.first?.content.hasPrefix("You fix English") ?? false) ? fakeUnderstandingEnglish : fakeUnderstanding
    }
}

/// 按模式返回的假语言包探测
public final class UITestProbe: LanguagePackProbing {
    let mode: UITestMode
    public init(mode: UITestMode) { self.mode = mode }
    public func translationStatus(from: String, to: String) async -> PackStatus { mode.packStatus }
    public func speechReadiness(locale: String) async -> Readiness { mode.speechReadiness }
}

public final class UITestTranslator: Translating {
    public init() {}
    public func translate(_ text: String, from: String, to: String) async throws -> String { UITestMode.fakeTranslate(text, to: to) }
}
