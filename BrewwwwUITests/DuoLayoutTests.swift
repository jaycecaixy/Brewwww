import XCTest

final class DuoLayoutTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testCalendarNavigationAndLeftHandedControls() {
        let app = launch()
        let mode = app.buttons["calendar.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15))
        mode.tap()
        XCTAssertEqual(mode.label, "切换月视图")
        capture(app, "Duo-week")
        mode.tap()
        app.buttons["nav.settings"].tap()
        app.buttons["settings.通用"].tap()
        app.buttons["settings.偏好设置"].tap()
        app.segmentedControls["settings.handedness"].buttons["左手"].tap()
        let home = app.buttons["nav.home"]
        XCTAssertLessThan(home.frame.midX, app.frame.midX)
        home.tap()
        XCTAssertTrue(app.buttons["calendar.mode"].exists)
        capture(app, "Duo-left-hand")
    }

    func testDraftSurvivesRotation() {
        let app = launch(["--preview-editor"])
        let shop = app.textFields["field.cup.and.saucer"]
        XCTAssertTrue(shop.waitForExistence(timeout: 15))
        let editor = app.otherElements["editor.layout"]
        let beforeKeyboard = editor.value as? String
        shop.tap()
        shop.typeText(" Test")
        XCTAssertEqual(editor.value as? String, beforeKeyboard, "键盘弹出不应改变持握布局")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertNotEqual(editor.value as? String, "tabletop", "未半折叠时不应进入桌面布局")
        XCTAssertTrue(shop.waitForExistence(timeout: 5))
        XCTAssertTrue((shop.value as? String)?.contains("Test") == true)
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.isHittable)
        capture(app, "Duo-landscape-editor")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue((shop.value as? String)?.contains("Test") == true)
        save.tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
    }

    func testHalfFoldArrangementAndNavigation() {
        let app = launch(["--preview-partial-hinge", "--preview-editor"])
        XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        let arrangement = app.otherElements["editor.layout"].value as? String
        if app.frame.width > app.frame.height {
            XCTAssertEqual(arrangement, "tabletop")
        } else {
            XCTAssertNotEqual(arrangement, "tabletop", "竖屏不应使用横放半折叠布局")
        }
        capture(app, "Duo-half-fold-editor")
        app.buttons["editor.cancel"].tap()
        app.buttons["nav.stamps"].tap()
        XCTAssertTrue(app.buttons["nav.home"].waitForExistence(timeout: 5))
        capture(app, "Duo-landscape-stamps")
        app.buttons["nav.home"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].exists)
        let add = app.buttons["nav.add"]
        XCTAssertTrue(add.isHittable)
        XCTAssertGreaterThanOrEqual(add.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(add.frame.maxX, app.frame.maxX + 1)
    }

    func testLandscapeTabletopWhenRotationIsAvailable() throws {
        let app = launch(["--preview-partial-hinge", "--preview-editor"])
        XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        guard XCTWaiter.wait(for: [rotated], timeout: 5) == .completed else {
            throw XCTSkip("当前模拟器姿势未允许窗口横向旋转；真实铰链切换需在 Device Hub 中验证。")
        }
        XCTAssertEqual(app.otherElements["editor.layout"].value as? String, "tabletop")
        XCTAssertTrue(app.buttons["editor.save"].isHittable)
        capture(app, "tabletop-verified-landscape")
        let shop = app.textFields["field.cup.and.saucer"]
        shop.tap()
        shop.typeText(" Fold")
        XCTAssertEqual(app.otherElements["editor.layout"].value as? String, "tabletop")
        XCTAssertTrue(app.buttons["editor.save"].isHittable)
        XCTAssertTrue((shop.value as? String)?.contains("Fold") == true)
        let fieldVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            shop.frame.maxY <= app.keyboards.firstMatch.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [fieldVisible], timeout: 5), .completed,
                       "输入行应滚动到键盘上方")
        capture(app, "tabletop-keyboard")
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + arguments
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        // Let the system rotation and the page spring settle before a visual artifact.
        Thread.sleep(forTimeInterval: 0.8)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
