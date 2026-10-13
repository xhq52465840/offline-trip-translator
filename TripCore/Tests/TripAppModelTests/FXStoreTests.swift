import XCTest
import TripCore
@testable import TripAppModel

final class FXStoreTests: XCTestCase {
    func defaults() -> UserDefaults { UserDefaults(suiteName: "fx-\(UUID())")! }
    let d0 = ISO8601DateFormatter().date(from: "2026-10-13T02:00:00Z")!

    func testStaleWarning() {
        let fx = FXContext(rates: .bundled, currency: .cny)
        XCTAssertFalse(fx.isStale(now: d0)); XCTAssertEqual(fx.caption(now: d0), "汇率 2026-10-12，换算为约值")
        let later = d0.addingTimeInterval(40 * 86_400)
        XCTAssertTrue(fx.isStale(now: later)); XCTAssertTrue(fx.caption(now: later).contains("超过 30 天"))
        XCTAssertTrue(FXContext(rates: .bundled, currency: .usd).caption(now: later).contains("older than 30 days"))
    }

    func testRefreshAcceptsSaneRejectsWild() async {
        let s = FXStore(defaults: defaults())
        XCTAssertEqual(s.current, .bundled)
        let skipped = await s.refresh(now: d0, online: false) { _ in Data() }; XCTAssertEqual(skipped, .skipped)
        let ok = Data(#"{"base":"USD","date":"2026-10-20","rates":{"CNY":6.70,"IDR":18000}}"#.utf8)
        let r = await s.refresh(now: d0, online: true) { _ in ok }
        if case .updated(let x) = r { XCTAssertEqual(x.date, "2026-10-20") } else { XCTFail("\(r)") }
        XCTAssertEqual(s.current.date, "2026-10-20")
        let again = await s.refresh(now: d0.addingTimeInterval(3600), online: true) { _ in ok }; XCTAssertEqual(again, .skipped, "6 小时内不重复")
        let wild = Data(#"{"base":"USD","date":"2026-10-21","rates":{"CNY":6.70,"IDR":1800}}"#.utf8)
        let rej = await s.refresh(now: d0.addingTimeInterval(7 * 3600), online: true) { _ in wild }
        XCTAssertEqual(rej, .rejected); XCTAssertEqual(s.current.date, "2026-10-20", "被拒后保留旧值")
        struct E: Error {}
        let f = await s.refresh(now: d0.addingTimeInterval(14 * 3600), online: true) { _ in throw E() }; XCTAssertEqual(f, .failed)
    }

    @MainActor func testTranscriptAnnotatesForMeOnly() async {
        let tr = FakeAmountTranslator()
        let m = ConversationModel(translator: tr, understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        await m.receiveTheirs("Harganya Rp 100.000 kak")
        await m.sendMine("最多给200块")
        let fx = FXContext(rates: .bundled, currency: .cny)
        let me = Transcript.rows(m.messages, viewer: .me, rate: nil, fx: fx)
        XCTAssertTrue(me[0].primary.contains("（约 ¥37）"), me[0].primary)
        XCTAssertTrue(me[0].secondary!.contains("Rp 100.000（约 ¥37）"))
        XCTAssertEqual(me[0].chips.first?.cny, "约 ¥37")
        XCTAssertTrue(me[1].note?.contains("¥200≈Rp 536.000") ?? false, "\(String(describing: me[1].note))")
        let partner = Transcript.rows(m.messages, viewer: .partner, rate: nil, fx: fx)
        XCTAssertFalse(partner.map(\.primary).joined().contains("¥"), "对方看到的不加人民币")
        let usd = Transcript.rows(m.messages, viewer: .me, rate: nil, fx: FXContext(rates: .bundled, currency: .usd))
        XCTAssertTrue(usd[0].secondary!.contains("（≈ $5.6）"))
    }
}

final class FakeAmountTranslator: Translating {
    func translate(_ text: String, from: String, to: String) async throws -> String {
        if text.contains("⟦N1⟧") { return "价格是⟦N1⟧" }
        if text.contains("200") { return "Maksimal 200 yuan" }
        return text
    }
}
