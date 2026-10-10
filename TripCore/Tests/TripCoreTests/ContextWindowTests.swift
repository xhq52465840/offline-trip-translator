import XCTest
@testable import TripCore

final class ContextWindowTests: XCTestCase {
    func turns(_ n: Int) -> [ContextTurn] {
        (0..<n).map { i in i % 2 == 0 ? ContextTurn(role: .them, source: "harga \(i)0rb", zhDisplay: "价格\(i)万") : ContextTurn(role: .me, source: "太贵了\(i)", foreign: "Terlalu mahal \(i)") }
    }
    func testShortConversationPassesWholeSession() {
        let r = ContextWindow(maxTurns: 8).build(turns(8))
        XCTAssertNil(r.summary); XCTAssertEqual(r.recent.count, 8)
    }
    func testLongConversationSlidingWindowWithSummary() {
        let r = ContextWindow(maxTurns: 6).build(turns(20))
        XCTAssertEqual(r.recent.count, 5)
        XCTAssertEqual(r.recent.last?.source, "太贵了19")
        let s = r.summary ?? ""
        XCTAssertTrue(s.contains("开头对方说「价格0万」"), s)
        XCTAssertTrue(s.contains("提到过的金额"), s)
        XCTAssertTrue(s.contains("共省略 15 条"), s)
        XCTAssertLessThanOrEqual(s.count, 120)
    }
    func testPromptIncludesSceneSummaryAndBothLanguages() {
        var b = PromptBuilder(maxContextTurns: 4); b.scene = "打车（Grab/Gojek 司机）"
        let u = b.user(context: turns(9), source: "otw 5 mnt", literal: "otw 5 mnt", glossary: [])
        XCTAssertTrue(u.contains("场景：打车"))
        XCTAssertTrue(u.contains("前情摘要："))
        XCTAssertTrue(u.contains("对方看到：Terlalu mahal"), u)
        let short = PromptBuilder().user(context: turns(2), source: "a", literal: "a", glossary: [])
        XCTAssertFalse(short.contains("前情摘要")); XCTAssertFalse(short.contains("场景："))
    }
}
