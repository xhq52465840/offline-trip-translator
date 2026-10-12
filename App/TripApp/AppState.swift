import SwiftUI
import Combine
import TripCore
import TripLLM
import TripAppModel

/// 把非 UI 的模型（TripAppModel）桥接成 SwiftUI 可观察对象。业务逻辑全部在 TripAppModel 中测试。
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var decision: GateDecision = .onboarding
    @Published private(set) var rows: [PrepareRow] = []
    @Published var pendingCellularConfirm = false
    @Published var showPrepare = false
    @Published var translationToPrepare: [(String, String)] = []
    @Published private(set) var tick = 0                 // 对话模型变化时刷新

    let gate: AppGate
    let conversation: ConversationModel
    let clipboard = ClipboardHint()
    let downloader: ModelDownloader?
    let engine: LLMEngine
    let env: SystemDownloadEnvironment
    let network = NetworkMonitor()
    let probe: LanguagePackProbing
    let speechInstaller: SpeechAssetInstalling
    let purchase = PurchaseModel()
    let understander: Understander
    let talk: HoldToTalk
    let sessions: SessionStore
    private var session: StoredSession?
    @Published var askContinue = false
    @Published var speechAlert: String?
    /// 离线汇率（1 人民币 = ? 印尼盾），用户手动设置；不联网获取
    @Published var rate: ExchangeRate = AppState.loadRate() { didSet { AppState.saveRate(rate) } }
    @Published var faceToFace = false

    static func loadRate() -> ExchangeRate {
        let v = UserDefaults.standard.double(forKey: "idrPerCny")
        return v > 0 ? ExchangeRate(idrPerCny: v, updatedNote: "手动设置") : .default
    }
    static func saveRate(_ r: ExchangeRate) { UserDefaults.standard.set(r.idrPerCny, forKey: "idrPerCny") }

    /// 场景卡片最近使用排序（TripAppModel.RecentScenes）
    @Published var recentScenes: RecentScenes = AppState.loadRecent() { didSet { AppState.saveRecent(recentScenes) } }
    static func loadRecent() -> RecentScenes {
        (UserDefaults.standard.data(forKey: "recentScenes")).flatMap { try? JSONDecoder().decode(RecentScenes.self, from: $0) } ?? RecentScenes()
    }
    static func saveRecent(_ r: RecentScenes) { UserDefaults.standard.set(try? JSONEncoder().encode(r), forKey: "recentScenes") }

    /// 模型下载剩余时间估算（TripAppModel.DownloadETA）
    var eta = DownloadETA()
    var etaText: String {
        guard let d = downloader else { return Copy.downloadAdvice(eta: nil) }
        var received: Int64 = 0
        if case .downloading(let r, _) = d.machine.state { received = r }
        if case .paused(let r, _, _) = d.machine.state { received = r }
        if case .installed = d.machine.state { return "理解能力已就绪" }
        return Copy.downloadAdvice(eta: eta.text(remaining: max(0, d.entry.bytes - received)))
    }

    func enter(scene: Scenario?) {
        conversation.scene = scene
        if let scene { recentScenes.use(scene) }
        tick += 1
    }

    var isBlocking: Bool { if case .block = decision { return !showPrepare } else { return false } }
    var missingText: String { if case .block(let m) = decision { return AppGate.missingText(m) } else { return "" } }

    init(tier: DeviceTier, probe: LanguagePackProbing, translator: Translating, engine: LLMEngine,
         downloader: ModelDownloader?, env: SystemDownloadEnvironment, speechInstaller: SpeechAssetInstalling,
         transcriber: Transcribing, sessions: SessionStore,
         modelReadinessOverride: (() -> Readiness)? = nil, defaults: UserDefaults = .standard, trialStore: TrialStore? = nil) {
        self.probe = probe; self.engine = engine; self.downloader = downloader; self.env = env; self.speechInstaller = speechInstaller
        let dl = downloader
        gate = AppGate(tier: tier, probe: probe,
                       modelReadiness: modelReadinessOverride ?? { dl?.readiness ?? .unavailable("没有适合这台手机的理解能力") },
                       defaults: defaults)
        let store: TrialStore
        #if canImport(Security)
        store = trialStore ?? KeychainTrialStore()
        #else
        store = trialStore ?? InMemoryTrialStore()
        #endif
        understander = Understander(engine: engine)
        conversation = ConversationModel(translator: translator, understander: understander,
                                         trial: TrialCounter(store: store), metrics: MetricsSettings())
        conversation.onChange = { [weak self] in self?.tick += 1 }
        talk = HoldToTalk(transcriber: transcriber)
        self.sessions = sessions
        talk.onChange = { [weak self] in self?.tick += 1 }
        conversation.onPersist = { [weak self] msgs in
            guard let self else { return }
            if self.session == nil { self.session = try? self.sessions.startNew(theirLanguage: self.conversation.theirLanguage, deletePrevious: false) }
            self.session?.messages = msgs
            self.session?.theirLanguage = self.conversation.theirLanguage
            if let s = self.session { try? self.sessions.save(s) }
        }
        sessions.cleanup()
        switch sessions.load() {
        case .restored(let s): session = s; conversation.theirLanguage = s.theirLanguage; conversation.restore(s.messages)
        case .askContinue(let s): session = s; conversation.theirLanguage = s.theirLanguage; conversation.restore(s.messages); askContinue = true
        case .empty, .corrupt: break
        }
        downloader?.onChange = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if case .downloading(let r, _) = self.downloader?.machine.state { self.eta.record(bytes: r, at: Date()); self.tick += 1 }
                if case .awaitingCellularConfirmation = self.downloader?.machine.state { self.pendingCellularConfirm = true }
                await self.refresh(.downloadFinished)
            }
        }
        network.onChange = { [weak env] kind in env?.network = kind }
    }

    static func live() -> AppState {
        let tier = DeviceTier.from(physicalMemory: ProcessInfo.processInfo.physicalMemory)
        let entry = (try? ModelManifest.bundled())?.entry(for: tier)
        let env = SystemDownloadEnvironment(network: .wifi)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let downloader = entry.map {
            ModelDownloader(entry: $0, directory: support.appendingPathComponent("models/\($0.id)"),
                            transport: URLSessionTransport(), environment: env)
        }
        return AppState(tier: tier, probe: SystemPackProbe(), translator: SystemTranslator(), engine: LlamaCppEngine(),
                        downloader: downloader, env: env, speechInstaller: SystemSpeechInstaller(),
                        transcriber: LiveTranscriber(), sessions: SessionStore(directory: support.appendingPathComponent("sessions")))
    }

    func refresh(_ trigger: GateTrigger) async {
        decision = await gate.refresh(trigger)
        rows = PrepareRows.rows(status: gate.status, theirLanguages: gate.theirLanguages)
        if decision == .open {
            await loadModelIfNeeded()
            #if canImport(UIKit)
            clipboard.onForeground(hasStrings: UIPasteboard.general.hasStrings, changeCount: UIPasteboard.general.changeCount)
            #endif
        }
        tick += 1
    }

    #if DEBUG
    /// 模拟器 / XCUITest：`-UITestMode mock-ready|mock-not-ready|mock-onboarding`（TripAppModel.UITestMode，有单测）。
    /// MockEngine + 假翻译 + 假就绪；独立 UserDefaults 域与内存试用记录，每次启动清空，不碰真实数据。仅 DEBUG。
    static func uiTest(_ mode: UITestMode) -> AppState {
        UserDefaults.standard.removePersistentDomain(forName: UITestMode.defaultsSuite)
        let defaults = UserDefaults(suiteName: UITestMode.defaultsSuite) ?? .standard
        defaults.set(mode.onboardingCompleted, forKey: "onboarding.completed")
        let engine = MockEngine(pieceDelayNanos: 10_000_000) { _ in UITestMode.fakeUnderstanding }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-sessions")
        try? FileManager.default.removeItem(at: dir)
        let s = AppState(tier: .a8GB, probe: UITestProbe(mode: mode), translator: UITestTranslator(), engine: engine,
                         downloader: nil, env: SystemDownloadEnvironment(network: .wifi), speechInstaller: PreviewSpeechInstaller(),
                         transcriber: PreviewTranscriber(), sessions: SessionStore(directory: dir),
                         modelReadinessOverride: { mode.modelReadiness }, defaults: defaults, trialStore: InMemoryTrialStore())
        Task { try? await engine.load(modelURL: URL(fileURLWithPath: "/dev/null")) }
        return s
    }
    #endif

    /// 正常启动；DEBUG 构建带 `-UITestMode` 参数时走 uiTest。
    static func make() -> AppState {
        #if DEBUG
        if let m = UITestMode.from(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment) {
            return uiTest(m)
        }
        #endif
        return live()
    }

    private func loadModelIfNeeded() async {
        guard !engine.isLoaded, let url = downloader?.modelURL else { return }
        try? await engine.load(modelURL: url)
        try? await understander.warmUp()   // 预先算好系统提示 + 少样本的 KV
    }

    /// 「全部准备」：系统翻译（交给 translationTask 宿主）、听写资源、理解模型并行。
    func prepareAll() {
        var pairs: [(String, String)] = []
        for l in gate.theirLanguages { pairs += [(l, Lang.tourist), (Lang.tourist, l)] }
        translationToPrepare = pairs
        Task {
            for loc in [Lang.speechLocale(Lang.tourist)] + gate.theirLanguages.map(Lang.speechLocale) {
                try? await speechInstaller.install(locale: loc)
            }
            await refresh(.downloadFinished)
        }
        downloader?.start()
    }

    // MARK: 听写

    func speechReady(for target: TalkTarget) -> Bool {
        let item: PrepareItem = target == .me ? .touristSpeech : .speech(conversation.theirLanguage)
        if gate.status.items[item] == .ready { return true }
        speechAlert = target == .me ? "中文还不能离线听" : "\(Lang.displayName(conversation.theirLanguage))还不能离线听"
        return false
    }

    func handleTalk(_ outcome: HoldToTalk.Outcome) async {
        switch outcome {
        case .text(let s, .them): await conversation.receiveTheirs(s)
        case .text(let s, .me): await conversation.sendMine(s)
        case .failed: speechAlert = "需要麦克风和语音识别权限。可在系统设置里打开。"
        default: break
        }
        tick += 1
    }

    func enterBackground() { talk.enterBackground() }

    // MARK: 会话

    func newConversation(deletePrevious: Bool) {
        session = try? sessions.startNew(theirLanguage: conversation.theirLanguage, deletePrevious: deletePrevious)
        conversation.newConversation()
    }

    func continueSession() { if let s = session { try? sessions.touch(s) }; askContinue = false }

    func clearAllConversations() {
        try? sessions.deleteAll()
        session = nil
        conversation.newConversation()
    }

    func confirmCellular() { pendingCellularConfirm = false; downloader?.confirmCellular() }
}

