import XCTest
@testable import TripAppModel
@testable import TripCore

final class StatusProbe: LanguagePackProbing {
    var status: PackStatus
    init(_ s: PackStatus) { status = s }
    func translationStatus(from: String, to: String) async -> PackStatus { status }
    func speechReadiness(locale: String) async -> Readiness { .ready }
}
final class ThrowingTranslator: Translating {
    var calls = 0
    func translate(_ text: String, from: String, to: String) async throws -> String { calls += 1; throw CocoaError(.featureUnsupported) }
}
final class EchoTranslator: Translating {
    func translate(_ text: String, from: String, to: String) async throws -> String { "apple:" + text }
}

final class FallbackTests: XCTestCase {
    func engine(_ out: String) async throws -> MockEngine {
        let e = MockEngine { _ in out }; try await e.load(modelURL: URL(fileURLWithPath: "/dev/null")); return e
    }

    func testUnsupportedPackUsesLocalModelWithoutTryingApple() async throws {
        let apple = ThrowingTranslator()
        let t = FallbackTranslator(primary: apple, fallback: LocalModelTranslator(engine: try await engine("价格是⟦A1⟧\n多余")), probe: StatusProbe(.unsupported))
        let r = try await t.translate("harganya ⟦A1⟧", from: "id", to: "zh-Hans")
        XCTAssertEqual(r, "价格是⟦A1⟧"); XCTAssertEqual(apple.calls, 0); XCTAssertEqual(t.usedFallback["id>zh-Hans"], true)
    }

    func testInstalledPackUsesApple() async throws {
        let t = FallbackTranslator(primary: EchoTranslator(), fallback: LocalModelTranslator(engine: try await engine("x")), probe: StatusProbe(.installed))
        let r = try await t.translate("halo", from: "id", to: "en")
        XCTAssertEqual(r, "apple:halo"); XCTAssertEqual(t.usedFallback["id>en"], false)
    }

    func testAppleErrorFallsBackAndModelNotLoadedRethrows() async throws {
        let t = FallbackTranslator(primary: ThrowingTranslator(), fallback: LocalModelTranslator(engine: try await engine("Hello")), probe: StatusProbe(.supported))
        let r = try await t.translate("halo", from: "id", to: "en")
        XCTAssertEqual(r, "Hello")
        let cold = FallbackTranslator(primary: ThrowingTranslator(), fallback: LocalModelTranslator(engine: MockEngine { _ in "x" }), probe: StatusProbe(.unsupported))
        do { _ = try await cold.translate("halo", from: "id", to: "en"); XCTFail("应抛错") } catch {}
    }

    func testPromptsMatchTrainingReplay() {
        XCTAssertEqual(LocalModelTranslator.messages("x", from: "id", to: "zh-Hans")[1].content, "把下面的印尼语翻译成简体中文：\nx")
        XCTAssertEqual(LocalModelTranslator.messages("x", from: "id", to: "en")[1].content, "Translate the following Indonesian into English:\nx")
    }

    func testUnsupportedTranslationDoesNotBlockGate() {
        let st = PrepareStatus(items: [.touristSpeech: .ready, .understander: .ready, .translation("id"): .unavailable("x"), .translation("en"): .ready])
        XCTAssertTrue(st.isComplete)
        let st2 = PrepareStatus(items: [.touristSpeech: .ready, .understander: .ready, .translation("id"): .needsDownload(bytes: nil)])
        XCTAssertFalse(st2.isComplete)
    }
}

final class LangProbe: LanguagePackProbing {
    var unsupported: Set<String>
    init(unsupported: Set<String>) { self.unsupported = unsupported }
    func translationStatus(from: String, to: String) async -> PackStatus { unsupported.contains(from) || unsupported.contains(to) ? .unsupported : .installed }
    func speechReadiness(locale: String) async -> Readiness { .ready }
}

@MainActor
final class FallbackMarkAndGateTests: XCTestCase {
    func testFallbackBubbleIsMarkedLowQuality() async throws {
        let e = MockEngine { _ in "价格是⟦A1⟧" }; try await e.load(modelURL: URL(fileURLWithPath: "/dev/null"))
        let t = FallbackTranslator(primary: ThrowingTranslator(), fallback: LocalModelTranslator(engine: e), probe: LangProbe(unsupported: ["id"]))
        let m = ConversationModel(translator: t, understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        await m.receiveTheirs("harganya 50rb")
        XCTAssertEqual(m.messages[0].lowQuality, true)
        let rows = Transcript.rows(m.messages, viewer: .me, rate: nil)
        XCTAssertTrue(rows[0].note?.contains("本机模型翻译") == true, rows[0].note ?? "nil")
        L10n.uiLanguage = "en"; defer { L10n.uiLanguage = "zh-Hans" }
        XCTAssertTrue(Transcript.rows(m.messages, viewer: .me, rate: nil)[0].note?.contains("on-device model") == true)
    }

    func testAppleBubbleNotMarked() async throws {
        let t = FallbackTranslator(primary: EchoTranslator(), fallback: ThrowingTranslator(), probe: LangProbe(unsupported: []))
        let m = ConversationModel(translator: t, understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        await m.receiveTheirs("halo")
        XCTAssertNil(m.messages[0].lowQuality)
        XCTAssertNil(Transcript.rows(m.messages, viewer: .me, rate: nil)[0].note)
    }

    func testGateChecksOnlyLanguagesInUse() async {
        // 我方中文、对方印尼语：英语包没有也不影响
        final class P: LanguagePackProbing {
            func translationStatus(from: String, to: String) async -> PackStatus { (from == "en" || to == "en") ? .supported : .installed }
            func speechReadiness(locale: String) async -> Readiness { .ready }
        }
        let g = AppGate(tier: .a8GB, theirLanguages: ["id"], probe: P(), modelReadiness: { .ready }, defaults: UserDefaults(suiteName: "g3-\(UUID())")!)
        g.myLanguage = "zh-Hans"
        let d = await g.refresh(.coldLaunch)
        XCTAssertEqual(d, .open)
        XCTAssertNil(g.status.items[.translation("en")])
        g.theirLanguages = ["en"]
        let d2 = await g.refresh(.foreground)
        XCTAssertNotEqual(d2, .open, "换成英语后才要求英语包")
    }
}
