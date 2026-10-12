import SwiftUI
import Network
import Speech
import TripCore
import TripAppModel
#if canImport(Translation)
import Translation
#endif

// MARK: - 语言包状态（Translation：LanguageAvailability.status(from:to:)，iOS 18+）

final class SystemPackProbe: LanguagePackProbing {
    func translationStatus(from: String, to: String) async -> PackStatus {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            let s = await LanguageAvailability().status(from: Locale.Language(identifier: from), to: Locale.Language(identifier: to))
            switch s {
            case .installed: return .installed
            case .supported: return .supported
            case .unsupported: return .unsupported
            @unknown default: return .unsupported
            }
        }
        #endif
        return .unsupported
    }

    func speechReadiness(locale: String) async -> Readiness {
        let loc = Locale(identifier: locale)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let installed = await SpeechTranscriber.installedLocales
            if installed.contains(where: { $0.identifier(.bcp47) == loc.identifier(.bcp47) }) { return .ready }
            let supported = await SpeechTranscriber.supportedLocales
            if supported.contains(where: { $0.identifier(.bcp47) == loc.identifier(.bcp47) }) { return .needsDownload(bytes: nil) }
        }
        #endif
        if let r = SFSpeechRecognizer(locale: loc), r.supportsOnDeviceRecognition { return .ready }
        // 只有对方语言听写可以是「暂不可用」；中文听写缺失视为需要下载（由 AppGate 阻断）
        return locale.hasPrefix("zh") ? .needsDownload(bytes: nil) : .unavailable("听\(Lang.displayName(String(locale.prefix(2))))暂不可用")
    }
}

// MARK: - 听写资源下载（AssetInventory，iOS 26+）

protocol SpeechAssetInstalling { func install(locale: String) async throws }

final class SystemSpeechInstaller: SpeechAssetInstalling {
    func install(locale: String) async throws {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let t = SpeechTranscriber(locale: Locale(identifier: locale), preset: .transcription)
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
                try await req.downloadAndInstall()
            }
        }
        #endif
    }
}

// MARK: - 系统翻译

/// iOS 26+：TranslationSession(installedSource:target:) 可在视图外直接创建（只用已安装的语言包，不联网）。
/// iOS 18–25：需要通过 .translationTask 拿 session，这里由 TranslationBridge 提供。
final class SystemTranslator: Translating {
    func translate(_ text: String, from: String, to: String) async throws -> String {
        #if canImport(Translation)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let s = TranslationSession(installedSource: Locale.Language(identifier: from), target: Locale.Language(identifier: to))
            return try await s.translate(text).targetText
        }
        #endif
        if #available(iOS 18.0, *) {
            return try await TranslationBridge.shared.translate(text, from: from, to: to)
        }
        #endif
        throw CocoaError(.featureUnsupported)
    }
}

#if canImport(Translation)
@available(iOS 18.0, *)
@MainActor
final class TranslationBridge: ObservableObject {
    static let shared = TranslationBridge()
    @Published var configuration: TranslationSession.Configuration?
    private var pending: [(text: String, cont: CheckedContinuation<String, Error>)] = []

    nonisolated func translate(_ text: String, from: String, to: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            Task { @MainActor in
                self.pending.append((text, cont))
                let cfg = TranslationSession.Configuration(source: Locale.Language(identifier: from), target: Locale.Language(identifier: to))
                if self.configuration?.source == cfg.source && self.configuration?.target == cfg.target {
                    self.configuration?.invalidate()
                } else {
                    self.configuration = cfg
                }
            }
        }
    }

    func run(_ session: TranslationSession) async {
        let jobs = pending; pending = []
        for j in jobs {
            do { j.cont.resume(returning: try await session.translate(j.text).targetText) }
            catch { j.cont.resume(throwing: error) }
        }
    }
}
#endif

/// 宿主修饰器：
/// 1) 准备阶段对每个语言对调用 prepareTranslation()（系统会弹出自己的下载确认）；
/// 2) iOS 18–25 的翻译请求通过 translationTask 执行。
struct TranslationPrepareHost: ViewModifier {
    @ObservedObject var state: AppState

    func body(content: Content) -> some View {
        #if canImport(Translation)
        if #available(iOS 18.0, *) {
            content
                .background(PrepareRunner(state: state))
                .background(BridgeRunner(bridge: TranslationBridge.shared))
        } else { content }
        #else
        content
        #endif
    }
}

#if canImport(Translation)
@available(iOS 18.0, *)
private struct PrepareRunner: View {
    @ObservedObject var state: AppState
    @State private var config: TranslationSession.Configuration?
    var body: some View {
        Color.clear
            .onChange(of: state.translationToPrepare.count) { _, _ in next() }
            .translationTask(config) { session in
                do { try await session.prepareTranslation() } catch { }
                await MainActor.run {
                    if !state.translationToPrepare.isEmpty { state.translationToPrepare.removeFirst() }
                    next()
                }
                await state.refresh(.downloadFinished)
            }
    }
    private func next() {
        guard let p = state.translationToPrepare.first else { config = nil; return }
        config = TranslationSession.Configuration(source: Locale.Language(identifier: p.0), target: Locale.Language(identifier: p.1))
    }
}

@available(iOS 18.0, *)
private struct BridgeRunner: View {
    @ObservedObject var bridge: TranslationBridge
    var body: some View {
        Color.clear.translationTask(bridge.configuration) { session in await bridge.run(session) }
    }
}
#endif

extension View {
    func translationPrepareHost(state: AppState) -> some View { modifier(TranslationPrepareHost(state: state)) }
}

// MARK: - 网络类型（NWPathMonitor，只用于下载策略）

final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    var onChange: ((NetworkKind) -> Void)?
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: NetworkKind = path.status != .satisfied ? .none : (path.isExpensive || path.usesInterfaceType(.cellular) ? .cellular : .wifi)
            DispatchQueue.main.async { self?.onChange?(kind) }
        }
        monitor.start(queue: DispatchQueue(label: "net"))
    }
}
