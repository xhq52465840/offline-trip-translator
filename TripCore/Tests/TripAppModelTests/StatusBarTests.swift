import XCTest
import TripCore
@testable import TripAppModel

final class StatusBarTests: XCTestCase {
    func st(_ model: Readiness, _ pack: Readiness) -> PrepareStatus {
        PrepareStatus(items: [.understander: model, .translation("id"): pack, .touristSpeech: .ready])
    }
    func testReadyHidden() { XCTAssertNil(StatusBar.compute(status: st(.ready, .ready), partner: "id", online: false)) }
    func testUnsupportedPackCountsAsOK() { XCTAssertNil(StatusBar.compute(status: st(.ready, .unavailable("x")), partner: "id", online: true)) }
    func testDownloadingPercent() {
        XCTAssertEqual(StatusBar.compute(status: st(.downloading(progress: 0.28), .ready), partner: "id", online: true)?.kind, .modelPreparing(percent: 28))
    }
    func testModelMissing() {
        XCTAssertEqual(StatusBar.compute(status: st(.needsDownload(bytes: 1), .ready), partner: "id", online: true)?.kind, .modelPreparing(percent: nil))
    }
    func testPackMissing() {
        XCTAssertEqual(StatusBar.compute(status: st(.ready, .needsDownload(bytes: nil)), partner: "id", online: true)?.kind, .packMissing("id"))
    }
    func testBothMissing() {
        let b = StatusBar.compute(status: st(.needsDownload(bytes: 1), .needsDownload(bytes: nil)), partner: "id", online: true)
        XCTAssertEqual(b?.kind, .nothingReady); XCTAssertTrue(b!.isWarning)
    }
    func testOfflineNeedingDownload() {
        XCTAssertEqual(StatusBar.compute(status: st(.needsDownload(bytes: 1), .ready), partner: "id", online: false)?.kind, .waitingNetwork)
    }
    func testTextsLocalized() {
        L10n.uiLanguage = "en"; defer { L10n.uiLanguage = "zh-Hans" }
        XCTAssertEqual(StatusBar(kind: .modelPreparing(percent: 28)).text, "Preparing understanding 28%")
        XCTAssertFalse(StatusBar(kind: .packMissing("id")).text.contains("离线"))
    }
}
