import XCTest

final class CutoutFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testUnavailableInferenceCanStillSaveTheOriginal() {
        let app = launch("--preview-cutout-fixture")
        let status = app.staticTexts["cutout.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 20), "先运行 scripts/stage-cutout-fixtures.py 布置测试照片。")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            status.label != "正在提取主体…"
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 30), .completed)
        XCTAssertTrue(status.label.contains("模拟器无法运行"))
        app.buttons["cutout.useOriginal"].tap()
        let name = app.textFields["field.cup.and.saucer"]
        if !name.isHittable { app.scrollViews.firstMatch.swipeUp() }
        name.tap()
        name.typeText("Original Test")
        XCTAssertTrue(app.buttons["editor.save"].isEnabled)
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.buttons["nav.calendar"].waitForExistence(timeout: 5))
        app.buttons["home.summary"].tap()
        XCTAssertTrue(app.buttons["drink.Original Test"].waitForExistence(timeout: 5))
    }

    func testSavedCutoutCanToggleAndReopen() {
        let app = launch("--preview-saved-cutout")
        let status = app.staticTexts["cutout.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15), "先运行 scripts/stage-cutout-fixtures.py 布置测试照片。")
        XCTAssertEqual(status.label, "主体贴纸已生成")
        XCTAssertTrue(element("sticker.cutout", in: app).exists)
        app.buttons["cutout.toggle"].tap()
        XCTAssertTrue(element("sticker.original", in: app).waitForExistence(timeout: 5))
        app.buttons["cutout.toggle"].tap()
        XCTAssertTrue(element("sticker.cutout", in: app).waitForExistence(timeout: 5))
        capture("cutout-editor", app: app)
        app.buttons["editor.save"].tap()
        app.buttons["home.summary"].tap()
        app.buttons["drink.Cutout Fixture"].tap()
        XCTAssertTrue(element("sticker.cutout", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cutout.status"].label, "主体贴纸已生成")
        capture("cutout-reopened", app: app)
    }

    private func launch(_ preview: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", preview]
        app.launch()
        return app
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
