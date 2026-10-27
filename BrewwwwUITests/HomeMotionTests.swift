import XCTest

final class HomeMotionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    func testCupTabMeansCalendarAndRepeatedTapDoesNothing() {
        let app = launch()
        let title = app.otherElements["calendar.pager"].firstMatch
        XCTAssertTrue(app.buttons["nav.calendar"].waitForExistence(timeout: 12))
        let before = title.value as? String
        app.buttons["nav.calendar"].tap()
        app.buttons["nav.calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].exists)
        XCTAssertEqual(title.value as? String, before)
        app.buttons["nav.stamps"].tap()
        app.buttons["nav.calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
        app.buttons["nav.map"].tap()
        app.buttons["nav.calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
        // The list is still reachable through the month summary, not through the tab.
        app.buttons["home.summary"].tap()
        XCTAssertTrue(app.buttons["drink.动画测试1"].waitForExistence(timeout: 5))
        app.buttons["nav.calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
    }

    func testMonthAndWeekSwipes() {
        let app = launch()
        let pager = app.otherElements["calendar.pager"].firstMatch
        XCTAssertTrue(pager.waitForExistence(timeout: 12))
        let month = pager.value as? String
        pager.swipeLeft()
        waitForValueChange(pager, from: month)
        pager.swipeRight()
        waitForValue(pager, equals: month)
        capture("日历-贴纸落入", app)
        app.buttons["calendar.mode"].tap()
        let week = pager.value as? String
        XCTAssertTrue(week?.hasPrefix("week:") == true)
        pager.swipeLeft()
        waitForValueChange(pager, from: week)
        pager.swipeRight()
        waitForValue(pager, equals: week)
    }

    func testFolderPhotoFliesOutAndReturns() {
        let app = launch()
        let folder = app.buttons["nav.cards"]
        XCTAssertTrue(folder.waitForExistence(timeout: 12))
        capture("展开-竖屏首页", app)
        folder.tap()
        let overlay = app.otherElements["album.overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        waitForValue(overlay, equals: "open")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "album.photo.0").firstMatch.exists)
        capture("相册-弹出完成", app)
        app.buttons["cards.layout"].tap()
        app.buttons["cards.layout"].tap()
        app.buttons["album.close"].tap()
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["calendar.mode"].exists)
    }

    func testExpandedPortraitAndLandscapeArrangement() throws {
        let app = launch()
        let home = app.descendants(matching: .any).matching(identifier: "home.layout").firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 12))
        let value = home.value as? String
        guard value == "expanded-portrait" || value == "expanded-landscape" else {
            throw XCTSkip("在 Device Hub 将本任务的 iPhone Duo 设为 Open，再执行展开布局验收。")
        }
        if value == "expanded-portrait" {
            XCTAssertTrue(app.otherElements["navigation.bottom"].exists)
            capture("展开-竖屏首页", app)
        } else {
            XCTAssertFalse(app.otherElements["navigation.bottom"].exists)
            capture("展开-横屏首页", app)
        }
        app.buttons["nav.cards"].tap()
        waitForValue(app.otherElements["album.overlay"], equals: "open")
        capture(value == "expanded-portrait" ? "展开-竖屏相册" : "展开-横屏相册", app)
        app.buttons["album.close"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--preview-calendar-fixtures"]
        app.launch()
        return app
    }
    private func waitForValue(_ element: XCUIElement, equals value: String?) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.value as? String == value }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 8), .completed)
    }
    private func waitForValueChange(_ element: XCUIElement, from value: String?) {
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.value as? String != value }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 8), .completed)
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
