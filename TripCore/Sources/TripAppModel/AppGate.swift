import Foundation
import TripCore

/// 启动 / 回到前台的准备检查（PRD v2 §4.3、§4.4）。
@MainActor
public final class AppGate {
    public private(set) var status = PrepareStatus(items: [:])
    public private(set) var decision: GateDecision = .onboarding
    public let tier: DeviceTier
    public var theirLanguages: [String]
    /// 我方语言（P4）；检查「我方 ↔ 每个对方语言」的语言包与听写
    public var myLanguage: String = Lang.tourist
    public var partnerLanguages: [String] { theirLanguages.filter { $0 != myLanguage } }
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
        items[.touristSpeech] = await probe.speechReadiness(locale: Lang.speechLocale(myLanguage))
        for l in partnerLanguages {
            let a = await probe.translationStatus(from: l, to: myLanguage)
            let b = await probe.translationStatus(from: myLanguage, to: l)
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
        if a == .unsupported || b == .unsupported { return .unavailable(L10n.t("这台手机不支持这门语言的离线翻译")) }
        return .needsDownload(bytes: nil)
    }

    /// 阻断提示正文（PRD v2 §13）。
    /// 任意两种语言之间（P5 代码侧）：双向都装好才算就绪；同语直接就绪
    public static func pairReadiness(_ a: String, _ b: String, probe: LanguagePackProbing) async -> Readiness {
        if Lang.normalize(a) == Lang.normalize(b) { return .ready }
        return combine(await probe.translationStatus(from: a, to: b), await probe.translationStatus(from: b, to: a))
    }

    public static func missingText(_ items: [PrepareItem], myLanguage: String = Lang.tourist) -> String {
        items.map { item -> String in
            switch item {
            case .touristSpeech: return L10n.f("%@听写", Lang.displayName(myLanguage))
            case .translation(let l): return L10n.f("%@翻译", Lang.displayName(l))
            case .speech(let l): return L10n.f("%@听写", Lang.displayName(l))
            case .understander: return L10n.t("理解能力")
            }
        }.joined(separator: L10n.isEnglish ? ", " : "、")
    }
}
