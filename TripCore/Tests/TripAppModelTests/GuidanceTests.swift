import XCTest
import TripCore
@testable import TripAppModel

final class GuidanceTests: XCTestCase {
    func testETAAssumedThenMeasured() {
        var e = DownloadETA()
        XCTAssertEqual(e.text(remaining: 1_117_320_736), "Wi‑Fi 下约 4 分钟")          // 1.1GB / 5MB/s ≈ 3.7 分
        let t0 = Date(timeIntervalSince1970: 0)
        for k in 0...10 { e.record(bytes: Int64(k) * 1_000_000, at: t0.addingTimeInterval(Double(k))) }   // 1 MB/s
        XCTAssertEqual(e.measuredBytesPerSecond ?? 0, 1_000_000, accuracy: 1)
        XCTAssertEqual(e.text(remaining: 1_100_000_000), "还要约 19 分钟")
        XCTAssertEqual(e.text(remaining: 5_000_000_000), "还要约 1 小时 24 分钟")
        e.record(bytes: 0, at: t0.addingTimeInterval(11))                                // 重下
        XCTAssertNil(e.measuredBytesPerSecond)
    }
    func testETASlow() {
        var e = DownloadETA(); let t0 = Date(timeIntervalSince1970: 0)
        e.record(bytes: 0, at: t0); e.record(bytes: 100, at: t0.addingTimeInterval(5))
        XCTAssertEqual(e.text(remaining: 1_000_000), "网速很慢，建议换个 Wi‑Fi")
        XCTAssertEqual(DownloadETA.minutes(remaining: 1, bytesPerSecond: 1_000_000), 1)
    }
    func testDownloadAdviceCopy() {
        XCTAssertTrue(Copy.downloadAdvice(eta: "Wi‑Fi 下约 4 分钟").contains("出发前在家"))
        XCTAssertTrue(Copy.downloadAdvice(eta: nil).hasSuffix("后台继续。"))
        XCTAssertTrue(Copy.amountTrust.contains("不靠 AI 猜"))
    }
    func testRecentScenes() throws {
        var r = RecentScenes()
        XCTAssertEqual(r.ordered(), Scenario.allCases)
        r.use(.restaurant); r.use(.ride); r.use(.restaurant)
        XCTAssertEqual(Array(r.ordered().prefix(2)), [.restaurant, .ride])
        XCTAssertEqual(r.ordered().count, Scenario.allCases.count)
        for s in Scenario.allCases { r.use(s) }
        XCTAssertEqual(r.recent.count, 6)
        let back = try JSONDecoder().decode(RecentScenes.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back, r)
    }
    func testCopyHint() {
        XCTAssertTrue(CopyHint.text(scene: .ride).contains("Grab"))
        XCTAssertTrue(CopyHint.text(scene: .delivery).contains("外卖"))
        XCTAssertEqual(CopyHint.text(scene: nil), "已复制，可以粘贴到聊天里发送")
    }
    func testPresentAmountLine() {
        XCTAssertEqual(PresentContent.amountLine(foreign: "Harganya 50rb, boleh?", source: "5万可以吗"), "Rp 50.000")
        XCTAssertEqual(PresentContent.amountLine(foreign: "Sekitar Rp 30-40 ribu", source: ""), "Rp 30.000 · Rp 40.000")
        XCTAssertNil(PresentContent.amountLine(foreign: "Terima kasih", source: "谢谢"))
    }
}
