import XCTest
@testable import TripAppModel
@testable import TripCore

final class FakeTranslator: Translating {
    var table: [String: String] = [:]
    var fail = false
    var calls: [(String, String, String)] = []
    func translate(_ text: String, from: String, to: String) async throws -> String {
        calls.append((text, from, to))
        if fail { throw NSError(domain: "t", code: 1) }
        return table[text] ?? "译:\(text)"
    }
}

final class FakeProbe: LanguagePackProbing {
    var mt: [String: PackStatus] = [:]
    var speech: [String: Readiness] = [:]
    func translationStatus(from: String, to: String) async -> PackStatus { mt["\(from)>\(to)"] ?? .installed }
    func speechReadiness(locale: String) async -> Readiness { speech[locale] ?? .ready }
}

final class StepClock: Clock, @unchecked Sendable {
    var t = Date(timeIntervalSince1970: 0)
    func now() -> Date { t }
}

/// 翻译时把时钟往前推，模拟慢翻译。
final class SlowClockTranslator: Translating {
    let clock: StepClock; let advance: TimeInterval
    init(clock: StepClock, advance: TimeInterval) { self.clock = clock; self.advance = advance }
    func translate(_ text: String, from: String, to: String) async throws -> String {
        clock.t = clock.t.addingTimeInterval(advance); return "早上好"
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    func engine(_ out: String) async -> MockEngine {
        let e = MockEngine { _ in out }
        try? await e.load(modelURL: URL(fileURLWithPath: "/dev/null"))
        return e
    }
    func trial(_ used: Int = 0) -> TrialCounter { TrialCounter(store: used >= 30 ? InMemoryTrialStore.expired() : InMemoryTrialStore()) }

    func testTheirsPlaceholderAndUnderstanding() async {
        let tr = FakeTranslator()
        tr.table["⟦N1⟧ belum termasuk ongkos"] = "⟦N1⟧还没有包括费用"
        let m = ConversationModel(translator: tr, understander: Understander(engine: await engine("5万，不含车费")), trial: trial())
        await m.receiveTheirs("50rb belum termasuk ongkos")
        let msg = m.messages[0]
        XCTAssertEqual(tr.calls.first?.0, "⟦N1⟧ belum termasuk ongkos", "金额占位后送翻译")
        XCTAssertEqual(msg.literal, "5万还没有包括费用")
        XCTAssertEqual(msg.mainLine, "5万，不含车费")
        XCTAssertEqual(msg.literalLine, "字面：5万还没有包括费用")
        XCTAssertNotEqual(m.trial.state, .notStarted, "第一条翻译开始计时")
    }

    func testPlaceholderLostFallsBack() async {
        let tr = FakeTranslator()
        tr.table["⟦N1⟧ belum termasuk ongkos"] = "还没有包括费用"
        tr.table["50rb belum termasuk ongkos"] = "50rb还没有包括费用"
        let m = ConversationModel(translator: tr, understander: nil, trial: trial())
        await m.receiveTheirs("50rb belum termasuk ongkos")
        XCTAssertEqual(m.messages[0].literal, "50rb还没有包括费用（5万）")
    }

    func testUnderstandingRejectedKeepsLiteral() async {
        let tr = FakeTranslator(); tr.table["175 deal ya"] = "175成交好吗"
        let m = ConversationModel(translator: tr, understander: Understander(engine: await engine("175万成交")), trial: trial())
        await m.receiveTheirs("175 deal ya")
        XCTAssertEqual(m.messages[0].mainLine, "175成交好吗"); XCTAssertNil(m.messages[0].literalLine)
    }

    func testUnderstandingBudgetExpired() async {
        let clock = StepClock()
        let m = ConversationModel(translator: SlowClockTranslator(clock: clock, advance: 2.98),
                                  understander: Understander(engine: await engine("早上好呀")), trial: trial(), clock: clock)
        await m.receiveTheirs("selamat pagi")
        XCTAssertEqual(m.messages[0].mainLine, "早上好", "剩余预算不足，不跑理解")
    }

    func testTrialExhausted() async {
        let m = ConversationModel(translator: FakeTranslator(), understander: Understander(engine: await engine("不应出现")), trial: trial(30))
        XCTAssertEqual(m.bannerText, "24 小时试用已结束")
        let r = await m.sendMine("太贵了"); XCTAssertEqual(r, .ok)
        XCTAssertEqual(m.messages[0].status, .trialBlocked)
        XCTAssertNil(m.messages[0].foreign)
        await m.receiveTheirs("terima kasih")
        XCTAssertEqual(m.messages[1].mainLine, "译:terima kasih", "用尽后仍有字面")
        XCTAssertFalse(m.messages[1].understood)
    }

    func testSendRules() async {
        let tr = FakeTranslator(); tr.table["太贵了"] = "Terlalu mahal"; tr.table["Terlalu mahal"] = "太贵了"
        let m = ConversationModel(translator: tr, understander: nil, trial: trial())
        var r = await m.sendMine("too expensive"); XCTAssertEqual(r, .notChinese)
        XCTAssertEqual(m.inputHint, "请用中文说你要讲的")
        r = await m.sendMine("   "); XCTAssertEqual(r, .empty)
        r = await m.sendMine("太贵了"); XCTAssertEqual(r, .ok)
        XCTAssertEqual(m.messages[0].foreign, "Terlalu mahal")
        XCTAssertTrue(m.messages[0].canCopyOrPresent)
        XCTAssertFalse(m.messages[0].showBackTranslation, "回译一致不显示")
        r = await m.sendMine("150000"); XCTAssertEqual(r, .ok)
        XCTAssertEqual(m.messages[1].foreign, "150000")
        XCTAssertEqual(tr.calls.count, 2, "纯数字不调用翻译")
        XCTAssertNotEqual(m.trial.state, .notStarted)
    }

    func testBackTranslationShownWhenInconsistent() async {
        let tr = FakeTranslator(); tr.table["我要两个"] = "Saya mau tiga"; tr.table["Saya mau tiga"] = "我要三个"
        let m = ConversationModel(translator: tr, understander: nil, trial: trial())
        await m.sendMine("我要两个")
        XCTAssertTrue(m.messages[0].showBackTranslation)
        XCTAssertEqual(m.messages[0].backTranslation, "我要三个")
    }

    func testMineRewriteForcesBackTranslationAndGuardsNumbers() async {
        let tr = FakeTranslator()
        let m = ConversationModel(translator: tr, understander: Understander(engine: await engine("刚才那个红色的就要")), trial: trial())
        await m.receiveTheirs("yang merah 50rb")
        await m.sendMine("那个就要")
        XCTAssertEqual(tr.calls.first { $0.1 == "zh-Hans" }?.0, "刚才那个红色的就要")
        XCTAssertTrue(m.messages[1].showBackTranslation, "改写后回译一定显示")
        let tr2 = FakeTranslator()
        let m2 = ConversationModel(translator: tr2, understander: Understander(engine: await engine("那个4万的")), trial: trial())
        await m2.receiveTheirs("ini 40rb")
        await m2.sendMine("那个40的")
        XCTAssertEqual(tr2.calls.first { $0.1 == "zh-Hans" }?.0, "那个40的", "数字被改动则用原文")
    }

    func testTranslationFailure() async {
        let tr = FakeTranslator(); tr.fail = true
        let m = ConversationModel(translator: tr, understander: nil, trial: trial())
        await m.receiveTheirs("halo")
        XCTAssertEqual(m.messages[0].status, .failed); XCTAssertEqual(m.messages[0].mainLine, "这句还没翻译出来")
        XCTAssertEqual(m.trial.state, .notStarted, "失败不开始计时")
    }

    func testRetranslateOffer() async {
        let tr = FakeTranslator()
        let m = ConversationModel(translator: tr, understander: nil, trial: trial())
        await m.receiveTheirs("please wait for me")
        XCTAssertEqual(m.messages[0].offerRetranslateAs, "en")
        await m.retranslate(m.messages[0].id, as: "en")
        XCTAssertEqual(tr.calls.last?.1, "en"); XCTAssertNil(m.messages[0].offerRetranslateAs)
        XCTAssertEqual(m.theirLanguage, "id", "开关不变")
        XCTAssertNotEqual(m.trial.state, .notStarted)
    }

    func testGate() async {
        let p = FakeProbe()
        var model: Readiness = .needsDownload(bytes: 1_117_320_736)
        let d = UserDefaults(suiteName: "g-\(UUID())")!
        let g = AppGate(tier: .b6GB, probe: p, modelReadiness: { model }, defaults: d)
        var r = await g.refresh(.coldLaunch); XCTAssertEqual(r, .onboarding)
        model = .ready
        r = await g.refresh(.downloadFinished); XCTAssertEqual(r, .open)
        XCTAssertTrue(g.onboardingCompleted)
        p.mt["zh-Hans>id"] = .supported
        r = await g.refresh(.foreground); XCTAssertEqual(r, .block(missing: [.translation("id")]))
        XCTAssertEqual(AppGate.missingText([.translation("id"), .understander]), "印尼语翻译、理解能力")
        p.mt = [:]; p.speech["id-ID"] = .unavailable("听印尼语暂不可用")
        r = await g.refresh(.foreground); XCTAssertEqual(r, .open)
        model = .downloading(progress: 0.3)
        r = await g.refresh(.foreground); XCTAssertEqual(r, .showProgress)
        model = .ready
        r = await AppGate(tier: .unsupported, probe: p, modelReadiness: { model }, defaults: d).refresh(.coldLaunch)
        XCTAssertEqual(r, .unsupportedDevice)
    }

    func testPrepareRows() {
        let s = PrepareStatus(items: [.touristSpeech: .ready, .translation("id"): .needsDownload(bytes: nil), .speech("id"): .unavailable("听印尼语暂不可用"),
                                      .translation("en"): .ready, .speech("en"): .ready, .understander: .downloading(progress: 0.426)])
        let rows = PrepareRows.rows(status: s, theirLanguages: ["id", "en"])
        XCTAssertEqual(rows.map(\.title), ["中文听写", "印尼语翻译", "印尼语听写", "英语翻译", "英语听写", "理解能力"])
        XCTAssertEqual(rows[1].state, "需要下载"); XCTAssertTrue(rows[1].actionable)
        XCTAssertEqual(rows[2].state, "听印尼语暂不可用"); XCTAssertFalse(rows[2].actionable)
        XCTAssertEqual(rows[5].state, "下载中 43%")
        XCTAssertEqual(PrepareRows.text(.needsDownload(bytes: 1_117_320_736)), "需要下载 · 约 1.1 GB")
        XCTAssertEqual(PrepareRows.text(.notEnoughSpace(needed: 300_000_000)), "空间不够，还需要约 300 MB")
        XCTAssertEqual(PrepareRows.cellularPrompt(bytes: 1_117_320_736), "当前不是 Wi‑Fi，要用流量下载约 1.1 GB吗？")
    }

    func testClipboard() {
        let c = ClipboardHint()
        c.onForeground(hasStrings: true, changeCount: 7); XCTAssertTrue(c.visible)
        c.dismiss(); c.onForeground(hasStrings: true, changeCount: 7); XCTAssertFalse(c.visible)
        c.onForeground(hasStrings: true, changeCount: 8); XCTAssertTrue(c.visible)
        XCTAssertNil(c.accept("yang tadi 40 saja", lastSource: "yang tadi 40 saja")); XCTAssertEqual(c.notice, "这句已经在对话里了")
        XCTAssertEqual(c.accept(String(repeating: "a", count: 600), lastSource: nil)?.count, 500); XCTAssertEqual(c.notice, "只保留前 500 字")
        c.onForeground(hasStrings: false, changeCount: 9); XCTAssertFalse(c.visible)
    }

    func testBackTranslationRule() {
        XCTAssertTrue(BackTranslation.consistent(original: "太贵了", back: "太贵了！"))
        XCTAssertFalse(BackTranslation.consistent(original: "我要2个", back: "我要3个"))
        XCTAssertFalse(BackTranslation.consistent(original: "不要辣", back: "要辣"))
        XCTAssertFalse(BackTranslation.consistent(original: "去机场", back: "我们去海边玩"))
    }
}
