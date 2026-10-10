import XCTest
@testable import TripCore

/// 30 条用例与 model_eval/cases.py 一一对应：原文 -> 期望识别的金额数值。
final class AmountTests: XCTestCase {
    static let cases: [(String, String, [Int])] = [
        ("01", "50rb belum termasuk ongkos", [50_000]),
        ("02", "yang tadi 40 saja", []),
        ("03", "brp lama lagi pak?", []),
        ("04", "udh di depan lobby ya", []),
        ("05", "gk bisa kurang lagi kak", []),
        ("06", "total 1,5jt sudah termasuk tips", [1_500_000]),
        ("07", "harganya 250 ribu per orang", [250_000]),
        ("08", "saya sudah sampai, mobil avanza putih B 1234 XYZ", []),
        ("09", "tunggu sebentar ya, macet", []),
        ("10", "oke saya ke situ", []),
        ("11", "ini 100rb, itu 75rb", [100_000, 75_000]),
        ("12", "yang mahal bisa 85", []),
        ("13", "maaf kak, udah habis", []),
        ("14", "alamatnya di jl. sunset road no 88", []),
        ("15", "mantap, gas!", []),
        ("16", "nggak apa-apa, santai aja", []),
        ("17", "jam berapa pesawatnya?", []),
        ("18", "175 deal ya", []),
        ("19", "bisa tunggu 5 menit?", []),
        ("20", "it's 50k for the ride, cash only", [50_000]),
        ("21", "same price", []),
        ("22", "sy otw kak, 10 mnt lg", []),
        ("23", "oke yang biasa ya", []),
        ("24", "belum bayar, kurang 20rb", [20_000]),
        ("25", "terima kasih", []),
        ("26", "selamat pagi", []),
        ("27", "tiga 120rb aja", [120_000]),
        ("28", "oke ke sana 80rb", [80_000]),
        ("29", "bs bayar pake qris?", []),
        ("30", "pls wait, i'm omw", []),
    ]

    func testThirtyCaseSet() {
        XCTAssertEqual(Self.cases.count, 30)
        for (id, src, expected) in Self.cases {
            XCTAssertEqual(AmountNormalizer.findAmounts(in: src).map(\.value), expected, "case \(id): \(src)")
        }
    }

    func testEdgeForms() {
        let t: [(String, Int, String)] = [
            ("50rb", 50_000, "5万"), ("50 RB", 50_000, "5万"), ("250 ribu", 250_000, "25万"),
            ("1,5jt", 1_500_000, "150万"), ("2.5jt", 2_500_000, "250万"), ("1,5 juta", 1_500_000, "150万"),
            ("3 juta", 3_000_000, "300万"), ("75rb", 75_000, "7.5万"), ("50k", 50_000, "5万"), ("50K", 50_000, "5万"),
            ("Rp 50.000", 50_000, "5万"), ("1.500.000", 1_500_000, "150万"), ("45rbu", 45_000, "4.5万"),
            ("5rb", 5_000, "5000"), ("12.500", 12_500, "1.25万"), ("50.000rb", 50_000_000, "5000万"),
        ]
        for (s, v, d) in t {
            let m = AmountNormalizer.findAmounts(in: s)
            XCTAssertEqual(m.count, 1, s)
            XCTAssertEqual(m.first?.value, v, s)
            XCTAssertEqual(m.first?.display, d, s)
        }
    }

    func testNotAmounts() {
        for s in ["kerbau", "rbx", "B 1234 XYZ", "jam 5", "okey", "10 mnt", "jtk", "8.5"] {
            XCTAssertTrue(AmountNormalizer.findAmounts(in: s).isEmpty, s)
        }
    }

    func testFormatter() {
        XCTAssertEqual(ChineseAmountFormatter.format(9_500), "9500")
        XCTAssertEqual(ChineseAmountFormatter.format(10_000), "1万")
        XCTAssertEqual(ChineseAmountFormatter.format(175_000), "17.5万")
        XCTAssertEqual(ChineseAmountFormatter.format(1_500_000), "150万")
        XCTAssertEqual(ChineseAmountFormatter.parse("17.5万"), 175_000)
        XCTAssertEqual(ChineseAmountFormatter.parse("1234"), 1234)
    }

    func testPlaceholderRoundTrip() {
        let (t, table) = AmountNormalizer.placeholderize("ini 100rb, itu 75rb")
        XCTAssertEqual(t, "ini ⟦N1⟧, itu ⟦N2⟧")
        XCTAssertEqual(AmountNormalizer.restore("这个⟦N1⟧，那个⟦N2⟧", table: table), "这个10万，那个7.5万")
        XCTAssertNil(AmountNormalizer.restore("这个⟦N1⟧，那个", table: table), "占位丢失应回退")
        XCTAssertNil(AmountNormalizer.restore("⟦N1⟧⟦N1⟧⟦N2⟧", table: table), "占位重复应回退")
    }

    func testBareNumbers() {
        XCTAssertEqual(AmountNormalizer.bareNumbers(in: "yang tadi 40 saja"), [40])
        XCTAssertEqual(AmountNormalizer.bareNumbers(in: "ini 100rb, itu 75"), [75])
    }
}
