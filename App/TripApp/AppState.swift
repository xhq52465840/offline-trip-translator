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

    var isBlocking: Bool { if case .block = decision { return !showPrepare } else { return false } }
    var missingText: String { if case .block(let m) = decision { return AppGate.missingText(m) } else { return "" } }

    init(tier: DeviceTier, probe: LanguagePackProbing, translator: Translating, engine: LLMEngine,
         downloader: ModelDownloader?, env: SystemDownloadEnvironment, speechInstaller: SpeechAssetInstalling,
         transcriber: Transcribing, sessions: SessionStore) {
        self.probe = probe; self.engine = engine; self.downloader = downloader; self.env = env; self.speechInstaller = speechInstaller
        let dl = downloader
        gate = AppGate(tier: tier, probe: probe, modelReadiness: { dl?.readiness ?? .unavailable("没有适合这台手机的理解能力") })
        let store: TrialStore
        #if canImport(Security)
        store = KeychainTrialStore()
        #else
        store = InMemoryTrialStore()
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

