import XCTest
@testable import TripAppModel
import TripCore

final class FakeTranscriber: Transcribing {
    var started: [String] = []; var cancelled = 0; var text = "bisa kurang"; var fail = false
    func start(locale: String) async throws { if fail { throw NSError(domain: "s", code: 1) }; started.append(locale) }
    func finish() async -> String { text }
    func cancel() { cancelled += 1 }
}

final class SessionStoreTests: XCTestCase {
    var dir: URL!
    var t = Date(timeIntervalSince1970: 1_000_000)
    override func setUp() { dir = FileManager.default.temporaryDirectory.appendingPathComponent("s-\(UUID())") }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }
    func store() -> SessionStore { SessionStore(directory: dir, now: { [unowned self] in self.t }) }
    func msg(_ s: String, _ status: MessageStatus = .ready) -> Message {
        var m = Message(id: UUID(), role: .them, createdAt: t, source: s, sourceLocale: "id"); m.literal = "字面"; m.status = status; return m
    }

    func testSaveRestoreAndFourHours() throws {
        let st = store()
        XCTAssertEqual(st.load(), .empty)
        var s = try st.startNew(theirLanguage: "id", deletePrevious: false)
        s.messages = [msg("50rb"), msg("yang tadi 40 saja")]
        try st.save(s)
        guard case .restored(let r) = store().load() else { return XCTFail() }
        XCTAssertEqual(r.messages.map(\.source), ["50rb", "yang tadi 40 saja"])
        XCTAssertEqual(r.messages[0].literal, "字面")
        t = t.addingTimeInterval(4 * 3600)
        guard case .askContinue(let a) = store().load() else { return XCTFail("4 小时应询问") }
        try store().touch(a)
        guard case .restored = store().load() else { return XCTFail("继续后不再询问") }
    }

    func testCorruptBackedUp() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{oops".utf8).write(to: store().current)
        XCTAssertEqual(store().load(), .corrupt)
        XCTAssertTrue(store().fileNames().contains { $0.hasPrefix("session-corrupt-") })
        XCTAssertEqual(store().load(), .empty)
    }

    func testNewConversationAndDeleteAll() throws {
        let st = store()
        var s = try st.startNew(theirLanguage: "id", deletePrevious: false); s.messages = [msg("a")]; try st.save(s)
        t = t.addingTimeInterval(10)
        _ = try st.startNew(theirLanguage: "en", deletePrevious: false)
        XCTAssertEqual(st.fileNames().filter { $0.hasPrefix("session-") && $0 != "session-current.json" }.count, 1, "上一场归档")
        t = t.addingTimeInterval(10)
        var s2 = try st.startNew(theirLanguage: "en", deletePrevious: true); s2.messages = [msg("b")]; try st.save(s2)
        XCTAssertEqual(st.fileNames().count, 2, "勾选删除上一场则不归档")
        try st.deleteAll()
        XCTAssertTrue(st.fileNames().isEmpty)
        XCTAssertEqual(st.load(), .empty)
    }

    @MainActor
    func testConversationPersistsAndRestoresWithoutHalfBubbles() async throws {
        let st = store()
        var session = try st.startNew(theirLanguage: "id", deletePrevious: false)
        let tr = FakeTranslator()
        let m = ConversationModel(translator: tr, understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        m.onPersist = { msgs in session.messages = msgs; try? st.save(session) }
        await m.receiveTheirs("terima kasih")
        await m.sendMine("太贵了")
        guard case .restored(let r) = store().load() else { return XCTFail() }
        XCTAssertEqual(r.messages.count, 2)
        // 模拟识别/翻译中被杀掉
        var killed = r; killed.messages.append(msg("halo", .translating)); try st.save(killed)
        guard case .restored(let r2) = store().load() else { return XCTFail() }
        let m2 = ConversationModel(translator: tr, understander: nil, trial: TrialCounter(store: InMemoryTrialStore()))
        m2.restore(r2.messages)
        XCTAssertEqual(m2.messages.count, 3)
        XCTAssertEqual(m2.messages[2].status, .failed, "翻译中的消息恢复为失败，不卡在正在看")
        XCTAssertFalse(m2.isTranslating)
    }

    func testCleanup() throws {
        let st = store()
        _ = try st.startNew(theirLanguage: "id", deletePrevious: false)
        let old = dir.appendingPathComponent("session-1.json"), bad = dir.appendingPathComponent("session-corrupt-1.json")
        try Data().write(to: old); try Data().write(to: bad)
        let past = t.addingTimeInterval(-8 * 86400)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: bad.path)
        st.cleanup()
        XCTAssertTrue(st.fileNames().contains("session-1.json"), "归档 8 天不删")
        XCTAssertFalse(st.fileNames().contains("session-corrupt-1.json"), "损坏备份 7 天后删")
        t = t.addingTimeInterval(23 * 86400); st.cleanup()
        XCTAssertFalse(st.fileNames().contains("session-1.json")); XCTAssertTrue(st.fileNames().contains("session-current.json"))
    }
}

@MainActor
final class HoldToTalkTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 0)

    func testShortPressNoMessage() async {
        let tr = FakeTranscriber(); let h = HoldToTalk(transcriber: tr)
        h.press(.them, locale: "id-ID", at: t0)
        let mid = await h.tick(at: t0.addingTimeInterval(0.2)); XCTAssertNil(mid)
        let r = await h.release(at: t0.addingTimeInterval(0.25))
        XCTAssertEqual(r, .none); XCTAssertTrue(tr.started.isEmpty); XCTAssertEqual(h.phase, .idle)
    }

    func testRecordAndRelease() async {
        let tr = FakeTranscriber(); let h = HoldToTalk(transcriber: tr)
        h.press(.them, locale: "id-ID", at: t0)
        _ = await h.tick(at: t0.addingTimeInterval(0.31))
        XCTAssertEqual(h.phase, .recording(.them)); XCTAssertEqual(tr.started, ["id-ID"])
        XCTAssertEqual(h.buttonTitle.them, "松手翻译，上滑取消")
        let r = await h.release(at: t0.addingTimeInterval(2))
        XCTAssertEqual(r, .text("bisa kurang", .them))
    }

    func testSlideUpCancels() async {
        let tr = FakeTranscriber(); let h = HoldToTalk(transcriber: tr)
        h.press(.me, locale: "zh-CN", at: t0); _ = await h.tick(at: t0.addingTimeInterval(0.5))
        h.drag(dy: -50); XCTAssertEqual(h.phase, .recording(.me))
        h.drag(dy: -90); XCTAssertEqual(h.phase, .cancelZone(.me))
        h.drag(dy: -10); XCTAssertEqual(h.phase, .recording(.me), "滑回来恢复")
        h.drag(dy: -120)
        let r = await h.release(at: t0.addingTimeInterval(1))
        XCTAssertEqual(r, .cancelled); XCTAssertEqual(tr.cancelled, 1); XCTAssertEqual(h.feedback, "已取消")
    }

    func testEmptyAndMaxDurationAndBackground() async {
        let tr = FakeTranscriber(); tr.text = "  "; let h = HoldToTalk(transcriber: tr)
        h.press(.them, locale: "en-US", at: t0); _ = await h.tick(at: t0.addingTimeInterval(0.4))
        let r = await h.release(at: t0.addingTimeInterval(1)); XCTAssertEqual(r, .empty); XCTAssertEqual(h.feedback, "没听清，按住再说一次")
        tr.text = "please wait"
        h.press(.them, locale: "en-US", at: t0); _ = await h.tick(at: t0.addingTimeInterval(0.4))
        let auto = await h.tick(at: t0.addingTimeInterval(30.31)); XCTAssertEqual(auto, .text("please wait", .them), "30 秒自动松手")
        h.press(.them, locale: "en-US", at: t0); _ = await h.tick(at: t0.addingTimeInterval(0.4))
        h.enterBackground(); XCTAssertEqual(h.phase, .idle); XCTAssertEqual(tr.cancelled, 1)
        tr.fail = true
        h.press(.them, locale: "en-US", at: t0)
        let f = await h.tick(at: t0.addingTimeInterval(0.4)); XCTAssertEqual(f, .failed); XCTAssertEqual(h.phase, .idle)
    }
}

@MainActor
final class PartnerTalkTests: XCTestCase {
    final class T: Transcribing {
        var text = "Kak, saya di lobi"; var locales: [String] = []
        func start(locale: String) async throws { locales.append(locale) }
        func finish() async -> String { text }
        func cancel() {}
    }
    func testPartnerButtonRecordsTheirLanguageAndGoesToTheirs() async {
        let t = T(); let h = HoldToTalk(transcriber: t); let t0 = Date()
        XCTAssertEqual(h.partnerTitle(lang: "id"), "Tahan untuk bicara")
        XCTAssertEqual(h.partnerTitle(lang: "en"), "Hold to talk")
        h.press(.them, locale: "id-ID", at: t0)
        _ = await h.tick(at: t0.addingTimeInterval(0.4))
        XCTAssertTrue(h.partnerTitle(lang: "id").hasPrefix("Lepas"))
        h.press(.me, locale: "zh-CN", at: t0)          // 我这边同时按下被忽略（一次只录一个人）
        XCTAssertEqual(h.phase, .recording(.them))
        let o = await h.release(at: t0.addingTimeInterval(2))
        XCTAssertEqual(o, .text("Kak, saya di lobi", .them)); XCTAssertEqual(t.locales, ["id-ID"])
    }
    func testPartnerCancel() async {
        let h = HoldToTalk(transcriber: T()); let t0 = Date()
        h.press(.them, locale: "id-ID", at: t0); _ = await h.tick(at: t0.addingTimeInterval(0.5))
        h.drag(dy: -100)
        let o = await h.release(at: t0.addingTimeInterval(1)); XCTAssertEqual(o, .cancelled)
    }
}
