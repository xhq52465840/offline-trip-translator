import XCTest
@testable import TripAppModel
import TripCore

@MainActor
final class UXTests: XCTestCase {
    func testScenariosHavePhrasesInBothLanguages() {
        XCTAssertGreaterThanOrEqual(Scenario.allCases.count, 12)
        for s in Scenario.allCases {
            XCTAssertGreaterThanOrEqual(s.phrases.count, 3, s.title)
            XCTAssertEqual(Set(s.phrases.map(\.zh)).count, s.phrases.count)
            for p in s.phrases {
                XCTAssertFalse(p.id_.isEmpty); XCTAssertFalse(p.en.isEmpty)
                XCTAssertTrue(p.zh.unicodeScalars.contains { $0.properties.isIdeographic }, p.zh)
            }
        }
    }

    func testMoneyChips() {
        XCTAssertEqual(Money.rupiah(50000), "Rp 50.000")
        XCTAssertEqual(Money.rupiah(1500000), "Rp 1.500.000")
        XCTAssertEqual(Money.rupiah(500), "Rp 500")
        let r = ExchangeRate(idrPerCny: 2500, updatedNote: "")
        XCTAssertEqual(Money.cny(50000, rate: r), "≈ ¥20.0")
        XCTAssertEqual(Money.cny(1500000, rate: r), "≈ ¥600")
        XCTAssertNil(Money.cny(50000, rate: nil))
        let chips = Money.chips(in: "total 1,5jt, deposit 500rb", rate: r)
        XCTAssertEqual(chips.map(\.rupiah), ["Rp 1.500.000", "Rp 500.000"])
        XCTAssertEqual(chips.first?.chinese, "150万印尼盾")
    }

    func testPhraseSendIsInstantAndFree() async {
        let tr = FakeTranslator()
        let trial = TrialCounter(store: InMemoryTrialStore())
        let m = ConversationModel(translator: tr, understander: nil, trial: trial)
        m.scene = .restaurant
        m.sendPhrase(Scenario.restaurant.phrases[1])
        XCTAssertEqual(m.messages.count, 1)
        XCTAssertEqual(m.messages[0].foreign, "Tidak pedas, ya.")
        XCTAssertEqual(m.messages[0].status, .ready)
        XCTAssertTrue(tr.calls.isEmpty, "短语不调用翻译")
        XCTAssertEqual(trial.used, 0, "短语不计试用")
        m.theirLanguage = "en"; m.sendPhrase(Scenario.restaurant.phrases[1])
        XCTAssertEqual(m.messages[1].foreign, "Not spicy, please.")
    }

    func testTranscriptBothViewersBilingual() async {
        let tr = FakeTranslator(); tr.table = ["太贵了": "Terlalu mahal", "5万 belum termasuk ongkos": "5万还不含车费"]
        let m = ConversationModel(translator: tr, understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        await m.receiveTheirs("50rb belum termasuk ongkos")
        await m.sendMine("太贵了")
        let utc = TimeZone(identifier: "UTC")!
        let mine = Transcript.rows(m.messages, viewer: .me, rate: .default, tz: utc)
        XCTAssertEqual(mine.map(\.side), [.leading, .trailing])
        XCTAssertEqual(mine[0].primary, m.messages[0].mainLine); XCTAssertTrue(mine[0].primary.contains("5万")); XCTAssertEqual(mine[0].secondary, "50rb belum termasuk ongkos")
        XCTAssertEqual(mine[0].chips.first?.rupiah, "Rp 50.000"); XCTAssertNotNil(mine[0].chips.first?.cny)
        XCTAssertEqual(mine[1].primary, "太贵了"); XCTAssertEqual(mine[1].secondary, "Terlalu mahal")
        XCTAssertEqual(mine[0].time.count, 5)
        let partner = Transcript.rows(m.messages, viewer: .partner, rate: .default, tz: utc)
        XCTAssertEqual(partner.map(\.side), [.trailing, .leading], "对方视角：对方自己的话在右")
        XCTAssertEqual(partner[0].primary, "50rb belum termasuk ongkos")
        XCTAssertEqual(partner[1].primary, "Terlalu mahal"); XCTAssertEqual(partner[1].secondary, "太贵了")
        XCTAssertNil(partner[0].chips.first?.cny, "对方视角不显示人民币")
    }

    func testContextTurnsCarryForeignAndScene() async {
        let tr = FakeTranslator(); tr.table = ["太贵了": "Terlalu mahal"]
        let m = ConversationModel(translator: tr, understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        await m.sendMine("太贵了")
        let ctx = m.contextTurns(excluding: UUID())
        XCTAssertEqual(ctx.first?.foreign, "Terlalu mahal")
    }

    func testHaptics() {
        XCTAssertEqual(HapticEvent.recordStart.kind, .impactMedium)
        XCTAssertEqual(HapticEvent.failed.kind, .error)
    }
}

final class CommunityPhraseTests: XCTestCase {
    func testOffAppTipParkingPickupPhrasesPresentAndPolite() {
        let flagged = Scenario.allCases.flatMap(\.phrases).filter(\.needsNativeReview)
        XCTAssertGreaterThanOrEqual(flagged.count, 9)
        for p in flagged {
            XCTAssertTrue(p.id_.contains("Pak") || p.id_.contains("Kak"), "礼貌称呼：\(p.id_)")
            XCTAssertFalse(p.en.isEmpty)
        }
        XCTAssertTrue(Scenario.ride.phrases.contains { $0.id_.contains("titik jemput") })
        XCTAssertTrue(Scenario.delivery.phrases.contains { $0.id_.contains("karcis parkir") })
        XCTAssertEqual(Set(Scenario.allCases.flatMap(\.phrases).map(\.zh)).count, Scenario.allCases.flatMap(\.phrases).count, "短语 id（中文）不重复")
    }
}
