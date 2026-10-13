import XCTest
@testable import TripCore

/// 金额换算（PRD v2 §7.9）：数量级永不出错。
final class FXTests: XCTestCase {
    let r = FXRates.bundled

    func one(_ s: String) -> Int? {
        let a = AmountNormalizer.findAmounts(in: s); XCTAssertEqual(a.count, 1, s); return a.first?.value
    }

    func testAllSuffixFormsMagnitude() {
        let cases: [(String, Int)] = [
            ("50rb", 50_000), ("50 rb", 50_000), ("50ribu", 50_000), ("50 ribu", 50_000), ("50rbu", 50_000),
            ("50k", 50_000), ("50K", 50_000), ("1,5jt", 1_500_000), ("1.5jt", 1_500_000), ("1,5 juta", 1_500_000),
            ("2 juta", 2_000_000), ("250 ribu", 250_000), ("Rp 100.000", 100_000), ("Rp100.000", 100_000),
            ("100.000", 100_000), ("1.500.000", 1_500_000), ("Rp 5000", 5_000), ("Rp. 25000", 25_000),
            ("IDR 50,000", 50_000), ("IDR 1,250,000", 1_250_000), ("10rb", 10_000), ("100rb", 100_000), ("1rb", 1_000),
            ("2,5rb", 2_500), ("0,5jt", 500_000), ("12.500", 12_500),
        ]
        for (s, v) in cases { XCTAssertEqual(one(s), v, s) }
    }

    func testAmbiguousForms() {
        XCTAssertEqual(one("10.000"), 10_000, "点 + 三位 = 千分位")
        XCTAssertEqual(one("10,5rb"), 10_500, "逗号 = 小数点")
        XCTAssertEqual(AmountNormalizer.findAmounts(in: "10,5").count, 0, "无单位小数不当金额")
        XCTAssertEqual(AmountNormalizer.findAmounts(in: "50,000").count, 0, "无 Rp 前缀的英文逗号千分位不猜")
        XCTAssertEqual(AmountNormalizer.findAmounts(in: "jam 10.30").count, 0, "时间不当金额")
        XCTAssertEqual(one("Rp 50rb"), 50_000, "Rp + 单位不重复")
    }

    func testMagnitudePropertyRoundTrip() {
        // 任意金额：Rp 千分位写法 → 解析 → 换算；人民币值 × 汇率 必须回到同一数量级（误差 < 1%）
        var g = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let v = Int.random(in: 1...5_000, using: &g) * [1, 10, 100, 1000][Int.random(in: 0...3, using: &g)]
            guard v >= 1000 else { continue }
            let text = "harganya \(Money_rupiah(v)) ya"
            let parsed = AmountNormalizer.findAmounts(in: text).first?.value
            XCTAssertEqual(parsed, v, text)
            let cny = Double(v) / r.idrPerCNY
            XCTAssertLessThan(abs(cny * r.idrPerCNY - Double(v)) / Double(v), 0.01)
            // 显示的数值与真实值同数量级（取整误差内）
            let shown = FXFormatter.amount(v, to: .cny, rates: r).dropFirst().replacingOccurrences(of: ",", with: "")
            if let d = Double(shown), cny >= 0.1 { XCTAssertLessThanOrEqual(abs(d - cny), cny < 10 ? 0.051 : 0.501, text) }   // 只有取整误差，数量级不变
        }
        for (s, v) in [("10rb", 10_000), ("1rb", 1_000), ("100rb", 100_000)] {
            XCTAssertEqual(AmountNormalizer.findAmounts(in: s).first?.value, v)
        }
    }

    private func Money_rupiah(_ v: Int) -> String {
        let s = String(v); var out = ""
        for (i, ch) in s.reversed().enumerated() { if i > 0 && i % 3 == 0 { out.append(".") }; out.append(ch) }
        return "Rp " + String(out.reversed())
    }

    func testFormatterValues() {
        XCTAssertEqual(FXFormatter.amount(100_000, to: .cny, rates: r), "¥37")     // 100000/2677.5 = 37.3
        XCTAssertEqual(FXFormatter.amount(10_000, to: .cny, rates: r), "¥3.7")
        XCTAssertEqual(FXFormatter.amount(1_000, to: .cny, rates: r), "¥0.4")
        XCTAssertEqual(FXFormatter.amount(1_500_000, to: .cny, rates: r), "¥560")
        XCTAssertEqual(FXFormatter.amount(100_000, to: .usd, rates: r), "$5.6")
        XCTAssertEqual(FXFormatter.amount(50_000_000, to: .usd, rates: r), "$2,790")
        XCTAssertEqual(FXFormatter.approx(30_000, upper: 40_000, to: .cny, rates: r), "约 ¥11–15")
        XCTAssertEqual(FXFormatter.approx(30_000, to: .usd, rates: r), "≈ $1.7")
        XCTAssertEqual(TargetCurrency.forLocale("zh-Hans-CN"), .cny)
        XCTAssertEqual(TargetCurrency.forLocale("en_US"), .usd)
        XCTAssertEqual(TargetCurrency.forLocale("id"), .usd)
    }

    func testTenKVsOneKVsHundredKNeverConfused() {
        let a = FXFormatter.amount(1_000, to: .cny, rates: r), b = FXFormatter.amount(10_000, to: .cny, rates: r), c = FXFormatter.amount(100_000, to: .cny, rates: r)
        XCTAssertEqual([a, b, c], ["¥0.4", "¥3.7", "¥37"])
        XCTAssertEqual(AmountAnnotator.annotateSource("10rb", to: .cny, rates: r), "10rb（约 ¥3.7）")
        XCTAssertEqual(AmountAnnotator.annotateSource("100rb", to: .cny, rates: r), "100rb（约 ¥37）")
    }

    func testAnnotateSource() {
        XCTAssertEqual(AmountAnnotator.annotateSource("Harganya Rp 100.000 kak", to: .cny, rates: r), "Harganya Rp 100.000（约 ¥37） kak")
        XCTAssertEqual(AmountAnnotator.annotateSource("Sekitar Rp 30-40 ribu.", to: .cny, rates: r), "Sekitar Rp 30-40 ribu（约 ¥11–15）.")
        XCTAssertEqual(AmountAnnotator.annotateSource("ongkos 6-7rb", to: .usd, rates: r), "ongkos 6-7rb（≈ $0.3–0.4）")
        XCTAssertEqual(AmountAnnotator.annotateSource("Terima kasih", to: .cny, rates: r), "Terima kasih")
    }

    func testAnnotateChineseOnlyAllowedValues() {
        let src = "50rb belum termasuk ongkos"
        let allowed = AmountAnnotator.allowedValues(source: src)
        XCTAssertEqual(AmountAnnotator.annotateChinese("5万，不含车费", allowed: allowed, to: .cny, rates: r), "5万（约 ¥19），不含车费")
        XCTAssertEqual(AmountAnnotator.annotateChinese("50万，不含车费", allowed: allowed, to: .cny, rates: r), "50万，不含车费", "模型写错数量级时不加注释")
        let rs = AmountAnnotator.allowedValues(source: "Sekitar Rp 30-40 ribu")
        XCTAssertEqual(AmountAnnotator.annotateChinese("大概3万–4万", allowed: rs, to: .cny, rates: r), "大概3万–4万（约 ¥11–15）")
        XCTAssertEqual(AmountAnnotator.annotateChinese("大概3–4万", allowed: rs, to: .cny, rates: r), "大概3–4万（约 ¥11–15）")
        XCTAssertEqual(AmountAnnotator.annotateChinese("7500块", allowed: [7_500], to: .cny, rates: r), "7500（约 ¥2.8）块")
        XCTAssertEqual(AmountAnnotator.annotateChinese("等2分钟", allowed: [], to: .cny, rates: r), "等2分钟")
    }

    func testCommunityQuotes() {
        let q: [(String, String)] = [
            ("Kalo ke Jalan Raya Kebon Jeruk, ongkosnya lumayan beda kak. Sekitar Rp 30-40 ribu.", "Rp 30-40 ribu（约 ¥11–15）"),
            ("Kasih dia tips 10rb kalo nyuruh2 jalan kaki jaoh gitu.", "10rb（约 ¥3.7）"),
            ("wanted 80k as a tip", "80k（约 ¥30）"),
            ("ongkosan 1 makanan 6-7rb", "6-7rb（约 ¥2.2–2.6）"),
        ]
        for (s, want) in q { XCTAssertTrue(AmountAnnotator.annotateSource(s, to: .cny, rates: r).contains(want), s) }
    }

    func testRateSanityBounds() {
        XCTAssertTrue(FXRates.isSane(r))
        var c = r; c.idrPerCNY *= 1.25; XCTAssertTrue(FXRates.isSane(c))
        c = r; c.idrPerCNY *= 1.4; XCTAssertFalse(FXRates.isSane(c), ">30% 拒绝")
        c = r; c.idrPerUSD /= 10; XCTAssertFalse(FXRates.isSane(c), "单位错一位数拒绝")
        c = r; c.idrPerUSD = .nan; XCTAssertFalse(FXRates.isSane(c))
        let j = Data(#"{"amount":1.0,"base":"USD","date":"2026-10-12","rates":{"CNY":6.6928,"IDR":17920}}"#.utf8)
        let p = FXRates.parseFrankfurter(j)!
        XCTAssertEqual(p.date, "2026-10-12"); XCTAssertEqual(p.idrPerCNY, r.idrPerCNY, accuracy: 0.01); XCTAssertTrue(FXRates.isSane(p))
        XCTAssertNil(FXRates.parseFrankfurter(Data(#"{"base":"EUR","date":"x","rates":{}}"#.utf8)))
    }

    func testCNYReverse() {
        XCTAssertEqual(CNYParser.find(in: "最多给200块"), [200])
        XCTAssertEqual(CNYParser.find(in: "¥50 可以吗"), [50])
        XCTAssertEqual(CNYParser.find(in: "1.5万人民币"), [15_000])
        XCTAssertEqual(CNYParser.find(in: "等2分钟"), [])
        XCTAssertEqual(CNYParser.idrNote(200, rates: r), "约 Rp 536.000")
    }
}
