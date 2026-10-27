import XCTest

final class StampCatalogueTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testCatalogueThemeLockedAndUnlockedDetailsAndBackNavigation() {
        let app = launch(count: 10)
        let catalogue = app.buttons["stamps.catalogue"]
        XCTAssertTrue(catalogue.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["stamps.collected.firstSip"].exists)
        XCTAssertTrue(app.buttons["stamps.collected.sameTable"].exists)
        XCTAssertFalse(app.buttons["stamps.collected.slowRitual"].exists)
        catalogue.tap()
        let theme = app.buttons["stamps.openTheme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        XCTAssertTrue(theme.label.contains("永久"))
        XCTAssertFalse(app.staticTexts["合作店铺印章"].exists)
        capture("caffe-together-图鉴", app)
        theme.tap()
        let first = app.buttons["stamps.milestone.firstSip"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("已收集"))
        let locked = app.buttons["stamps.milestone.slowRitual"]
        XCTAssertTrue(locked.label.contains("尚未解锁"))
        capture("caffe-together-主题", app)
        if !locked.isHittable { app.scrollViews.firstMatch.swipeUp() }
        locked.tap()
        XCTAssertTrue(app.staticTexts["再记录 10 杯，即可收集这枚印章。"].waitForExistence(timeout: 5))
        capture("caffe-together-详情", app)
        app.buttons["stamps.closeDetail"].tap()
        app.buttons["stamps.back"].tap()
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        app.buttons["stamps.back"].tap()
        XCTAssertTrue(app.buttons["stamps.collected.firstSip"].waitForExistence(timeout: 5))
        app.buttons["nav.calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
    }

    func testCatalogueAvailableBeforeTheFirstDrink() {
        let app = launch(count: 0)
        XCTAssertTrue(app.buttons["stamps.catalogue"].waitForExistence(timeout: 12))
        app.buttons["stamps.catalogue"].tap()
        app.buttons["stamps.openTheme"].tap()
        let first = app.buttons["stamps.milestone.firstSip"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("尚未解锁"))
        first.tap()
        XCTAssertTrue(app.staticTexts["再记录 1 杯，即可收集这枚印章。"].waitForExistence(timeout: 5))
    }

    func testAllFourStampsCollectedAtFortyDrinks() {
        let app = launch(count: 40)
        XCTAssertTrue(app.buttons["stamps.catalogue"].waitForExistence(timeout: 12))
        for id in ["firstSip", "sameTable", "slowRitual", "alwaysTogether"] {
            XCTAssertTrue(app.buttons["stamps.collected.\(id)"].exists)
        }
        app.buttons["stamps.catalogue"].tap()
        XCTAssertTrue(app.buttons["stamps.openTheme"].label.contains("4枚已收集"))
        app.buttons["stamps.openTheme"].tap()
        capture("caffe-together-全部解锁", app)
    }

    private func launch(count: Int) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--screen=stamps", "--stamp-count=\(count)"]
        app.launch(); return app
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        // Capture the settled page rather than the catalogue-to-theme spring.
        Thread.sleep(forTimeInterval: 0.7)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
