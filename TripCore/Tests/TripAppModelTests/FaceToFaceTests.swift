import XCTest
import TripCore
@testable import TripAppModel

final class FaceToFaceTests: XCTestCase {
    func testMineShowsForeignAndAmountOnTop() {
        var m = Message(id: UUID(), role: .me, createdAt: Date(), source: "4万行吗？", sourceLocale: "zh-Hans")
        m.foreign = "Rp 40.000 boleh?"; m.status = .ready
        let c = FaceToFaceContent.make(messages: [m], myLanguage: "zh-Hans", theirLanguage: "id")
        XCTAssertEqual(c.partnerText, "Rp 40.000 boleh?")
        XCTAssertEqual(c.partnerAmounts, ["Rp 40.000"])
        XCTAssertEqual(c.partnerLabel, "Dia bilang:")
        XCTAssertEqual(c.myText, "4万行吗？")
    }
    func testTheirsEchoesSourceOnTop() {
        var t = Message(id: UUID(), role: .them, createdAt: Date(), source: "50rb belum termasuk ongkos", sourceLocale: "id")
        t.display = "5万，不含运费"; t.status = .ready
        let c = FaceToFaceContent.make(messages: [t], myLanguage: "zh-Hans", theirLanguage: "id")
        XCTAssertEqual(c.partnerText, "50rb belum termasuk ongkos")
        XCTAssertEqual(c.partnerAmounts, ["Rp 50.000"])
        XCTAssertEqual(c.partnerLabel, "Anda bilang:")
        XCTAssertEqual(c.myText, "5万，不含运费")
    }
    func testEmpty() {
        let c = FaceToFaceContent.make(messages: [], myLanguage: "zh-Hans", theirLanguage: "en")
        XCTAssertNil(c.partnerText)
        XCTAssertEqual(FaceToFaceContent.partnerEmpty(lang: "en"), "Please speak")
    }
}
