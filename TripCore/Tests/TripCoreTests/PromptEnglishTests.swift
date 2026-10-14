import XCTest
@testable import TripCore

final class PromptEnglishP3Tests: XCTestCase {
    func testChinesePromptUnchangedByDefault() {
        let b = PromptBuilder()
        XCTAssertEqual(b.target, "zh-Hans")
        XCTAssertTrue(b.system.hasPrefix("你是旅行对话的中文译文修正器"))
        XCTAssertEqual(PromptBuilder.fewShot(for: "zh-Hans").map(\.assistant), PromptBuilder.fewShot.map(\.assistant))
        XCTAssertTrue(b.user(context: [], source: "harga 50rb", literal: "价格5万", glossary: []).contains("⟦N1⟧50rb=5万"))
    }

    func testEnglishPromptSnapshot() {
        var b = PromptBuilder(); b.target = "en"; b.scene = "Ride-hailing"
        XCTAssertTrue(b.system.contains("Indonesian"))
        XCTAssertFalse(b.system.unicodeScalars.contains { $0.properties.isIdeographic })
        let u = b.user(context: [ContextTurn(role: .them, source: "harga 30rb", zhDisplay: "the price is Rp 30,000"), ContextTurn(role: .me, source: "Too expensive")],
                       source: "yang tadi 25 aja", literal: "the earlier 25 only", glossary: [GlossaryHit(source: "ongkos", zh: "fare")])
        XCTAssertEqual(u, """
        Conversation (in order):
        Scene: Ride-hailing
        Them: harga 30rb / English: the price is Rp 30,000
        Me: Too expensive

        Amounts: none
        Words: ongkos = fare

        Original: yang tadi 25 aja
        Literal:
        the earlier 25 only
        """)
        XCTAssertTrue(b.user(context: [], source: "harga 50rb", literal: "", glossary: []).contains("⟦N1⟧50rb=Rp 50,000"))
        XCTAssertEqual(b.prefixMessages.count, 1 + 2 * PromptBuilder.fewShotEnglish.count)
        XCTAssertTrue(PromptBuilder.supportsUnderstanding(target: "en"))
        XCTAssertFalse(PromptBuilder.supportsUnderstanding(target: "id"))
    }

    func v(_ out: String, _ src: String, lit: String = "x", ctx: [ContextTurn] = []) -> ValidationResult {
        OutputValidator.validate(output: out, literal: lit, source: src, context: ctx, target: "en")
    }

    func testEnglishValidator() {
        XCTAssertEqual(v("Rp 50,000, fare not included", "50rb belum termasuk ongkos"), .accepted("Rp 50,000, fare not included"))
        XCTAssertEqual(v("50k, fare not included", "50rb belum termasuk ongkos"), .accepted("50k, fare not included"))
        // 数量级错 → 拒绝
        XCTAssertEqual(v("Rp 500,000, fare not included", "50rb belum termasuk ongkos"), .rejected(.amountMismatch("500,000")))
        XCTAssertEqual(v("5k only", "50rb belum termasuk ongkos"), .rejected(.amountMismatch("5k")))
        XCTAssertEqual(v("1.5 million including tips", "total 1,5jt sudah termasuk tips"), .accepted("1.5 million including tips"))
        XCTAssertEqual(v("15 million including tips", "total 1,5jt sudah termasuk tips"), .rejected(.amountMismatch("15 million")))
        // 讲价裸数字 → 千
        let ctx = [ContextTurn(role: .them, source: "ke bandara 200rb")]
        XCTAssertEqual(v("175k, deal?", "175 deal ya", ctx: ctx), .accepted("175k, deal?"))
        XCTAssertEqual(v("Wait 5 minutes?", "bisa tunggu 5 menit?"), .accepted("Wait 5 minutes?"))
        XCTAssertEqual(v("Wait 50 minutes?", "bisa tunggu 5 menit?"), .rejected(.amountMismatch("50")))
        XCTAssertEqual(v("The boat leaves at 9, be at the harbor by 8.30", "kapal ke Gili jam 9, harus di pelabuhan jam 8.30"),
                       .accepted("The boat leaves at 9, be at the harbor by 8.30"))
        // 残留缩写 / 汉字
        XCTAssertEqual(v("udh arrived", "udh sampe"), .rejected(.foreignWord("udh")))
        XCTAssertEqual(v("已经到了", "udh sampe"), .rejected(.foreignWord("汉字")))
        XCTAssertEqual(v("Have you arrived?", "udh sampe blm?", lit: "Have you arrived?"), .unchanged)
    }
}
