import XCTest
import TripCore
@testable import TripAppModel

/// 记录每次翻译的方向，返回「[from>to]原文」
final class RecordingTranslator: Translating {
    var calls: [(String, String, String)] = []
    func translate(_ text: String, from: String, to: String) async throws -> String {
        calls.append((text, from, to)); return "[\(from)>\(to)]\(text)"
    }
}

@MainActor
final class TrilingualP1Tests: XCTestCase {
    func model(_ me: String, _ them: String) -> (ConversationModel, RecordingTranslator) {
        let tr = RecordingTranslator()
        let m = ConversationModel(translator: tr, understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        m.myLanguage = me; m.theirLanguage = them
        return (m, tr)
    }

    func testRouteTable() {
        let L = Lang.all
        for f in L { for t in L {
            let r = LangRoute.route(from: f, to: t)
            if f == t { XCTAssertEqual(r, .same, "\(f)>\(t)") }
            else if t == "zh-Hans" { XCTAssertEqual(r, .translateAndUnderstand, "\(f)>\(t)") }
            else if PromptBuilder.supportsUnderstanding(target: t) && f != "zh-Hans" { XCTAssertEqual(r, .translateAndUnderstand) }
            else { XCTAssertEqual(r, .translate, "\(f)>\(t)") }
        }}
        XCTAssertEqual(LangRoute.route(from: "zh-CN", to: "zh-Hans"), .same)
        XCTAssertEqual(Lang.normalize("en-US"), "en"); XCTAssertEqual(Lang.normalize("id-ID"), "id"); XCTAssertEqual(Lang.normalize("in"), "id")
    }

    func testAllNinePairsSendMine() async {
        let sample = ["zh-Hans": "你好", "id": "Halo kak", "en": "Hello there"]
        for me in Lang.all { for them in Lang.all {
            let (m, tr) = model(me, them)
            let r = await m.sendMine(sample[me]!)
            XCTAssertEqual(r, .ok, "\(me)>\(them)")
            let msg = m.messages[0]
            XCTAssertEqual(msg.sourceLocale, me)
            if me == them {
                XCTAssertEqual(msg.foreign, sample[me]); XCTAssertTrue(tr.calls.isEmpty)
            } else {
                XCTAssertEqual(msg.foreign, "[\(me)>\(them)]\(sample[me]!)")
                XCTAssertEqual(tr.calls.last?.1, them); XCTAssertEqual(tr.calls.last?.2, me)   // 回译
            }
        }}
    }

    func testAllNinePairsReceive() async {
        let sample = ["zh-Hans": "太贵了", "id": "Mahal sekali", "en": "Too expensive"]
        for me in Lang.all { for them in Lang.all {
            let (m, tr) = model(me, them)
            await m.receiveTheirs(sample[them]!)
            let msg = m.messages[0]
            if me == them { XCTAssertEqual(msg.literal, sample[them]); XCTAssertTrue(tr.calls.isEmpty) }
            else { XCTAssertEqual(msg.literal, "[\(them)>\(me)]\(sample[them]!)"); XCTAssertEqual(msg.status, .ready) }
        }}
    }

    func testZhIdUnchanged() async {
        let (m, tr) = model("zh-Hans", "id")
        await m.receiveTheirs("harga 50rb")
        XCTAssertEqual(tr.calls[0].1, "id"); XCTAssertEqual(tr.calls[0].2, "zh-Hans")
        XCTAssertTrue(tr.calls[0].0.contains("⟦N1⟧"), "中文目标仍用金额占位")
        let r = await m.sendMine("too expensive"); XCTAssertEqual(r, .notChinese)
    }

    func testCheckPerLanguage() {
        XCTAssertEqual(ConversationModel.check("太贵了", lang: "en"), .wrongLanguage)
        XCTAssertEqual(ConversationModel.check("too expensive", lang: "en"), .ok)
        XCTAssertEqual(ConversationModel.check("mahal", lang: "id"), .ok)
        XCTAssertEqual(ConversationModel.check("50000", lang: "id"), .ok)
        XCTAssertEqual(ConversationModel.check("  ", lang: "en"), .empty)
        XCTAssertEqual(ConversationModel.check("mahal", lang: "zh-Hans"), .notChinese)
    }

    func testPhraseUsesBothLanguages() {
        let (m, _) = model("en", "id")
        let p = Scenario.restaurant.phrases[1]
        m.sendPhrase(p)
        XCTAssertEqual(m.messages[0].source, p.en); XCTAssertEqual(m.messages[0].foreign, p.id_)
        let (m2, _) = model("id", "zh-Hans"); m2.sendPhrase(p)
        XCTAssertEqual(m2.messages[0].source, p.id_); XCTAssertEqual(m2.messages[0].foreign, p.zh)
    }

    func testLanguageGuessThreeWay() {
        let zh = ["太贵了", "你好，多少钱？", "我在大门口等你", "这个不要", "司机到了吗"]
        let id = ["harganya berapa kak", "udah sampai belum ya", "ini bisa kurang gak", "saya di depan pintu", "tidak ada uang kecil"]
        let en = ["how much is this please", "wait for me at the gate", "where is the toilet", "this is not the price", "can you please hurry"]
        for s in zh { XCTAssertEqual(LanguageGuess.guess(s), "zh-Hans", s) }
        for s in id { XCTAssertEqual(LanguageGuess.guess(s), "id", s) }
        for s in en { XCTAssertEqual(LanguageGuess.guess(s), "en", s) }
        XCTAssertNil(LanguageGuess.guess("ok"))
        XCTAssertNil(LanguageGuess.guess("Grab 司机 is here harga"), "混写且汉字少 → 不猜")
    }

    func testBackTranslationNegationAcrossLanguages() {
        XCTAssertFalse(BackTranslation.consistent(original: "not spicy please", back: "spicy please"))
        XCTAssertTrue(BackTranslation.consistent(original: "not spicy please", back: "not spicy please"))
        XCTAssertFalse(BackTranslation.consistent(original: "harga 50", back: "harga 60"))
    }
}

@MainActor
final class TrilingualP2Tests: XCTestCase {
    func testEnglishViewerTranscript() async {
        let tr = RecordingTranslator()
        let m = ConversationModel(translator: tr, understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        m.myLanguage = "en"; m.theirLanguage = "id"
        await m.receiveTheirs("harganya 100rb kak")
        XCTAssertEqual(m.messages[0].literal, "[id>en]harganya Rp 100,000 kak")
        let rows = Transcript.rows(m.messages, viewer: .me, rate: nil, fx: FXContext(rates: .bundled, currency: .usd), lang: "en")
        XCTAssertTrue(rows[0].primary.contains("Rp 100,000 (≈ $5.6)"), rows[0].primary)
        XCTAssertEqual(rows[0].chips.first?.cny, "≈ $5.6")
    }

    func testIndonesianViewerReverse() async {
        let tr = RecordingTranslator()
        let m = ConversationModel(translator: tr, understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        m.myLanguage = "id"; m.theirLanguage = "zh-Hans"
        await m.receiveTheirs("给你200块")
        let rows = Transcript.rows(m.messages, viewer: .me, rate: nil, fx: FXContext(rates: .bundled, currency: .idr), lang: "id")
        XCTAssertEqual(rows[0].note, "¥200≈Rp 536.000")
        XCTAssertNil(rows[0].chips.first?.cny)
    }

    func testZhViewerUnchanged() async {
        let m = ConversationModel(translator: UITestTranslator(), understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        await m.receiveTheirs(UITestMode.seedAmountText)
        let rows = Transcript.rows(m.messages, viewer: .me, rate: nil, fx: FXContext(rates: .bundled, currency: .cny))
        XCTAssertEqual(rows[0].primary, "价格是10万（约 ¥37）")
    }
}
