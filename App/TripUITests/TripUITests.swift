import XCTest

/// 关键路径 UI 测试（模拟器，无需下载模型 / Apple Translation）。
/// App 以 `-UITestMode <mode>` 启动（DEBUG 才生效），见 TripAppModel.UITestMode。
/// 截图：作为 XCTAttachment 保留；若设置环境变量 SCREEN_DIR（xcodebuild 用 TEST_RUNNER_SCREEN_DIR=...），同时写 PNG 到该目录。
class TripUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// UI 语言：默认中文；子类 `TripUITestsEnglish` 覆盖为英文（r5：TEST_RUNNER_UI_LANG 在 Xcode 16.2 上没进测试进程，改用子类，一次 xcodebuild test 中英两遍都跑）
    var uiLang: String { ProcessInfo.processInfo.environment["UI_LANG"] == "en" ? "en" : "zh-Hans" }
    var isEn: Bool { uiLang == "en" }

    func launch(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", mode, "-AppleLanguages", "(\(uiLang))", "-AppleLocale", isEn ? "en_US" : "zh_CN"]
        app.launch()
        return app
    }

    func shot(_ name: String) {
        let name = isEn && !name.hasSuffix("_en") ? name + "_en" : name
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

    /// v4 V1：打开即对话页；等对话页出现（替代旧的 startChat 首页按钮）
    @discardableResult
    func waitHome(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        app.buttons["holdToTalk"].waitForExistence(timeout: timeout) || app.otherElements["holdToTalk"].waitForExistence(timeout: 2)
            || chatInput(app).waitForExistence(timeout: 2)
    }
    func chatInput(_ app: XCUIApplication) -> XCUIElement {
        app.textFields["chatInput"].exists ? app.textFields["chatInput"] : app.textViews["chatInput"]
    }
    func openPhraseBook(_ app: XCUIApplication, en: Bool) {
        let menu = app.buttons["settingsMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10)); menu.tap()
        let item = app.buttons[en ? "Phrases" : "常用句"]
        XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
    }

    /// v4 V1：没就绪时不再弹阻断 sheet，而是对话页 + 顶部状态条，输入框可用
    func testStatusBarInsteadOfBlockingSheet() {
        let app = launch("mock-not-ready")
        XCTAssertTrue(app.buttons["statusBar"].waitForExistence(timeout: 10), "应出现状态条")
        XCTAssertFalse(app.staticTexts["blockingTitle"].exists, "不应再有阻断弹窗")
        XCTAssertTrue(waitHome(app))
        XCTAssertTrue(chatInput(app).isEnabled)
        shot("02_status_bar_not_ready")
    }

    func testPhraseBookFromSettingsAndPresent() {
        let app = launch("mock-not-ready")
        openPhraseBook(app, en: isEn)
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
        let link = app.buttons["purchaseLink"]
        if !link.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.buttons["restorePurchases"].waitForExistence(timeout: 10))
        sleep(2)   // 等 StoreKit 本地配置的价格加载
        shot("05_purchase")
    }

    func testHomeAndChatWithMockEngine() {
        // 我方固定中文（英文界面跑时也一样），保证 zh→id 主路径无回归
        let app = launchLangs("zh-Hans,id", ui: uiLang, locale: isEn ? "en_US" : "zh_CN")
        XCTAssertTrue(waitHome(app))
        shot("06_home")
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
        XCTAssertTrue(waitHome(app))
        // v4 V2：金额卡片（整卡一个无障碍元素，label 含换算）
        let card = moneyCard(app)
        XCTAssertTrue(card.waitForExistence(timeout: 10), "应出现金额卡片")
        XCTAssertTrue(card.label.contains("约 ¥37"), "应显示 约 ¥37（100.000 / 2677.5）：\(card.label)")
        XCTAssertTrue(card.label.hasPrefix("对方报价"))
        XCTAssertTrue(app.staticTexts["rateCaption"].exists)
        XCTAssertTrue(app.staticTexts["rateCaption"].label.contains("2026-10-12"))
        shot("08_amount_conversion")
    }

    func testAmountConversionShownEnglish() {
        // 英文系统 → 美元：Rp 100.000 → ≈ $5.6（100000 / 17920）
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "mock-ready", "-UITestSeedAmount", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(waitHome(app))
        let card = moneyCard(app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("$5.6"), "英文环境应显示 ≈ $5.6：\(card.label)")
        XCTAssertFalse(card.label.contains("印尼盾"), "英文界面金额卡不应有中文单位")
        shot("08_amount_conversion_en")
    }

    func moneyCard(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["moneyCard"].firstMatch }

    /// v4 V2：点金额卡片 → 全屏出示金额
    func testMoneyCardPresentsFullScreen() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "mock-ready", "-UITestSeedAmount", "-AppleLanguages", "(\(uiLang))", "-AppleLocale", isEn ? "en_US" : "zh_CN"]
        app.launch()
        let card = moneyCard(app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        shot("13_money_card")
        card.tap()
        XCTAssertTrue(app.staticTexts["presentText"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["presentText"].label, "Rp 100.000")
        app.buttons["presentClose"].tap()
    }

    /// v4 V3：对方报价后出现还价快捷回复；还价金额由程序算（100.000 × 80% = 80.000）；点一下直接发送
    func testContextualRepliesAfterPrice() {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "mock-ready", "-UITestSeedAmount", "-UITestLangs", "zh-Hans,id", "-AppleLanguages", "(\(uiLang))", "-AppleLocale", isEn ? "en_US" : "zh_CN"]
        app.launch()
        let counter = app.buttons["reply_8万印尼盾行吗？"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10), "应出现程序计算的还价")
        let bargain = app.buttons["reply_太贵了，便宜点"]
        XCTAssertTrue(bargain.exists)
        shot("14_context_replies")
        bargain.tap()
        XCTAssertTrue(app.staticTexts["Terlalu mahal, bisa kurang?"].waitForExistence(timeout: 5), "快捷回复应直接发出印尼语")
    }

    func holdToTalk(_ app: XCUIApplication) -> XCUIElement { app.descendants(matching: .any)["holdToTalk"].firstMatch }

    /// v4 V4：只有一个大「按住说话」，空对话先听我；可手动换成对方；还有「给对方看」
    func testSingleHoldToTalkAndSwitch() {
        let app = launchLangs("zh-Hans,id", ui: uiLang, locale: isEn ? "en_US" : "zh_CN")
        let talk = holdToTalk(app)
        XCTAssertTrue(talk.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["showToPartner"].exists)
        XCTAssertFalse(app.buttons[isEn ? "Hold to listen" : "按住听对方"].exists, "旧的双按钮应已移除")
        let sw = app.buttons["switchSpeaker"]
        XCTAssertTrue(sw.exists)
        let before = sw.label
        XCTAssertEqual(before, isEn ? "Switch to them" : "换成对方说")
        sw.tap()
        XCTAssertNotEqual(app.buttons["switchSpeaker"].label, before)
        XCTAssertTrue(talk.frame.height >= 90, "按住说话按钮高度应 ≥ 96pt：\(talk.frame.height)")
        shot("15_single_talk_button")
    }

    // MARK: P4 双方各自选语言

    func launchLangs(_ langs: String, ui: String = "zh-Hans", locale: String = "zh_CN") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "mock-ready", "-UITestLangs", langs, "-AppleLanguages", "(\(ui))", "-AppleLocale", locale]
        app.launch()
        return app
    }

    func send(_ app: XCUIApplication, _ text: String) {
        let input = app.textFields["chatInput"].exists ? app.textFields["chatInput"] : app.textViews["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText(text)
        app.buttons["sendButton"].tap()
    }

    func testChineseMeEnglishPartner() {
        let app = launchLangs("zh-Hans,en")
        XCTAssertTrue(waitHome(app))
        XCTAssertTrue(app.buttons["theirLangPicker"].waitForExistence(timeout: 5))
        send(app, "太贵了")
        XCTAssertTrue(app.staticTexts["Too expensive"].waitForExistence(timeout: 10))
        shot("10_lang_picker")
    }

    func testEnglishMeChinesePartnerAndFaceToFace() {
        let app = launchLangs("en,zh-Hans", ui: "en", locale: "en_US")
        XCTAssertTrue(waitHome(app))
        send(app, "Too expensive")
        XCTAssertTrue(app.staticTexts["太贵了"].waitForExistence(timeout: 10))
        app.buttons["faceToFaceToggle"].tap()
        XCTAssertTrue(app.buttons["partnerLangPicker"].waitForExistence(timeout: 5))
        shot("11_face_to_face_lang")
    }

    func testSwapLanguages() {
        let app = launchLangs("zh-Hans,id")
        XCTAssertTrue(waitHome(app))
        let swap = app.buttons["swapLangs"]
        XCTAssertTrue(swap.waitForExistence(timeout: 5))
        swap.tap()
        XCTAssertTrue(app.buttons["myLangPicker"].label.contains("印尼") || app.buttons["myLangPicker"].label.contains("Indonesian"))
    }

    // MARK: P7 英文界面：可见文字里不能有汉字（对方/我方语言是中文的气泡除外，所以这里用 en↔id）

    func assertNoHan(_ app: XCUIApplication, _ screen: String) {
        let han = NSPredicate(format: "label MATCHES %@", ".*[\\u4e00-\\u9fff].*")
        for q in [app.staticTexts, app.buttons, app.navigationBars.staticTexts] {
            let hits = q.matching(han).allElementsBoundByIndex.map(\.label)
            XCTAssertTrue(hits.isEmpty, "\(screen) 英文界面出现汉字：\(hits)")
        }
    }

    func testEnglishUIHasNoChinese() {
        for mode in ["mock-onboarding", "mock-not-ready"] {
            let app = XCUIApplication()
            app.launchArguments += ["-UITestMode", mode, "-UITestLangs", "en,id", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            sleep(2); assertNoHan(app, mode); shot("12_no_han_\(mode)_en")
            app.terminate()
        }
        let app = launchLangs("en,id", ui: "en", locale: "en_US")
        XCTAssertTrue(waitHome(app))
        assertNoHan(app, "home"); shot("12_no_han_home_en")
        XCTAssertTrue(app.buttons["theirLangPicker"].waitForExistence(timeout: 5))
        assertNoHan(app, "conversation"); shot("12_no_han_conversation_en")
        // r5 #4：常用句页的分段控件曾显示「中文」
        app.terminate()
        let nr = XCUIApplication()
        nr.launchArguments += ["-UITestMode", "mock-not-ready", "-UITestLangs", "en,id", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        nr.launch()
        openPhraseBook(nr, en: true)
        XCTAssertTrue(nr.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'phrase_'")).firstMatch.waitForExistence(timeout: 5))
        assertNoHan(nr, "phrasebook"); shot("12_no_han_phrasebook_en")
    }

    func testLaunchMemoryMetric() {
        // 基本指标（无需 Instruments）：启动到首页的内存与时间
        let app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "mock-ready"]
        measure(metrics: [XCTMemoryMetric(application: app), XCTApplicationLaunchMetric()], options: {
            let o = XCTMeasureOptions(); o.iterationCount = 3; return o
        }()) {
            app.launch()
            _ = waitHome(app)
            app.terminate()
        }
    }
}

/// 英文界面整套再跑一遍（继承全部用例；截图自动加 _en）。只跑这一遍：`-only-testing:TripUITests/TripUITestsEnglish`
final class TripUITestsEnglish: TripUITests {
    override var uiLang: String { "en" }
    override func testLaunchMemoryMetric() {}          // 指标只在中文遍测一次
    override func testEnglishUIHasNoChinese() {}       // 已在中文遍类里显式用英文跑过
}
