import XCTest
@testable import TripCore

/// 用 model_eval 里的真实模型输出做校验用例。
final class ValidatorTests: XCTestCase {
    let ctx50 = [ContextTurn(role: .them, source: "50rb belum termasuk ongkos", zhDisplay: "5万不含车费"), ContextTurn(role: .me, source: "太贵了")]
    let ctx200 = [ContextTurn(role: .them, source: "ke bandara 200rb", zhDisplay: "去机场20万"), ContextTurn(role: .me, source: "150行吗")]

    func v(_ out: String, _ lit: String, _ src: String, _ ctx: [ContextTurn] = []) -> ValidationResult {
        OutputValidator.validate(output: out, literal: lit, source: src, context: ctx)
    }

    func testReferenceAmountWithContext() {
        XCTAssertEqual(v("刚才那个价格4万就行", "刚才的40就行", "yang tadi 40 saja", ctx50), .accepted("刚才那个价格4万就行"))
        XCTAssertEqual(v("刚才那个40就行", "刚才的40就行", "yang tadi 40 saja", ctx50), .accepted("刚才那个40就行"))
        // 没有金额上下文时，40 不能被放大成 4万
        XCTAssertEqual(v("4万就行", "40就行", "yang tadi 40 saja"), .rejected(.amountMismatch("4万")))
    }

    func testWrongAmountsRejected() {
        XCTAssertEqual(v("175万成交好吗", "175成交好吗", "175 deal ya", ctx200), .rejected(.amountMismatch("175万")))
        XCTAssertEqual(v("17.5万成交", "175成交好吗", "175 deal ya", ctx200), .accepted("17.5万成交"))
        XCTAssertEqual(v("价格是2.5万每人", "价格是250千每人", "harganya 250 ribu per orang"), .rejected(.amountMismatch("2.5万")))
        XCTAssertEqual(v("价格是25万每人", "价格是250千每人", "harganya 250 ribu per orang"), .accepted("价格是25万每人"))
        XCTAssertEqual(v("三个120万就行", "三个12万就行", "tiga 120rb aja"), .rejected(.amountMismatch("120万")))
        XCTAssertEqual(v("总共150万已经包括小费", "总共1.5jt已经包括小费", "total 1,5jt sudah termasuk tips"), .accepted("总共150万已经包括小费"))
        XCTAssertEqual(v("这个10万，那个7.5万", "这个10万，那个7.5万", "ini 100rb, itu 75rb"), .unchanged)
    }

    func testNonMoneyNumbersAllowed() {
        XCTAssertEqual(v("我到了，白色 Avanza，车牌B 1234 XYZ", "我已经到了", "saya sudah sampai, mobil avanza putih B 1234 XYZ"), .accepted("我到了，白色 Avanza，车牌B 1234 XYZ"))
        XCTAssertEqual(v("我在路上，10分钟后到", "sy otw 姐姐", "sy otw kak, 10 mnt lg"), .accepted("我在路上，10分钟后到"))
        XCTAssertEqual(v("可以等15分钟吗", "可以等5分钟吗？", "bisa tunggu 5 menit?"), .rejected(.amountMismatch("15")))
    }

    func testForeignWords() {
        XCTAssertEqual(v("brp 还要多久先生？", "brp 还要多久先生？", "brp lama lagi pak?"), .unchanged)
        XCTAssertEqual(v("tiga 120万", "三个12万就行", "tiga 120rb aja"), .rejected(.amountMismatch("120万")))
        XCTAssertEqual(v("总共1.5 juta sudah termasuk tip.", "x", "total 1,5jt sudah termasuk tips"), .rejected(.foreignWord("juta")))
        XCTAssertEqual(v("可以刷QRIS付款吗？", "bs 付用 qris？", "bs bayar pake qris?"), .accepted("可以刷QRIS付款吗？"))
        XCTAssertEqual(v("好的mantap", "太棒了", "mantap, gas!"), .accepted("好的mantap")) // 原文出现的词允许
        XCTAssertEqual(v("请稍等hello", "请等", "pls wait"), .rejected(.foreignWord("hello")))
    }

    func testFormatRules() {
        XCTAssertEqual(v("   ", "谢谢", "terima kasih"), .rejected(.empty))
        XCTAssertEqual(v(String(repeating: "好", count: 81), "谢谢", "terima kasih"), .rejected(.empty), "r8：整串重复字先按坏输出拒绝")
        XCTAssertEqual(v(String(repeating: "好吃的炒饭不辣", count: 12), "谢谢", "terima kasih"), .rejected(.tooLong))
        XCTAssertEqual(v("「谢谢。」\n解释：…", "谢谢", "terima kasih"), .unchanged)
        XCTAssertEqual(v("早上好！", "早上好", "selamat pagi"), .unchanged)
    }

    func testPromptBuilder() {
        let p = PromptBuilder()
        let u = p.user(context: ctx50, source: "ini 100rb, itu 75rb", literal: "这个10万", glossary: [GlossaryHit(source: "ongkos", zh: "车费")])
        XCTAssertTrue(u.contains("对方：50rb belum termasuk ongkos ／ 中文：5万不含车费"))
        XCTAssertTrue(u.contains("我：太贵了"))
        XCTAssertTrue(u.contains("⟦N1⟧100rb=10万, ⟦N2⟧75rb=7.5万"))
        XCTAssertTrue(u.contains("词：ongkos = 车费"))
        XCTAssertTrue(p.system.contains("印尼语"))
        let many = (0..<30).map { ContextTurn(role: .me, source: "句\($0)") }
        let t = PromptBuilder(maxContextTurns: 5).trimmed(many)
        XCTAssertEqual(t.map(\.source), ["句0", "句26", "句27", "句28", "句29"])
        let hits = (0..<12).map { GlossaryHit(source: "w\($0)", zh: "z") }
        XCTAssertFalse(p.user(context: [], source: "x", literal: "y", glossary: hits).contains("w8"))
    }
}
