import XCTest

/// 关键路径 UI 测试（模拟器，无需下载模型 / Apple Translation）。
/// App 以 `-UITestMode <mode>` 启动（DEBUG 才生效），见 TripAppModel.UITestMode。
/// 截图：作为 XCTAttachment 保留；若设置环境变量 SCREEN_DIR（xcodebuild 用 TEST_RUNNER_SCREEN_DIR=...），同时写 PNG 到该目录。
final class TripUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func launch(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", mode, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        return app
    }

    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = ProcessInfo.processInfo.environment["SCREEN_DIR"], !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func testOnboardingShows() {
        let app = launch("mock-onboarding")
        XCTAssertTrue(app.staticTexts["onboardingTitle"].waitForExistence(timeout: 10))
        shot("01_onboarding")
    }

    func testBlockingSheetOnLaunchWhenNotReady() {
        let app = launch("mock-not-ready")
        XCTAssertTrue(app.staticTexts["blockingTitle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["去下载"].exists)
        shot("02_blocking_sheet")
    }

    func testPhraseBookFromBlockingSheetAndPresent() {
        let app = launch("mock-not-ready")
        let link = app.buttons["blockingPhraseBook"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'phrase_'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        shot("03_phrasebook")
        first.tap()
        XCTAssertTrue(app.staticTexts["presentText"].waitForExistence(timeout: 5))
        shot("04_present_fullscreen")
        app.buttons["presentClose"].tap()
    }

    func testPurchasePageOpens() {
        let app = launch("mock-onboarding")
        let link = app.buttons["购买 / 恢复购买"]
        if !link.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.buttons["恢复购买"].waitForExistence(timeout: 10))
        sleep(2)   // 等 StoreKit 本地配置的价格加载
        shot("05_purchase")
    }

    func testHomeAndChatWithMockEngine() {
        let app = launch("mock-ready")
        let start = app.buttons["startChat"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        shot("06_home")
        start.tap()
        let input = app.textFields["chatInput"].exists ? app.textFields["chatInput"] : app.textViews["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("太贵了")
        app.buttons["sendButton"].tap()
        XCTAssertTrue(app.staticTexts["Terlalu mahal"].waitForExistence(timeout: 10), "假翻译结果应出现")
        shot("07_chat_sent")
    }

    func testAmountConversionShown() {
        // 金额换算（PRD v2 §7.9）：对方「Rp 100.000」→ 气泡里出现「约 ¥37」与汇率日期
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "mock-ready", "-UITestSeedAmount", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["startChat"].tap()
        let conv = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '约 ¥37'")).firstMatch
        XCTAssertTrue(conv.waitForExistence(timeout: 10), "应显示 约 ¥37（100.000 / 2677.5）")
        XCTAssertTrue(app.staticTexts["rateCaption"].exists)
        XCTAssertTrue(app.staticTexts["rateCaption"].label.contains("2026-10-12"))
        shot("08_amount_conversion")
    }

    func testAmountConversionShownEnglish() {
        // 英文系统 → 美元：Rp 100.000 → ≈ $5.6（100000 / 17920）
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "mock-ready", "-UITestSeedAmount", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.buttons["startChat"].tap()
        let conv = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '$5.6'")).firstMatch
        XCTAssertTrue(conv.waitForExistence(timeout: 10), "英文环境应显示 ≈ $5.6")
        shot("08_amount_conversion_en")
    }

    func testLaunchMemoryMetric() {
        // 基本指标（无需 Instruments）：启动到首页的内存与时间
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "mock-ready"]
        measure(metrics: [XCTMemoryMetric(application: app), XCTApplicationLaunchMetric()], options: {
            let o = XCTMeasureOptions(); o.iterationCount = 3; return o
        }()) {
            app.launch()
            _ = app.buttons["startChat"].waitForExistence(timeout: 10)
            app.terminate()
        }
    }
}
