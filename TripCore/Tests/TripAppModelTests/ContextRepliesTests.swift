import XCTest
import TripCore
@testable import TripAppModel

final class ContextRepliesTests: XCTestCase {
    func testClassify() {
        XCTAssertEqual(ContextReplies.classify("50rb belum termasuk ongkos"), .price)
        XCTAssertEqual(ContextReplies.classify("Harganya Rp 100.000 kak"), .price)
        XCTAssertEqual(ContextReplies.classify("Lurus terus, nanti belok kiri di Jalan Legian"), .place)
        XCTAssertEqual(ContextReplies.classify("Tunggu 10 menit ya"), .time)
        XCTAssertEqual(ContextReplies.classify("Mau pakai es?"), .question)
        XCTAssertEqual(ContextReplies.classify("Maaf, sudah habis"), .negative)
        XCTAssertEqual(ContextReplies.classify("Oke kak siap"), .fallback)
        XCTAssertEqual(ContextReplies.classify("Turn left at the bank"), .place)
    }
    func testCounterOfferIsCodeComputed() {
        XCTAssertEqual(ContextReplies.counterOffer(50_000), 40_000)
        XCTAssertEqual(ContextReplies.counterOffer(100_000), 80_000)
        XCTAssertEqual(ContextReplies.counterOffer(175_000), 140_000)
        XCTAssertEqual(ContextReplies.counterOffer(5_500), 4_400)
        XCTAssertEqual(ContextReplies.counterOffer(25_000), 20_000)
        XCTAssertEqual(ContextReplies.counterOffer(12_345), 9_000)
    }
    func testPriceRepliesTrilingual() {
        let r = ContextReplies.replies(for: .price, price: 50_000)
        XCTAssertEqual(r.first?.zh, "太贵了，便宜点")
        XCTAssertEqual(r[1].zh, "4万印尼盾行吗？")
        XCTAssertEqual(r[1].id_, "Rp 40.000 boleh?")
        XCTAssertEqual(r[1].en, "Would Rp 40,000 work?")
        for p in r { XCTAssertFalse(p.id_.isEmpty); XCTAssertFalse(p.en.isEmpty) }
    }
    func testSuggestUsesLastTheirMessage() {
        XCTAssertNil(ContextReplies.suggest(messages: []))
        var a = Message(id: UUID(), role: .them, createdAt: Date(), source: "50rb belum termasuk ongkos", sourceLocale: "id")
        a.status = .ready
        var b = Message(id: UUID(), role: .me, createdAt: Date(), source: "太贵了", sourceLocale: "zh-Hans")
        b.status = .ready
        let s = ContextReplies.suggest(messages: [a, b])!
        XCTAssertEqual(s.kind, .price)
        XCTAssertTrue(s.phrases.contains { $0.id_ == "Rp 40.000 boleh?" })
    }
    func testAllKindsNonEmpty() {
        for k in [ContextReplies.Kind.price, .place, .time, .question, .negative, .fallback] {
            XCTAssertFalse(ContextReplies.replies(for: k, price: 10_000).isEmpty)
        }
    }
}
