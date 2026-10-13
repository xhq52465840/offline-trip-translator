import XCTest
import TripCore
@testable import TripAppModel

@MainActor
final class UITestModeTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(UITestMode.from(arguments: ["app", "-UITestMode", "mock-ready"], environment: [:]), .mockReady)
        XCTAssertEqual(UITestMode.from(arguments: ["app"], environment: ["UITEST_MODE": "mock-not-ready"]), .mockNotReady)
        XCTAssertNil(UITestMode.from(arguments: ["app", "-UITestMode"], environment: [:]))
        XCTAssertNil(UITestMode.from(arguments: ["app", "-UITestMode", "bogus"], environment: [:]))
        XCTAssertNil(UITestMode.from(arguments: ["app"], environment: [:]))
    }

    func gate(_ m: UITestMode) -> AppGate {
        let d = UserDefaults(suiteName: "uitest-\(UUID())")!
        let g = AppGate(tier: .a8GB, probe: UITestProbe(mode: m), modelReadiness: { m.modelReadiness }, defaults: d)
        g.onboardingCompleted = m.onboardingCompleted
        return g
    }

    func testGateDecisions() async {
        let r = await gate(.mockReady).refresh(.coldLaunch); XCTAssertEqual(r, .open)
        let n = await gate(.mockNotReady).refresh(.coldLaunch)
        if case .block(let miss) = n { XCTAssertTrue(miss.contains(.understander)) } else { XCTFail("\(n)") }
        let f = await gate(.mockNotReady).refresh(.foreground)
        if case .block = f {} else { XCTFail("回前台也要阻断") }
        let o = await gate(.mockOnboarding).refresh(.coldLaunch); XCTAssertEqual(o, .onboarding)
    }

    func testFakeTranslationAndChat() async {
        let m = ConversationModel(translator: UITestTranslator(), understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        await m.sendMine("太贵了")
        XCTAssertEqual(m.messages.last?.foreign, "Terlalu mahal")
        XCTAssertEqual(UITestMode.fakeTranslate("xyz"), "〔mock〕xyz")
    }
}

@MainActor
final class UITestSeedAmountTests: XCTestCase {
    func testSeedShowsConversion() async {
        let m = ConversationModel(translator: UITestTranslator(), understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        await m.receiveTheirs(UITestMode.seedAmountText)
        let rows = Transcript.rows(m.messages, viewer: .me, rate: nil, fx: FXContext(rates: .bundled, currency: .cny))
        XCTAssertEqual(rows[0].primary, "价格是10万（约 ¥37）")
        XCTAssertTrue(rows[0].secondary!.contains("Rp 100.000（约 ¥37）"))
    }
}
