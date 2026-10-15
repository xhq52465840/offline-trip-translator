import XCTest
import TripCore
@testable import TripAppModel

final class MoneyCardTests: XCTestCase {
    override func tearDown() { L10n.uiLanguage = "zh-Hans" }
    let fx = FXContext(rates: .bundled, currency: .cny)

    func testNoAmountNoCard() {
        XCTAssertNil(MoneyCard.make(chips: Money.chips(in: "Pak, saya sudah di lobi", fx: fx), source: "Pak, saya sudah di lobi", fromPartner: true))
    }
    func testFiftyRbExclShipping() {
        let src = "50rb belum termasuk ongkos"
        let c = MoneyCard.make(chips: Money.chips(in: src, fx: fx), source: src, fromPartner: true)!
        XCTAssertEqual(c.lines.map(\.idr), [50_000])
        XCTAssertEqual(c.lines[0].rupiah, "Rp 50.000")
        XCTAssertEqual(c.conditions, ["不含运费"])
        XCTAssertTrue(c.detail(for: c.lines[0]).contains("5万印尼盾"))
        XCTAssertTrue(c.accessibilityText.hasPrefix("对方报价"))
        XCTAssertNotNil(c.lines[0].cny)
    }
    func testInclVsExclNotBoth() {
        XCTAssertEqual(MoneyCard.conditions(in: "sudah termasuk ongkir"), ["含运费"])
        XCTAssertEqual(MoneyCard.conditions(in: "belum termasuk ongkir ya"), ["不含运费"])
    }
    func testMultipleAmountsAndPerPerson() {
        let src = "Rp 150.000 per orang, anak 75rb"
        let c = MoneyCard.make(chips: Money.chips(in: src, fx: fx), source: src, fromPartner: true)!
        XCTAssertEqual(c.lines.map(\.idr), [150_000, 75_000])
        XCTAssertEqual(c.conditions, ["每人"])
    }
    func testEnglishUI() {
        L10n.uiLanguage = "en"
        let src = "50rb belum termasuk ongkos"
        let c = MoneyCard.make(chips: Money.chips(in: src, fx: FXContext(rates: .bundled, currency: .usd)), source: src, fromPartner: true)!
        XCTAssertEqual(c.header, "Their price")
        XCTAssertEqual(c.conditions, ["excl. delivery"])
        XCTAssertTrue(c.lines[0].chinese.contains("rupiah"))
        XCTAssertFalse(c.accessibilityText.contains("印尼盾"))
    }
}
