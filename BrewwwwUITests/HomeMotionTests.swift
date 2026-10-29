import XCTest

final class HomeMotionTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    func testCompactPhoneStaysPortraitWhenRotated() throws {
        let app = launch()
        XCTAssertTrue(app.buttons["home.summary"].waitForExistence(timeout: 12))
        guard app.frame.width < 600 else { throw XCTSkip("仅适用于折叠状态或普通 iPhone") }
        for orientation in [UIDeviceOrientation.landscapeLeft, .landscapeRight] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(app.buttons["home.summary"].exists)
            XCTAssertLessThan(app.frame.width, app.frame.height)
        }
    }

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
        app.buttons["nav.home"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
    }

    func testMonthRecordBlankAreaCanDragDownAndShortDragRestores() {
        let app = launch()
        let summary = app.buttons["home.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 12))
        summary.tap()
        let overlay = app.otherElements["month.overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        let close = app.buttons["nav.home"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertEqual(close.frame.midY, overlay.frame.midY, accuracy: 24)
        // Verify an actual finger tap at the new sidebar position.
        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let closedByButton = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !overlay.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [closedByButton], timeout: 5), .completed)
        summary.tap()
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        let blank = overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        blank.press(forDuration: 0.2, thenDragTo: overlay.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.74)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(app.buttons["nav.home"].exists)
        blank.press(forDuration: 0.2, thenDragTo: blank.withOffset(CGVector(dx: 0, dy: 90)), withVelocity: .slow, thenHoldForDuration: 0.1)
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !overlay.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        summary.tap()
        XCTAssertTrue(app.buttons["nav.home"].waitForExistence(timeout: 5))
        app.buttons["nav.home"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
    }

    func testSettingsGlassCloseAndCalendarRecordRemainReachable() {
        let app = launch()
        let settings = app.buttons["nav.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 12))
        settings.tap()
        let close = app.buttons["nav.home"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(close.isHittable)
        let settingsPage = app.otherElements["settings.page.root"]
        XCTAssertTrue(settingsPage.waitForExistence(timeout: 5))
        // On the unfolded simulator, XCUIApplication.frame can retain portrait
        // dimensions. Compare against the visible page in screen coordinates.
        XCTAssertEqual(close.frame.midY, settingsPage.frame.midY, accuracy: 45)
        capture("设置-液态玻璃侧栏关闭", app)
        close.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let day = Calendar.current.component(.day, from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        app.otherElements["calendar.grid"].buttons["calendar.day.\(day)"].tap()
        XCTAssertTrue(app.buttons["editor.cancel"].waitForExistence(timeout: 5))
        capture("饮品详情-底部进入", app)
        app.buttons["editor.cancel"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
    }

    func testSettingsSubpagesAndGlassBackButton() {
        let app = launch()
        XCTAssertTrue(app.buttons["nav.settings"].waitForExistence(timeout: 12))
        app.buttons["nav.settings"].tap()
        for (title, page) in [("个人信息", "profile"), ("通用", "general"), ("外观", "appearance"), ("常见问题", "faq")] {
            let row = app.buttons["settings.\(title)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            XCTAssertTrue(app.otherElements["settings.page.\(page)"].waitForExistence(timeout: 5))
            if page == "general" {
                app.buttons["settings.偏好设置"].tap()
                XCTAssertTrue(app.otherElements["settings.page.preferences"].waitForExistence(timeout: 5))
            }
            app.buttons["nav.home"].tap()
            if page == "general" {
                XCTAssertTrue(app.buttons["settings.偏好设置"].waitForExistence(timeout: 5))
                app.buttons["nav.home"].tap()
            }
            XCTAssertTrue(app.buttons["settings.个人信息"].waitForExistence(timeout: 5))
        }
        app.buttons["nav.home"].tap()
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

    func testCalendarCornerBadgeDoesNotOverlapDatesInEitherMode() {
        let app = launch()
        let badge = app.buttons["calendar.mode"]
        XCTAssertTrue(badge.waitForExistence(timeout: 12))
        for cycle in 0..<3 {
            for value in ["M", "W"] {
                XCTAssertEqual(badge.value as? String, value)
                XCTAssertEqual(app.buttons.matching(identifier: "calendar.mode").count, 1)
                let grid = app.otherElements["calendar.grid"].firstMatch
                let pager = app.otherElements["calendar.pager"].firstMatch
                // Both the visible corner and its touch area are triangular.
                // Even the bottom-right date must remain above the diagonal.
                XCTAssertLessThanOrEqual(grid.frame.maxX + grid.frame.maxY,
                                         badge.frame.minX + badge.frame.minY + 44 + 1)
                XCTAssertLessThanOrEqual(badge.frame.maxX, pager.frame.maxX)
                XCTAssertLessThanOrEqual(badge.frame.maxY, pager.frame.maxY + 1)
                XCTAssertEqual(badge.frame.width, 44, accuracy: 1)
                if cycle == 0 { capture("日历-斜切角标-\(value)", app) }
                badge.tap()
                XCTAssertEqual(badge.label, value == "M" ? "切换月视图" : "切换周视图")
            }
        }
        capture("日历-角标切换后", app)
    }

    func testLightCalendarCornerSurvivesPaging() {
        let app = launch(["--appearance=light"])
        let badge = app.buttons["calendar.mode"]
        let pager = app.otherElements["calendar.pager"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 12))
        capture("浅色日历-花体M角标", app)
        for _ in 0..<2 {
            let original = pager.value as? String
            pager.swipeLeft()
            waitForValueChange(pager, from: original)
            XCTAssertTrue(badge.exists)
            pager.swipeRight()
            waitForValue(pager, equals: original)
            XCTAssertTrue(badge.exists)
            badge.tap()
        }
        badge.tap()
        XCTAssertEqual(badge.value as? String, "W")
        capture("浅色日历-花体W角标", app)
    }

    func testExpandedCalendarPagingAndShortDragInBothOrientations() throws {
        let app = launch()
        let home = app.descendants(matching: .any).matching(identifier: "home.layout").firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 12))
        guard (home.value as? String)?.hasPrefix("expanded") == true else {
            throw XCTSkip("需要展开状态的设备")
        }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let pager = app.otherElements["calendar.pager"].firstMatch
            let before = pager.value as? String
            if orientation == .portrait { pager.swipeLeft() } else { pager.swipeUp() }
            waitForValueChange(pager, from: before)
            if orientation == .portrait { pager.swipeRight() } else { pager.swipeDown() }
            waitForValue(pager, equals: before)
            let start = pager.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 15, dy: 0)),
                        withVelocity: .slow, thenHoldForDuration: 0.2)
            XCTAssertEqual(pager.value as? String, before)
        }
    }

    func testExpandedFrostedPagesStayContinuousInMonthAndWeekModes() throws {
        let app = launch()
        let home = app.descendants(matching: .any).matching(identifier: "home.layout").firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 12))
        guard (home.value as? String)?.hasPrefix("expanded") == true else {
            throw XCTSkip("需要展开状态的设备")
        }
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let pager = app.otherElements["calendar.pager"].firstMatch
            XCTAssertTrue(pager.waitForExistence(timeout: 5))
            for mode in ["M", "W"] {
                XCTAssertEqual(app.buttons["calendar.mode"].value as? String, mode)
                capture("常驻毛玻璃预览-\(orientation.rawValue)-\(mode)", app)
                let before = pager.value as? String
                let title = app.descendants(matching: .any).matching(identifier: "home.title").firstMatch
                let start = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: pager.frame.midX, dy: title.frame.maxY + 9))
                let delta = orientation == .portrait ? CGVector(dx: -28, dy: 0) : CGVector(dx: 0, dy: -28)
                start.press(forDuration: 0.1, thenDragTo: start.withOffset(delta),
                            withVelocity: .slow, thenHoldForDuration: 0.4)
                XCTAssertEqual(pager.value as? String, before)
                if orientation == .portrait { pager.swipeLeft() } else { pager.swipeUp() }
                waitForValueChange(pager, from: before)
                XCTAssertTrue(app.buttons["calendar.mode"].exists)
                if orientation == .portrait { pager.swipeRight() } else { pager.swipeDown() }
                waitForValue(pager, equals: before)
                // Touch the painted triangle rather than the transparent
                // half of its rectangular accessibility bounding box.
                app.buttons["calendar.mode"].coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.78)).tap()
            }
        }
    }

    func testCompactModeAnimationPerformance() {
        let app = launch()
        let mode = app.buttons["calendar.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 15))
        // Warm both modes so image decoding and first-use metadata are excluded.
        mode.tap()
        mode.tap()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTOSSignpostMetric(subsystem: "com.xiuyuancai.brewwww",
                                            category: "Motion", name: "CalendarMode")], options: options) {
            mode.tap()
            mode.tap()
        }
    }

    func testCompactSettingsAnimationPerformance() {
        let app = launch()
        let settings = app.buttons["nav.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        app.buttons["nav.home"].tap()
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTOSSignpostMetric(subsystem: "com.xiuyuancai.brewwww",
                                            category: "Motion", name: "SettingsEntrance")], options: options) {
            settings.tap()
            app.buttons["nav.home"].tap()
        }
    }

    func testModeSwitchInPartialFoldPortraitAndLandscape() {
        let app = launch(["--preview-partial-hinge"])
        let mode = app.buttons["calendar.mode"]
        let pager = app.otherElements["calendar.pager"].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 15))
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            XCTAssertTrue(mode.waitForExistence(timeout: 5))
            for _ in 0..<2 {
                mode.tap()
                XCTAssertTrue((pager.value as? String)?.hasPrefix("week:") == true)
                mode.tap()
                XCTAssertFalse((pager.value as? String)?.hasPrefix("week:") == true)
            }
            capture("周月切换-半折叠-\(orientation.rawValue)", app)
        }
    }

    func testFolderPhotoFliesOutAndReturns() {
        for appearance in ["dark", "light"] {
            let app = launch(["--appearance=\(appearance)"])
            let folder = app.buttons["nav.cards"]
            XCTAssertTrue(folder.waitForExistence(timeout: 12))
            capture("照片夹-\(appearance)-收纳", app)
            folder.tap()
            let overlay = app.otherElements["album.overlay"]
            XCTAssertTrue(overlay.waitForExistence(timeout: 5))
            waitForValue(overlay, equals: "open")
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "album.photo.0").firstMatch.exists)
            capture("照片夹-\(appearance)-弹出", app)
            app.buttons["cards.layout"].tap()
            app.buttons["cards.layout"].tap()
            app.buttons["album.close"].tap()
            XCTAssertTrue(folder.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["calendar.mode"].exists)
        }
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

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--preview-calendar-fixtures"] + arguments
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
