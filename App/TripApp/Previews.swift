import SwiftUI
import TripCore
import TripAppModel

/// 预览 / UI 测试用：MockEngine + 假翻译 + 假语言包状态，不需要下载。
final class PreviewTranslator: Translating {
    func translate(_ text: String, from: String, to: String) async throws -> String {
        let table = ["⟦N1⟧ belum termasuk ongkos": "⟦N1⟧还没有包括费用", "太贵了": "Terlalu mahal", "Terlalu mahal": "太贵了"]
        return table[text] ?? "（示例）\(text)"
    }
}

final class PreviewProbe: LanguagePackProbing {
    func translationStatus(from: String, to: String) async -> PackStatus { .installed }
    func speechReadiness(locale: String) async -> Readiness { .ready }
}

struct PreviewSpeechInstaller: SpeechAssetInstalling { func install(locale: String) async throws {} }

extension AppState {
    static func preview() -> AppState {
        let engine = MockEngine(pieceDelayNanos: 20_000_000) { _ in "5万，不含车费" }
        Task { try? await engine.load(modelURL: URL(fileURLWithPath: "/dev/null")) }
        let s = AppState(tier: .a8GB, probe: PreviewProbe(), translator: PreviewTranslator(), engine: engine,
                         downloader: nil, env: SystemDownloadEnvironment(network: .wifi), speechInstaller: PreviewSpeechInstaller(),
                         transcriber: PreviewTranscriber(),
                         sessions: SessionStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("preview-sessions")))
        Task { await s.conversation.receiveTheirs("50rb belum termasuk ongkos"); await s.conversation.sendMine("太贵了") }
        return s
    }
}

extension Message {
    static var previewTheirs: Message {
        var m = Message(id: UUID(), role: .them, createdAt: Date(), source: "50rb belum termasuk ongkos", sourceLocale: "id")
        m.literal = "5万还没有包括费用"; m.display = "5万，不含车费"; m.understood = true; m.status = .ready
        return m
    }
    static var previewMine: Message {
        var m = Message(id: UUID(), role: .me, createdAt: Date(), source: "太贵了", sourceLocale: "zh-Hans")
        m.foreign = "Terlalu mahal"; m.status = .ready
        return m
    }
}

final class PreviewTranscriber: Transcribing {
    func start(locale: String) async throws {}
    func finish() async -> String { "bisa kurang sedikit?" }
    func cancel() {}
}
