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


final class GuidedLayoutRegressionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--preview-calendar-fixtures", "--map-fixtures"]
        app.launch()
        XCTAssertTrue(app.buttons["nav.settings"].waitForExistence(timeout: 15))
        return app
    }
    func testSettingsCloseReturnsOneLevel() {
        let app = launch()
        app.buttons["nav.settings"].tap()
        app.buttons["settings.通用"].tap()
        app.buttons["settings.偏好设置"].tap()
        XCTAssertTrue(app.otherElements["settings.page.preferences"].exists)
        app.buttons["nav.home"].tap()
        XCTAssertTrue(app.buttons["settings.偏好设置"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["calendar.mode"].exists)
        app.buttons["nav.home"].tap()
        XCTAssertTrue(app.buttons["settings.通用"].waitForExistence(timeout: 5))
        app.buttons["nav.home"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
    }
    func testMapActionsAndMenuSizes() {
        let app = launch()
        app.buttons["nav.map"].tap()
        let locate = app.buttons["map.locate"]
        XCTAssertTrue(locate.waitForExistence(timeout: 5))
        let add = app.buttons["nav.add"]
        XCTAssertEqual(locate.frame.midY, add.frame.midY, accuracy: 1)
        XCTAssertEqual(app.buttons["map.filters"].frame.width, app.buttons["map.wish"].frame.width, accuracy: 1)
        capture("地图-完整地球与对齐", app)
        app.buttons["map.filters"].tap()
        XCTAssertTrue(app.buttons["地球 · 全部店铺"].waitForExistence(timeout: 5))
        app.buttons["地球 · 全部店铺"].tap()
        locate.tap()
        let world = app.buttons["map.world"]
        XCTAssertTrue(world.waitForExistence(timeout: 12))
        XCTAssertEqual(world.frame.midY, add.frame.midY, accuracy: 1)
        capture("地图-街道与对齐", app)
        app.buttons["nav.stamps"].tap()
        XCTAssertEqual(app.buttons["stamps.filter"].frame.width, app.buttons["stamps.catalogue"].frame.width, accuracy: 1)
        capture("印章-相同玻璃按钮", app)
    }
    func testExpandedLandscapeCalendarDrag() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = launch()
        let pager = app.otherElements["calendar.pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 12))
        XCTAssertEqual(app.otherElements["home.layout"].value as? String, "expanded-landscape")
        let original = pager.value as? String
        let start = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let end = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (pager.value as? String) != original
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        let backStart = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let backEnd = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        backStart.press(forDuration: 0.1, thenDragTo: backEnd, withVelocity: .slow, thenHoldForDuration: 0.1)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (pager.value as? String) == original
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
    }
    func testPortraitSettingsAndRepeatedSourceCancellation() {
        let app = launch()
        let calendar = app.buttons["nav.calendar"]
        let stamps = app.buttons["nav.stamps"]
        if abs(calendar.frame.midY - stamps.frame.midY) < 5 {
            XCTAssertLessThanOrEqual(app.buttons["home.summary"].frame.maxY, calendar.frame.minY)
        }
        let add = app.buttons["nav.add"]
        let initialFrame = add.frame
        for _ in 0..<4 {
            add.tap()
            XCTAssertEqual(add.label, "取消")
            XCTAssertEqual(add.frame, initialFrame)
            add.tap()
            XCTAssertEqual(add.label, "添加记录")
        }
        add.tap()
        capture("添加菜单-重复开关后取消图标", app)
        add.tap()
        app.buttons["nav.settings"].tap()
        let close = app.buttons["nav.home"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.buttons["settings.常见问题"].frame.maxX, close.frame.minX)
        close.tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
    }
    func testCompactEditorCanReachCompleteBottom() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--preview-editor"]
        app.launch()
        XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.otherElements["editor.layout"].value as? String, "stack")
        let scroll = app.scrollViews["editor.scroll"]
        XCTAssertTrue(scroll.exists)
        capture("收起-添加记录-初始", app)
        for _ in 0..<3 { scroll.swipeUp() }
        let field = app.descendants(matching: .any)["editor.note"].firstMatch
        XCTAssertTrue(field.exists)
        XCTAssertTrue(field.isHittable)
        XCTAssertLessThan(field.frame.maxY, app.frame.maxY - 20)
        XCTAssertTrue(app.buttons["editor.save"].isHittable)
        capture("收起-添加记录-完整底部", app)
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
