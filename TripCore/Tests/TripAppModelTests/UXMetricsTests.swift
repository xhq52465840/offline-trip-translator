import XCTest
@testable import TripAppModel

final class UXMetricsTests: XCTestCase {
    func make() -> UXMetrics {
        let s = "uxm.test.\(UUID().uuidString)"; return UXMetrics(defaults: UserDefaults(suiteName: s)!)
    }
    func testCountsAndRates() {
        let m = make()
        XCTAssertNil(m.wrongSpeakerRate)
        for _ in 0..<10 { m.record(.voiceTurn) }
        m.record(.wrongSpeaker)
        XCTAssertEqual(m.wrongSpeakerRate!, 0.1, accuracy: 1e-9)
        XCTAssertTrue(m.summary.contains("voiceTurn=10"))
    }
    func testFirstTranslationNeedsLaunchAndIsSticky() {
        let m = make(); let t0 = Date(timeIntervalSince1970: 1000)
        m.markFirstTranslation(t0); XCTAssertNil(m.firstTranslationAt)
        m.markFirstLaunch(t0); m.markFirstTranslation(t0.addingTimeInterval(21)); m.markFirstTranslation(t0.addingTimeInterval(99))
        XCTAssertEqual(m.secondsToFirstTranslation, 21)
    }
    func testStartersTrilingual() {
        XCTAssertEqual(ContextReplies.starters.count, 3)
        for p in ContextReplies.starters { XCTAssertFalse(p.id_.isEmpty); XCTAssertFalse(p.en.isEmpty) }
    }
}
