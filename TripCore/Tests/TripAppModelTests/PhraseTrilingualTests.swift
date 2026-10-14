import XCTest
@testable import TripAppModel

final class PhraseTrilingualP6Tests: XCTestCase {
    func han(_ s: String) -> Bool { s.unicodeScalars.contains { $0.properties.isIdeographic } }

    func testEveryPhraseHasThreeLanguages() {
        for s in Scenario.allCases { for p in s.phrases {
            for l in Lang.all { XCTAssertFalse(p.text(l).trimmingCharacters(in: .whitespaces).isEmpty, "\(s) \(p.zh) \(l)") }
            XCTAssertTrue(han(p.zh), p.zh); XCTAssertFalse(han(p.en), p.en); XCTAssertFalse(han(p.id_), p.id_)
            XCTAssertLessThanOrEqual(p.en.count, 90, "出示页长度上限：\(p.en)")
            XCTAssertLessThanOrEqual(p.id_.count, 90, "出示页长度上限：\(p.id_)")
            XCTAssertNotEqual(p.en.lowercased(), p.id_.lowercased(), "英文与印尼语不应相同：\(p.en)")
        }}
    }

    func testSceneTitlesThreeLanguages() {
        for s in Scenario.allCases {
            for l in ["en", "id"] {
                XCTAssertFalse(han(s.title(for: l)), "\(s) \(l)"); XCTAssertFalse(han(s.subtitle(for: l)))
                XCTAssertFalse(s.title(for: l).isEmpty)
            }
            XCTAssertTrue(han(s.title(for: "zh-Hans")))
            XCTAssertFalse(han(s.contextName(for: "en")))
        }
        XCTAssertEqual(Scenario.restaurant.title(for: "en"), "Restaurant")
    }

    func testTitleFollowsUILanguage() {
        L10n.uiLanguage = "en"; defer { L10n.uiLanguage = "zh-Hans" }
        XCTAssertEqual(Scenario.money.title, "Money exchange · ATM")
    }

    func testPresentUsesMyLanguage() {
        let p = Scenario.chat.phrases[0]
        XCTAssertEqual(PhraseBook.present(p, lang: "id", myLanguage: "en").small, p.en)
        XCTAssertEqual(PhraseBook.present(p, lang: "zh-Hans", myLanguage: "id").big, p.zh)
        XCTAssertEqual(PhraseBook.present(p, lang: "id").small, p.zh)
    }

    /// 常用句不得出现在公开评测集（FLORES devtest / Tatoeba 抽样）中，避免污染
    func testNoOverlapWithPublicEval() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../finetune/public_data/public_eval.jsonl").standardized
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { throw XCTSkip("public_eval.jsonl 不在") }
        let srcs = Set(data.split(separator: "\n").compactMap { l -> String? in
            (try? JSONSerialization.jsonObject(with: Data(l.utf8))) .flatMap { ($0 as? [String: Any])?["src"] as? String }?.lowercased()
        })
        // 两三个词的通用寒暄（如 Terima kasih.）重合不可避免也无害，只查 ≥4 词的句子
        for s in Scenario.allCases { for p in s.phrases where p.id_.split(separator: " ").count >= 4 { XCTAssertFalse(srcs.contains(p.id_.lowercased()), p.id_) } }
    }
}
