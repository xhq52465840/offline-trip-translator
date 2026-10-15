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
    let defaults: UserDefaults
    private var session: StoredSession?
    @Published var askContinue = false
    @Published var speechAlert: String?
    /// 离线汇率（1 人民币 = ? 印尼盾），用户手动设置；不联网获取
    @Published var faceToFace = false

    /// 金额换算（PRD v2 §7.9）：中文界面 → 人民币，其余 → 美元；汇率有网时自动刷新（≥6 小时一次），超过 30 天警告
    let fxStore = FXStore()
    @Published var fx = FXContext(rates: FXStore().current,
                                  currency: TargetCurrency.forLocale(Locale.preferredLanguages.first ?? "zh-Hans"))
    var fxRefreshEnabled = true
    func refreshFX(force: Bool = false) async {
        guard fxRefreshEnabled else { return }
        let online = env.network != .none
        if force { UserDefaults.standard.removeObject(forKey: "fx.lastAttempt") }
        let r = await fxStore.refresh(now: Date(), online: online) { url in
            var req = URLRequest(url: url); req.timeoutInterval = 10
            return try await URLSession.shared.data(for: req).0
        }
        if case .updated(let x) = r { fx.rates = x }
    }


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
        if case .installed = d.machine.state { return L10n.t("理解能力已就绪") }
        return Copy.downloadAdvice(eta: eta.text(remaining: max(0, d.entry.bytes - received)))
    }

    func enter(scene: Scenario?) {
        conversation.scene = scene
        if let scene { recentScenes.use(scene) }
        tick += 1
    }

    /// v4 状态条（TripAppModel.StatusBar，有单测）
    var statusBar: StatusBar? { StatusBar.compute(status: gate.status, partner: theirLanguage, online: env.network != .none) }

    var isBlocking: Bool { if case .block = decision { return !showPrepare } else { return false } }
    var missingText: String { if case .block(let m) = decision { return AppGate.missingText(m, myLanguage: myLanguage) } else { return "" } }

    init(tier: DeviceTier, probe: LanguagePackProbing, translator: Translating, engine: LLMEngine,
         downloader: ModelDownloader?, env: SystemDownloadEnvironment, speechInstaller: SpeechAssetInstalling,
         transcriber: Transcribing, sessions: SessionStore,
         modelReadinessOverride: (() -> Readiness)? = nil, defaults: UserDefaults = .standard, trialStore: TrialStore? = nil) {
        self.probe = probe; self.engine = engine; self.downloader = downloader; self.env = env; self.speechInstaller = speechInstaller
        self.defaults = defaults
        let dl = downloader
        gate = AppGate(tier: tier, theirLanguages: ["id"], probe: probe,   // G3：只检查正在用的两种语言（applyLanguages 里同步）
                       modelReadiness: modelReadinessOverride ?? { dl?.readiness ?? .unavailable(L10n.t("没有适合这台手机的理解能力")) },
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
        talk = HoldToTalk(transcriber: transcriber)
        self.sessions = sessions
        // 闭包捕获 self 之前，所有 let 存储属性必须先完成初始化（Swift 6 确定初始化检查）。
        conversation.onChange = { [weak self] in self?.tick += 1 }
        applyLanguages(me: defaults.string(forKey: "lang.me") ?? AppState.defaultMyLanguage(), them: defaults.string(forKey: "lang.them"))
        talk.onChange = { [weak self] in self?.tick += 1 }
        conversation.onPersist = { [weak self] msgs in
            guard let self else { return }
            if self.session == nil { self.session = try? self.sessions.startNew(theirLanguage: self.conversation.theirLanguage, myLanguage: self.conversation.myLanguage, deletePrevious: false) }
            self.session?.messages = msgs
            self.session?.theirLanguage = self.conversation.theirLanguage
            self.session?.myLanguage = self.conversation.myLanguage
            if let s = self.session { try? self.sessions.save(s) }
        }
        sessions.cleanup()
        switch sessions.load() {
        case .restored(let s): session = s; applyLanguages(me: s.myLanguage ?? conversation.myLanguage, them: s.theirLanguage); conversation.restore(s.messages)
        case .askContinue(let s): session = s; applyLanguages(me: s.myLanguage ?? conversation.myLanguage, them: s.theirLanguage); conversation.restore(s.messages); askContinue = true
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
        // G1：Apple 翻译不支持 / 没装好的方向，改用本地模型直译
        let probe = SystemPackProbe(), engine = LlamaCppEngine()
        let translator = FallbackTranslator(primary: SystemTranslator(), fallback: LocalModelTranslator(engine: engine), probe: probe)
        return AppState(tier: tier, probe: probe, translator: translator, engine: engine,
                        downloader: downloader, env: env, speechInstaller: SystemSpeechInstaller(),
                        transcriber: LiveTranscriber(), sessions: SessionStore(directory: support.appendingPathComponent("sessions")))
    }

    // MARK: 语言（P4）：双方各自选；我方默认跟随系统语言（zh/en/id，其他 → 中文）

    static func defaultMyLanguage() -> String {
        let l = Lang.normalize(Locale.preferredLanguages.first ?? "zh-Hans")
        return Lang.all.contains(l) ? l : Lang.tourist
    }
    var myLanguage: String { conversation.myLanguage }
    var theirLanguage: String { conversation.theirLanguage }

    /// 设置双方语言：同步到对话、准备检查、币种（按我方语言），并持久化
    func applyLanguages(me: String? = nil, them: String? = nil) {
        conversation.setLanguages(me: me, them: them)
        if conversation.theirLanguage == conversation.myLanguage && them == nil {
            conversation.setLanguages(them: conversation.myLanguage == "id" ? "zh-Hans" : "id")
        }
        gate.myLanguage = conversation.myLanguage
        gate.theirLanguages = [conversation.theirLanguage]   // G3：只检查「我方 + 当前对方」，换语言时再提示下载
        fx.currency = TargetCurrency.forLocale(conversation.myLanguage)
        defaults.set(conversation.myLanguage, forKey: "lang.me"); defaults.set(conversation.theirLanguage, forKey: "lang.them")
        tick += 1
    }
    func setMyLanguage(_ l: String) { applyLanguages(me: l); Task { await refresh(.foreground) } }
    func setTheirLanguage(_ l: String) { applyLanguages(them: l); Task { await refresh(.foreground) } }
    func swapLanguages() { applyLanguages(me: theirLanguage, them: myLanguage); Task { await refresh(.foreground) } }

    func refresh(_ trigger: GateTrigger) async {
        decision = await gate.refresh(trigger)
        if trigger != .downloadFinished { Task { await refreshFX() } }
        rows = PrepareRows.rows(status: gate.status, theirLanguages: gate.partnerLanguages, myLanguage: myLanguage)
        // v4：老用户缺理解能力时，Wi‑Fi 下在后台自动续传（不再用阻断弹窗催）
        if case .block(let m) = decision, m.contains(.understander), env.network == .wifi, gate.onboardingCompleted {
            if case .needsDownload = downloader?.readiness { downloader?.start() }
            if case .paused = downloader?.readiness { downloader?.resume() }
        }
        if decision == .open || gate.status.items[.understander] == .ready { await loadModelIfNeeded() }
        if decision != .onboarding && decision != .unsupportedDevice {
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
        let engine = MockEngine(pieceDelayNanos: 10_000_000) { msgs in UITestMode.fakeUnderstanding(for: msgs) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("uitest-sessions")
        try? FileManager.default.removeItem(at: dir)
        let s = AppState(tier: .a8GB, probe: UITestProbe(mode: mode), translator: UITestTranslator(), engine: engine,
                         downloader: nil, env: SystemDownloadEnvironment(network: .wifi), speechInstaller: PreviewSpeechInstaller(),
                         transcriber: PreviewTranscriber(), sessions: SessionStore(directory: dir),
                         modelReadinessOverride: { mode.modelReadiness }, defaults: defaults, trialStore: InMemoryTrialStore())
        s.fxRefreshEnabled = false            // UI 测试用内置汇率，结果可复现
        s.fx = FXContext(rates: .bundled, currency: .cny)
        // 我方语言跟随 -AppleLanguages（英文截图显示 $）；`-UITestLangs en,zh-Hans` 可指定「我方,对方」（P4 UI 测试）
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: UITestMode.langsArgument), i + 1 < args.count {
            let p = args[i + 1].split(separator: ",").map(String.init)
            s.applyLanguages(me: p.first, them: p.count > 1 ? p[1] : nil)
        } else {
            s.applyLanguages(me: AppState.defaultMyLanguage(), them: AppState.defaultMyLanguage() == "id" ? "zh-Hans" : "id")
        }
        if ProcessInfo.processInfo.arguments.contains(UITestMode.seedAmountArgument) {
            Task { await s.conversation.receiveTheirs(UITestMode.seedAmountText) }   // 截图验证金额换算
        }
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
        for l in gate.partnerLanguages { pairs += [(l, myLanguage), (myLanguage, l)] }
        translationToPrepare = pairs
        Task {
            for loc in [Lang.speechLocale(myLanguage)] + gate.partnerLanguages.map(Lang.speechLocale) {
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
        speechAlert = L10n.f("%@还不能离线听", Lang.displayName(target == .me ? myLanguage : theirLanguage))
        return false
    }

    /// v4 V4：单按钮自动判定这一句是谁说的（TripAppModel.TalkRouter，有单测）
    @Published var forcedTalk: TalkTarget?
    @Published var lastVoiceMessageID: UUID?
    var nextTalk: TalkTarget { TalkRouter.predict(messages: conversation.messages, forced: forcedTalk) }
    func toggleNextTalk() { forcedTalk = nextTalk == .me ? .them : .me; tick += 1 }
    /// 「说错人了」：删掉这句，下一次按住改听另一方
    func wrongSpeaker(_ id: UUID) {
        guard let m = conversation.messages.first(where: { $0.id == id }) else { return }
        conversation.remove(id)
        forcedTalk = m.role == .me ? .them : .me
        lastVoiceMessageID = nil
        tick += 1
    }

    func handleTalk(_ outcome: HoldToTalk.Outcome) async {
        switch outcome {
        case .text(let s, let t):
            let who = TalkRouter.resolve(t, text: s, myLanguage: myLanguage, theirLanguage: theirLanguage)
            forcedTalk = nil
            if who == .them { await conversation.receiveTheirs(s) } else { await conversation.sendMine(s) }
            lastVoiceMessageID = conversation.messages.last?.id
        case .failed: speechAlert = L10n.t("需要麦克风和语音识别权限。可在系统设置里打开。")
        default: break
        }
        tick += 1
    }

    func enterBackground() { talk.enterBackground() }

    // MARK: 会话

    func newConversation(deletePrevious: Bool) {
        session = try? sessions.startNew(theirLanguage: conversation.theirLanguage, myLanguage: conversation.myLanguage, deletePrevious: deletePrevious)
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

