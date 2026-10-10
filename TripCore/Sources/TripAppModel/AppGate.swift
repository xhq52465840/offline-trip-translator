import Foundation
import TripCore

/// 启动 / 回到前台的准备检查（PRD v2 §4.3、§4.4）。
@MainActor
public final class AppGate {
    public private(set) var status = PrepareStatus(items: [:])
    public private(set) var decision: GateDecision = .onboarding
    public let tier: DeviceTier
    public var theirLanguages: [String]
    public var onboardingCompleted: Bool {
        get { defaults.bool(forKey: "onboarding.completed") }
        set { defaults.set(newValue, forKey: "onboarding.completed") }
    }
    public var onChange: (() -> Void)?

    private let probe: LanguagePackProbing
    private let modelReadiness: () -> Readiness
    private let defaults: UserDefaults

    public init(tier: DeviceTier, theirLanguages: [String] = ["id", "en"], probe: LanguagePackProbing,
                modelReadiness: @escaping () -> Readiness, defaults: UserDefaults = .standard) {
        self.tier = tier; self.theirLanguages = theirLanguages; self.probe = probe
        self.modelReadiness = modelReadiness; self.defaults = defaults
    }

    @discardableResult
    public func refresh(_ trigger: GateTrigger) async -> GateDecision {
        var items: [PrepareItem: Readiness] = [:]
        items[.touristSpeech] = await probe.speechReadiness(locale: Lang.speechLocale(Lang.tourist))
        for l in theirLanguages {
            let a = await probe.translationStatus(from: l, to: Lang.tourist)
            let b = await probe.translationStatus(from: Lang.tourist, to: l)
            items[.translation(l)] = Self.combine(a, b)
            items[.speech(l)] = await probe.speechReadiness(locale: Lang.speechLocale(l))
        }
        items[.understander] = modelReadiness()
        status = PrepareStatus(items: items)
        if status.isComplete && !onboardingCompleted { onboardingCompleted = true }
        decision = ReadinessGate.decide(tier: tier, status: status, onboardingCompleted: onboardingCompleted, trigger: trigger)
        onChange?()
        return decision
    }

    static func combine(_ a: PackStatus, _ b: PackStatus) -> Readiness {
        if a == .installed && b == .installed { return .ready }
        if a == .unsupported || b == .unsupported { return .unavailable("这台手机不支持这门语言的离线翻译") }
        return .needsDownload(bytes: nil)
    }

    /// 阻断提示正文（PRD v2 §13）。
    public static func missingText(_ items: [PrepareItem]) -> String {
        items.map { item -> String in
            switch item {
            case .touristSpeech: return "中文听写"
            case .translation(let l): return "\(Lang.displayName(l))翻译"
            case .speech(let l): return "\(Lang.displayName(l))听写"
            case .understander: return "理解能力"
            }
        }.joined(separator: "、")
    }
}
