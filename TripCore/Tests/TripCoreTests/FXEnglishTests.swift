import XCTest
@testable import TripCore

final class FXEnglishP2Tests: XCTestCase {
    let r = FXRates.bundled
    func vals(_ s: String) -> [Int] { AmountNormalizer.findAmounts(in: s).flatMap(\.values) }

    func testEnglishWritings() {
        let cases: [(String, [Int])] = [
            ("it's 50k", [50_000]), ("50 thousand rupiah", [50_000]), ("1.5 million", [1_500_000]),
            ("2 mil please", [2_000_000]), ("IDR 50,000", [50_000]), ("Rp 1,500,000", [1_500_000]),
            ("50,000 rupiah", [50_000]), ("25000 IDR", [25_000]), ("150.000 rupiah", [150_000]),
            ("30k-40k", [30_000, 40_000]), ("30 to 40 thousand", [30_000, 40_000]),
            ("1,5 juta", [1_500_000]), ("50rb", [50_000]),                        // 印尼语写法不退化
            ("room 305", []), ("at 7 pm", []), ("2 people", []),
        ]
        for (s, v) in cases { XCTAssertEqual(vals(s), v, s) }
    }

    func testDisplayForLang() {
        let m = AmountNormalizer.findAmounts(in: "harga 50rb")[0]
        XCTAssertEqual(m.display(for: "zh-Hans"), "5万")
        XCTAssertEqual(m.display(for: "en"), "Rp 50,000")
        XCTAssertEqual(m.display(for: "id"), "Rp 50.000")
        let rg = AmountNormalizer.findAmounts(in: "30-40rb")[0]
        XCTAssertEqual(rg.display(for: "en"), "Rp 30,000–40,000")
        let (ph, t) = AmountNormalizer.placeholderize("harga 50rb")
        XCTAssertEqual(AmountNormalizer.restore(ph.replacingOccurrences(of: "harga", with: "price"), table: t, lang: "en"), "price Rp 50,000")
    }

    func testAnnotateEnglishWhitelist() {
        let allowed = AmountAnnotator.allowedValues(source: "harganya 100rb kak")
        XCTAssertEqual(AmountAnnotator.annotateEnglish("The price is Rp 100,000", allowed: allowed, to: .usd, rates: r), "The price is Rp 100,000 (≈ $5.6)")
        XCTAssertEqual(AmountAnnotator.annotateEnglish("The price is 100k", allowed: allowed, to: .usd, rates: r), "The price is 100k (≈ $5.6)")
        // 模型写错数量级 → 不加注
        XCTAssertEqual(AmountAnnotator.annotateEnglish("The price is Rp 1,000,000", allowed: allowed, to: .usd, rates: r), "The price is Rp 1,000,000")
        XCTAssertEqual(AmountAnnotator.annotateEnglish("The price is 10,000", allowed: allowed, to: .usd, rates: r), "The price is 10,000")
        let a2 = AmountAnnotator.allowedValues(source: "30-40rb")
        XCTAssertEqual(AmountAnnotator.annotateEnglish("Rp 30,000–40,000", allowed: a2, to: .usd, rates: r), "Rp 30,000–40,000 (≈ $1.7–2.2)")
        XCTAssertEqual(AmountAnnotator.annotateDisplay("Rp 100.000", lang: "id", allowed: allowed, to: .idr, rates: r), "Rp 100.000")
    }

    func testIDRTargetNoAnnotation() {
        XCTAssertEqual(AmountAnnotator.annotateSource("Rp 100.000", to: .idr, rates: r), "Rp 100.000")
        XCTAssertEqual(TargetCurrency.forLocale("id-ID"), .idr)
        XCTAssertEqual(TargetCurrency.forLocale("en-US"), .usd)
        XCTAssertEqual(TargetCurrency.forLocale("zh-Hans-CN"), .cny)
        XCTAssertTrue(FXRates.isSane(r))
    }

    func testReverseNotes() {
        XCTAssertEqual(ForeignCashParser.findUSD(in: "it costs $20 or 30 dollars, 5 USD"), [20, 30, 5])
        XCTAssertEqual(ForeignCashParser.notes(in: "$20", lang: "en", rates: r), ["$20≈Rp 358,000"])
        XCTAssertEqual(ForeignCashParser.notes(in: "¥200", lang: "zh-Hans", rates: r), ["¥200≈Rp 536.000"])
        XCTAssertEqual(ForeignCashParser.notes(in: "200块", lang: "id", rates: r), ["¥200≈Rp 536.000"])
    }

    /// 2000 次随机：英文写法 → 解析值 → 美元约值，数量级必须正确
    func testEnglishMagnitudeProperty() {
        var g = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let k = Int.random(in: 1...999, using: &g)
            let form = Int.random(in: 0..<4, using: &g)
            let (s, v): (String, Int) = {
                switch form {
                case 0: return ("\(k)k", k * 1000)
                case 1: return ("\(k) thousand rupiah", k * 1000)
                case 2: return ("IDR \(RupiahFormatter.grouped(k * 1000, sep: ","))", k * 1000)
                default: return ("\(k) million", k * 1_000_000)
                }
            }()
            XCTAssertEqual(vals(s), [v], s)
            let usd = Double(v) / r.idrPerUSD
            let shown = AmountAnnotator.annotateEnglish(s, allowed: [v], to: .usd, rates: r)
            let num = Double(shown.split(separator: "$").last!.dropLast().replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "<", with: "")) ?? -1
            if usd >= 0.1 { XCTAssertEqual(num, usd, accuracy: usd < 10 ? 0.051 : 0.501, s) }
        }
    }
}
