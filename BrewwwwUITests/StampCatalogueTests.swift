import XCTest

final class StampCatalogueTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testTogetherColourAndLockedDetailAndBackNavigation() {
        let app = launch(count: 10)
        XCTAssertTrue(app.buttons["stamps.catalogue"].waitForExistence(timeout: 12))
        app.buttons["stamps.catalogue"].tap()
        let theme = app.buttons["stamps.openTheme"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        XCTAssertTrue(theme.label.contains("2枚已收集，共20枚"))
        capture("手绘印章-图鉴-浅色", app)
        theme.tap()
        let first = app.buttons["stamps.milestone.ribbed"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("已收集"))
        let locked = app.buttons["stamps.milestone.espresso"]
        XCTAssertTrue(locked.label.contains("尚未解锁"))
        capture("手绘印章-Together-浅色", app)
        locked.tap()
        XCTAssertTrue(app.staticTexts["再记录 5 杯，即可收集这枚印章。"].waitForExistence(timeout: 5))
        capture("手绘印章-未解锁详情", app)
        app.buttons["stamps.closeDetail"].tap()
        first.tap()
        XCTAssertTrue(app.staticTexts["已收集 · 累计 5 杯"].waitForExistence(timeout: 5))
        capture("手绘印章-彩色详情", app)
        app.buttons["stamps.closeDetail"].tap()
        app.buttons["stamps.back"].tap()
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        app.buttons["stamps.back"].tap()
        app.buttons["nav.calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
    }

    func testExploreRulesAndNavigation() {
        let app = launch(count: 10)
        XCTAssertTrue(app.buttons["stamps.catalogue"].waitForExistence(timeout: 12))
        app.buttons["stamps.catalogue"].tap()
        let explore = app.buttons["stamps.openExplore"]
        for _ in 0..<6 {
            if explore.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(explore.isHittable)
        XCTAssertTrue(explore.label.contains("3枚已收集，共8枚"))
        capture("手绘印章-Explore图鉴", app)
        explore.tap()
        let unlocked = app.buttons["stamps.milestone.pourOver"]
        XCTAssertTrue(unlocked.waitForExistence(timeout: 5))
        XCTAssertTrue(unlocked.label.contains("已收集"))
        capture("手绘印章-Explore-浅色", app)
        app.buttons["stamps.milestone.handGrinder"].tap()
        XCTAssertTrue(app.staticTexts["再记录 2 杯非连锁咖啡，即可收集这枚印章。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "星巴克")).firstMatch.exists)
        app.buttons["stamps.closeDetail"].tap()
        app.buttons["stamps.back"].tap()
        XCTAssertTrue(app.buttons["stamps.openTheme"].waitForExistence(timeout: 5))
    }

    func testEmptyCollectionNeedsFiveCups() {
        let app = launch(count: 0)
        XCTAssertTrue(app.buttons["stamps.catalogue"].waitForExistence(timeout: 12))
        app.buttons["stamps.catalogue"].tap()
        app.buttons["stamps.openTheme"].tap()
        XCTAssertTrue(app.buttons["stamps.milestone.ribbed"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.7)
        app.buttons["stamps.milestone.ribbed"].tap()
        XCTAssertTrue(app.staticTexts["再记录 5 杯，即可收集这枚印章。"].waitForExistence(timeout: 5))
    }

    func testAllCupStampsAtOneHundredInDarkMode() {
        let app = launch(count: 100, appearance: "dark")
        XCTAssertTrue(app.buttons["stamps.catalogue"].waitForExistence(timeout: 12))
        app.buttons["stamps.catalogue"].tap()
        XCTAssertTrue(app.buttons["stamps.openTheme"].label.contains("20枚已收集，共20枚"))
        app.buttons["stamps.openTheme"].tap()
        capture("手绘印章-Together-深色", app)
    }

    func testExploreCollectionCompletesAtTwentyFour() {
        let app = launch(count: 24)
        XCTAssertTrue(app.buttons["stamps.catalogue"].waitForExistence(timeout: 12))
        app.buttons["stamps.catalogue"].tap()
        let explore = app.buttons["stamps.openExplore"]
        for _ in 0..<6 {
            if explore.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(explore.label.contains("8枚已收集，共8枚"))
        explore.tap()
        let last = app.buttons["stamps.milestone.aeroPress"]
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        XCTAssertTrue(last.label.contains("已收集"))
        capture("质感印章-Explore-8枚收齐", app)
    }

    private func launch(count: Int, appearance: String = "light") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--screen=stamps", "--stamp-count=\(count)", "--appearance=\(appearance)"]
        app.launch(); return app
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        Thread.sleep(forTimeInterval: 0.7)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
