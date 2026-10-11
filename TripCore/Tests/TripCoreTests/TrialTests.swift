import XCTest
@testable import TripCore

final class FakeTime: TrialTimeSource, @unchecked Sendable {
    var w = Date(timeIntervalSince1970: 1_000_000); var u: TimeInterval = 100
    func wall() -> Date { w }
    func uptime() -> TimeInterval { u }
    func pass(_ s: TimeInterval) { w += s; u += s }
}

final class TrialTests: XCTestCase {
    func testStartsOnFirstTranslatedMessageNotInstall() {
        let t = FakeTime(); let c = TrialCounter(store: InMemoryTrialStore(), time: t)
        XCTAssertEqual(c.state, .notStarted); XCTAssertTrue(c.allowsFull)
        t.pass(10 * 86400)                                   // 下载后放了 10 天
        XCTAssertEqual(c.state, .notStarted, "安装/下载不计时")
        c.recordCompleteTurn()
        XCTAssertEqual(c.remainingHours, 24)
        t.pass(3600 * 5); c.recordCompleteTurn()             // 再次调用不重置
        XCTAssertEqual(c.remainingHours, 19)
        t.pass(3600 * 19); XCTAssertEqual(c.state, .expired); XCTAssertFalse(c.allowsFull); XCTAssertEqual(c.remainingHours, 0)
    }

    func testClockSetBackDoesNotRefund() {
        let t = FakeTime(); let s = InMemoryTrialStore(); let c = TrialCounter(store: s, time: t)
        c.recordCompleteTurn(); t.pass(3600 * 10); _ = c.state
        t.w -= 3600 * 48; t.u += 3600                         // 把系统时间往回拨两天，真实过了 1 小时
        XCTAssertEqual(c.remainingHours, 13, "墙钟倒退时按单调时钟计")
        t.pass(3600); XCTAssertEqual(c.remainingHours, 12)
    }

    func testRebootAndClockBack() {
        let t = FakeTime(); let s = InMemoryTrialStore(); let c = TrialCounter(store: s, time: t)
        c.recordCompleteTurn(); t.pass(3600 * 20); _ = c.state
        t.u = 5; t.w -= 3600 * 30                              // 重启 + 回拨
        XCTAssertEqual(c.remainingHours, 4, "已用时间不会减少")
        t.u = 3605; t.w += 3600; XCTAssertEqual(c.remainingHours, 3)
    }

    func testForwardJumpConsumes() {
        let t = FakeTime(); let c = TrialCounter(store: InMemoryTrialStore(), time: t)
        c.recordCompleteTurn(); t.w += 86400                   // 往前拨只会让试用提前结束
        XCTAssertEqual(c.state, .expired)
    }

    func testUnlocked() {
        let c = TrialCounter(store: InMemoryTrialStore.expired(), time: FakeTime())
        XCTAssertFalse(c.allowsFull); c.unlocked = true
        XCTAssertEqual(c.state, .unlocked); XCTAssertTrue(c.allowsFull); XCTAssertNil(c.remainingHours)
    }

    func testRecordRoundTrip() throws {
        let r = TrialRecord(startedAt: Date(timeIntervalSince1970: 5), consumed: 12, lastWall: Date(timeIntervalSince1970: 9), lastUptime: 3)
        XCTAssertEqual(try JSONDecoder().decode(TrialRecord.self, from: JSONEncoder().encode(r)), r)
    }

    func testEntitlementResolver() {
        typealias T = EntitlementResolver.Txn
        let d0 = Date(timeIntervalSince1970: 0), day: TimeInterval = 86400
        XCTAssertEqual(EntitlementResolver.resolve([], now: d0), .none)
        XCTAssertEqual(EntitlementResolver.resolve([T(productID: "pass.trip30", purchaseDate: d0)], now: d0 + day), .passUntil(d0 + 30 * day))
        XCTAssertEqual(EntitlementResolver.resolve([T(productID: "pass.trip30", purchaseDate: d0)], now: d0 + 31 * day), .none)
        XCTAssertEqual(EntitlementResolver.resolve([T(productID: "pass.trip30", purchaseDate: d0), T(productID: "pass.trip30", purchaseDate: d0 + 10 * day)], now: d0 + 40 * day),
                       .passUntil(d0 + 60 * day), "提前续买顺延")
        XCTAssertEqual(EntitlementResolver.resolve([T(productID: "pass.trip30", purchaseDate: d0), T(productID: "unlock.lifetime", purchaseDate: d0 + day)], now: d0 + 99 * day), .lifetime)
        XCTAssertEqual(EntitlementResolver.resolve([T(productID: "unlock.lifetime", purchaseDate: d0, revoked: true)], now: d0), .none)
        XCTAssertEqual(PurchaseProduct.tripPass.proposedPriceCNY, 18); XCTAssertEqual(PurchaseProduct.lifetime.proposedPriceCNY, 48)
    }
}
