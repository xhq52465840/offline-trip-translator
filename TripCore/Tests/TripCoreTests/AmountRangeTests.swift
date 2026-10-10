import XCTest
@testable import TripCore

/// 金额区间（社区真实语料发现的缺陷，见 docs/社区真实语料.md）
final class AmountRangeTests: XCTestCase {
    func one(_ s: String) -> AmountMatch? { let a = AmountNormalizer.findAmounts(in: s); XCTAssertEqual(a.count, 1, s); return a.first }

    func testRangeForms() {
        let cases: [(String, Int, Int, String)] = [
            ("Rp 30-40 ribu", 30_000, 40_000, "3万–4万"),
            ("6-7rb", 6_000, 7_000, "6000–7000"),
            ("30rb-40rb", 30_000, 40_000, "3万–4万"),
            ("30 s/d 40 ribu", 30_000, 40_000, "3万–4万"),
            ("50–75rb", 50_000, 75_000, "5万–7.5万"),
            ("1-1,5jt", 1_000_000, 1_500_000, "100万–150万"),
            ("Rp 30.000-40.000", 30_000, 40_000, "3万–4万"),
            ("100 sampai 150 ribu", 100_000, 150_000, "10万–15万"),
            ("500rb - 1jt", 500_000, 1_000_000, "50万–100万"),
        ]
        for (s, lo, hi, d) in cases {
            guard let m = one(s) else { continue }
            XCTAssertEqual(m.value, lo, s); XCTAssertEqual(m.upperValue, hi, s); XCTAssertEqual(m.display, d, s)
        }
    }

    func testRealCommunityQuotes() {
        // community_cases C008 / C014 / C015 及英文旅客帖 C021
        let a = AmountNormalizer.findAmounts(in: "Kalo ke Jalan Raya Kebon Jeruk, ongkosnya lumayan beda kak. Sekitar Rp 30-40 ribu.")
        XCTAssertEqual(a.map(\.display), ["3万–4万"])
        XCTAssertEqual(AmountNormalizer.findAmounts(in: "ongkosan 1 makanan 6-7rb, masih harus jalan kaki PP 600m").map(\.display), ["6000–7000"])
        XCTAssertEqual(AmountNormalizer.findAmounts(in: "Kasih dia tips 10rb kalo nyuruh2 jalan kaki jaoh gitu.").map(\.display), ["1万"])
        XCTAssertEqual(AmountNormalizer.findAmounts(in: "wanted 80k as a tip").map(\.display), ["8万"])
    }

    func testNotARange() {
        XCTAssertNil(AmountNormalizer.findAmounts(in: "40-30 ribu").first?.upperValue, "下限大于上限不当区间")
        XCTAssertEqual(AmountNormalizer.findAmounts(in: "jam 2-3 siang").count, 0)
        XCTAssertEqual(AmountNormalizer.findAmounts(in: "beli 2 harga 50rb").map(\.display), ["5万"])
    }

    func testPlaceholderAndRestore() {
        let (t, table) = AmountNormalizer.placeholderize("ongkos Rp 30-40 ribu ya")
        XCTAssertEqual(t, "ongkos Rp ⟦N1⟧ ya")   // 与单个金额一致：Rp 前缀留在原文
        XCTAssertEqual(AmountNormalizer.restore("运费⟦N1⟧", table: table), "运费3万–4万")
    }

    func testValidatorAcceptsRange() {
        let src = "Sekitar Rp 30-40 ribu"
        XCTAssertEqual(OutputValidator.validate(output: "大概3万–4万", literal: "大约Rp 30-40千", source: src, context: []), .accepted("大概3万–4万"))
        XCTAssertEqual(OutputValidator.validate(output: "大概3万到4万", literal: "x", source: src, context: []), .accepted("大概3万到4万"))
        XCTAssertEqual(OutputValidator.validate(output: "大概4万", literal: "x", source: src, context: []), .accepted("大概4万"))
        if case .rejected = OutputValidator.validate(output: "大概3万–5万", literal: "x", source: src, context: []) {} else { XCTFail("5万不在原文里") }
        XCTAssertFalse(AmountNormalizer.bareNumbers(in: src).contains(30), "区间数字不应再当裸数字")
    }
}
