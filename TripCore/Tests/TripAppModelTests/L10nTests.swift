import XCTest
@testable import TripAppModel
@testable import TripCore

final class L10nTests: XCTestCase {
    override func tearDown() { L10n.uiLanguage = "zh-Hans" }

    func testChineseIsIdentity() {
        L10n.uiLanguage = "zh-Hans"
        XCTAssertEqual(L10n.t("发送"), "发送")
        XCTAssertEqual(L10n.f("我说%@", "中文"), "我说中文")
    }

    func testEnglishLookupAndFormat() {
        L10n.uiLanguage = "en"
        XCTAssertEqual(L10n.t("没听清，按住再说一次"), "Didn’t catch that — hold and say it again".replacingOccurrences(of: "’", with: "'"))
        XCTAssertEqual(L10n.f("约 %@ 小时 %@ 分钟", "1", "5"), "About 1 h 5 min")
        XCTAssertEqual(L10n.f("下载中 %@%%", "42"), "Downloading 42%")
        XCTAssertEqual(Lang.displayName("id"), "Indonesian")
        XCTAssertEqual(Lang.chineseName("id"), "印尼语", "prompt 用的中文名不随界面语言变")
    }

    func testEveryTableValueHasNoHanAndSameFormatCount() {
        for (k, v) in L10nTable.en {
            XCTAssertFalse(v.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }, k)
            XCTAssertEqual(k.components(separatedBy: "%@").count, v.components(separatedBy: "%@").count, k)
        }
    }

    func testResolve() {
        XCTAssertEqual(L10n.resolve(preferred: ["zh-Hans-CN"], override: nil), "zh-Hans")
        XCTAssertEqual(L10n.resolve(preferred: ["en-US"], override: nil), "en")
        XCTAssertEqual(L10n.resolve(preferred: ["id-ID"], override: nil), "en")
        XCTAssertEqual(L10n.resolve(preferred: ["en-US"], override: "zh-Hans"), "zh-Hans")
    }

    func testEnglishDemoAndMoneyHaveNoChinese() {
        L10n.uiLanguage = "en"
        let han: (String) -> Bool = { $0.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }
        for l in DemoScript.lines { XCTAssertFalse(han(l.source + l.literal + l.understood)) }
        XCTAssertEqual(Money.spoken(50000), "50,000 rupiah")
    }
}
