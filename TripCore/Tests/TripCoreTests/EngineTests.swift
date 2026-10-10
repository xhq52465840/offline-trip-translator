import XCTest
@testable import TripCore

final class EngineTests: XCTestCase {
    let ctx = [ContextTurn(role: .them, source: "ke bandara 200rb", zhDisplay: "去机场20万"), ContextTurn(role: .me, source: "150行吗")]

    func testUnderstanderAcceptsAndRejects() async throws {
        let ok = MockEngine { _ in "17.5万成交\n解释" }
        try await ok.load(modelURL: URL(fileURLWithPath: "/dev/null"))
        let r1 = await Understander(engine: ok).understand(context: ctx, source: "175 deal ya", literal: "175成交好吗")
        XCTAssertEqual(r1, .replaced("17.5万成交"))
        let bad = MockEngine { _ in "175万成交好吗" }
        try await bad.load(modelURL: URL(fileURLWithPath: "/dev/null"))
        let r2 = await Understander(engine: bad).understand(context: ctx, source: "175 deal ya", literal: "175成交好吗")
        XCTAssertEqual(r2, .keepLiteral(reason: "amountMismatch(\"175万\")"))
    }

    func testTimeoutKeepsLiteral() async throws {
        let slow = MockEngine(pieceDelayNanos: 50_000_000) { _ in "早上好呀朋友们" }
        try await slow.load(modelURL: URL(fileURLWithPath: "/dev/null"))
        let r = await Understander(engine: slow, timeout: 0.05).understand(context: [], source: "selamat pagi", literal: "早上好")
        XCTAssertEqual(r, .keepLiteral(reason: "timeoutOrError"))
    }

    func testNotLoadedKeepsLiteral() async {
        let r = await Understander(engine: MockEngine { _ in "x" }).understand(context: [], source: "a", literal: "b")
        XCTAssertEqual(r, .keepLiteral(reason: "timeoutOrError"))
    }

    func testStreamingCancellation() async throws {
        let e = MockEngine(pieceDelayNanos: 1_000_000) { _ in String(repeating: "好", count: 50) }
        try await e.load(modelURL: URL(fileURLWithPath: "/dev/null"))
        var n = 0
        for try await _ in e.generate([], options: .init(maxTokens: 64, stopAtNewline: false)) { n += 1; if n == 3 { break } }
        XCTAssertEqual(n, 3)
    }

    func testPrefixAndMessages() async throws {
        let e = MockEngine { _ in "" }
        let u = Understander(engine: e)
        try await u.warmUp()
        XCTAssertEqual(e.warmedPrefix.first?.role, .system)
        XCTAssertEqual(e.warmedPrefix.count, 5)
        let m = u.builder.messages(context: ctx, source: "175 deal ya", literal: "175成交好吗")
        XCTAssertEqual(Array(m.prefix(5)), e.warmedPrefix, "前缀必须逐字相同才能复用 KV")
        XCTAssertEqual(m.last?.role, .user)
    }

    func testUTF8Accumulator() {
        var a = UTF8Accumulator()
        let bytes = Array("万元".utf8)            // 6 字节
        XCTAssertEqual(a.append(Array(bytes[0..<2])), "")
        XCTAssertEqual(a.append(Array(bytes[2..<4])), "万")
        XCTAssertEqual(a.append(Array(bytes[4..<6])), "元")
        XCTAssertEqual(a.append(Array("ok".utf8)), "ok")
    }
}
