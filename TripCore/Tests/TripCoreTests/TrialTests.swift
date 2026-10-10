import XCTest
@testable import TripCore

final class TrialTests: XCTestCase {
    func testTrialFlow() {
        let c = TrialCounter(store: InMemoryTrialStore())
        XCTAssertEqual(c.state, .trial(remaining: 30)); XCTAssertNil(c.bannerRemaining)
        for _ in 0..<25 { c.recordCompleteTurn() }
        XCTAssertEqual(c.bannerRemaining, 5)
        for _ in 0..<10 { c.recordCompleteTurn() }
        XCTAssertEqual(c.used, 30); XCTAssertFalse(c.allowsFull); XCTAssertEqual(c.bannerRemaining, 0)
        c.unlocked = true
        XCTAssertTrue(c.allowsFull); XCTAssertEqual(c.state, .unlocked); XCTAssertNil(c.bannerRemaining)
        c.recordCompleteTurn(); XCTAssertEqual(c.used, 30)
        c.unlocked = false // 退款撤销：used 保留
        XCTAssertEqual(c.state, .trial(remaining: 0))
    }

    func testMetricsDefaultOnAndToggle() {
        let d = UserDefaults(suiteName: "test-\(UUID())")!
        let m = MetricsSettings(defaults: d)
        XCTAssertTrue(m.enabled)
        m.increment("present"); XCTAssertEqual(m.counters["present"], 1)
        m.enabled = false
        XCTAssertTrue(m.counters.isEmpty); m.increment("present"); XCTAssertTrue(m.counters.isEmpty)
        XCTAssertFalse(MetricsSettings(defaults: d).enabled)
    }
}
