import XCTest
import TripCore
@testable import TripAppModel

final class TalkRouterTests: XCTestCase {
    func msg(_ r: Role) -> Message { var m = Message(id: UUID(), role: r, createdAt: Date(), source: "x", sourceLocale: "id"); m.status = .ready; return m }
    func testPredictAlternates() {
        XCTAssertEqual(TalkRouter.predict(messages: []), .me)
        XCTAssertEqual(TalkRouter.predict(messages: [msg(.them)]), .me)
        XCTAssertEqual(TalkRouter.predict(messages: [msg(.them), msg(.me)]), .them)
        XCTAssertEqual(TalkRouter.predict(messages: [msg(.me)], forced: .me), .me)
    }
    func testResolveFlipsOnClearScript() {
        XCTAssertEqual(TalkRouter.resolve(.me, text: "harganya berapa ya kak", myLanguage: "zh-Hans", theirLanguage: "id"), .them)
        XCTAssertEqual(TalkRouter.resolve(.them, text: "太贵了能便宜点吗", myLanguage: "zh-Hans", theirLanguage: "id"), .me)
        XCTAssertEqual(TalkRouter.resolve(.me, text: "太贵了", myLanguage: "zh-Hans", theirLanguage: "id"), .me)
        XCTAssertEqual(TalkRouter.resolve(.them, text: "ok", myLanguage: "zh-Hans", theirLanguage: "id"), .them)
    }
    @MainActor func testRemove() async {
        let c = ConversationModel(translator: UITestTranslator(), understander: nil, trial: TrialCounter(store: InMemoryTrialStore()), metrics: nil)
        c.sendPhrase(Phrase("谢谢", id: "Terima kasih", en: "Thank you"))
        XCTAssertEqual(c.messages.count, 1)
        c.remove(c.messages[0].id)
        XCTAssertTrue(c.messages.isEmpty)
    }
}
