import XCTest

final class NativeNavigationTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testClosedDuoRestoresWholeLayoutAfterBackgroundRotation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--map-fixtures", "--map-editor-fixture"]
        app.launch()
        let calendar = app.buttons["nav.calendar"]
        let stamps = app.buttons["nav.stamps"]
        let map = app.buttons["nav.map"]
        let add = app.buttons["nav.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        guard abs(calendar.frame.midX - map.frame.midX) < 3 else {
            throw XCTSkip("此回归需在合上的 Duo 系统侧栏环境运行")
        }
        let originalAdd = add.frame
        let originalCalendar = calendar.frame
        let originalMap = map.frame
        let pages = [(calendar, "home.layout"), (stamps, "stamps.collection"), (map, "map.page")]
        for (tab, pageID) in pages {
            tab.tap()
            let page = app.descendants(matching: .any).matching(identifier: pageID).firstMatch
            XCTAssertTrue(page.waitForExistence(timeout: 8))
            let originalPage = page.frame
            let locate = app.buttons["map.locate"]
            let world = app.buttons["map.world"]
            let originalLocate = locate.exists ? locate.frame : .zero
            let originalWorld = world.exists ? world.frame : .zero
            XCUIDevice.shared.press(.home)
            XCUIDevice.shared.orientation = .landscapeLeft
            app.activate()
            let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                abs(calendar.frame.midX - originalCalendar.midX) < 2 &&
                abs(map.frame.midY - originalMap.midY) < 2 &&
                abs(add.frame.midY - originalAdd.midY) < 2 &&
                abs(page.frame.width - originalPage.width) < 2
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
            XCTAssertEqual(add.frame.midX, originalAdd.midX, accuracy: 2)
            XCTAssertEqual(page.frame.height, originalPage.height, accuracy: 2)
            if pageID == "home.layout" { XCTAssertEqual(page.value as? String, "compact") }
            if pageID == "map.page" {
                XCTAssertEqual(locate.frame.midX, originalLocate.midX, accuracy: 2)
                XCTAssertEqual(locate.frame.midY, originalLocate.midY, accuracy: 2)
                XCTAssertEqual(world.frame.midX, originalWorld.midX, accuracy: 2)
                XCTAssertEqual(world.frame.midY, originalWorld.midY, accuracy: 2)
            }
            capture("后台旋转恢复-\(pageID)")
            XCUIDevice.shared.orientation = .portrait
        }
    }

    func testPlayfulMugHoldAndSilentUnlock() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--preview-calendar-fixtures"]
        app.launch()
        let mug = app.buttons["home.playfulMug"]
        let add = app.buttons["nav.add"]
        XCTAssertTrue(mug.waitForExistence(timeout: 15))
        XCTAssertGreaterThan(mug.frame.midY, app.buttons["nav.settings"].frame.midY)
        add.press(forDuration: 1)
        XCTAssertEqual(add.label, "添加记录")
        XCTAssertFalse(app.buttons["source.library"].isHittable)
        expectation(for: NSPredicate(format: "value == %@", "0%"), evaluatedWith: mug)
        waitForExpectations(timeout: 2)
        add.press(forDuration: 1.95)
        XCTAssertEqual(mug.value as? String, "100%")
        XCTAssertEqual(add.label, "添加记录")
        XCTAssertTrue(mug.isHittable, app.debugDescription)
        capture("马克杯-满杯")
        add.tap()
        XCTAssertEqual(add.label, "取消")
        XCTAssertTrue(app.buttons["source.library"].isHittable)
        add.tap()
        XCTAssertEqual(add.label, "添加记录")
        XCTAssertEqual(mug.value as? String, "100%")
        mug.tap(withNumberOfTaps: 10, numberOfTouches: 1)
        app.buttons["nav.stamps"].tap()
        app.buttons["stamps.catalogue"].tap()
        XCTAssertTrue(app.buttons["stamps.openTheme"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["stamps.openTheme"].label.contains("20枚已收集"))
        XCTAssertTrue(app.buttons["stamps.openExplore"].label.contains("8枚已收集"))
        app.buttons["nav.calendar"].tap()
        mug.tap(withNumberOfTaps: 10, numberOfTouches: 1)
        app.buttons["nav.stamps"].tap()
        app.buttons["stamps.catalogue"].tap()
        XCTAssertTrue(app.buttons["stamps.openTheme"].label.contains("0枚已收集"))
        XCTAssertTrue(app.buttons["stamps.openExplore"].label.contains("0枚已收集"))
    }

    func testSourcePickerActionsAndCancel() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--preview-calendar-fixtures"]
        app.launch()
        let add = app.buttons["nav.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 12))
        add.tap()
        let library = app.buttons["source.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        capture("添加记录-系统相册")
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        add.tap()
        XCTAssertEqual(add.label, "添加记录")
        let mode = app.buttons["calendar.mode"]
        let originalMode = mode.label
        mode.tap()
        XCTAssertNotEqual(mode.label, originalMode)
    }

    func testSystemTabsSlideSelectionAndSeparateAddAction() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--preview-calendar-fixtures"]
        app.launch()
        let calendar = app.buttons["nav.calendar"]
        let stamps = app.buttons["nav.stamps"]
        let map = app.buttons["nav.map"]
        let add = app.buttons["nav.add"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 15))
        let vertical = abs(calendar.frame.midX - map.frame.midX) < 5
        if vertical {
            XCTAssertEqual(calendar.frame.midX, add.frame.midX, accuracy: 2)
            XCTAssertGreaterThan(add.frame.minY, map.frame.maxY + 5)
            XCTAssertTrue(app.buttons["nav.settings"].isHittable)
            XCTAssertTrue(app.buttons["calendar.mode"].isHittable)
        } else {
            XCTAssertTrue(app.tabBars.firstMatch.exists, "横向主导航使用系统 UITabBar")
            XCTAssertGreaterThan(add.frame.minX, map.frame.maxX)
            XCTAssertEqual(add.frame.midY, map.frame.midY, accuracy: 3)
        }
        capture("原生导航-默认")
        calendar.press(forDuration: 0.6, thenDragTo: map)
        XCTAssertTrue(app.otherElements["map.page"].waitForExistence(timeout: 6))
        XCTAssertTrue(map.isSelected)
        map.press(forDuration: 0.6, thenDragTo: stamps)
        XCTAssertTrue(app.buttons["stamps.catalogue"].waitForExistence(timeout: 6))
        XCTAssertTrue(stamps.isSelected)
        calendar.tap()
        let addFrame = add.frame
        add.tap()
        XCTAssertTrue(app.buttons["从相册选择"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["source.camera"].exists)
        XCTAssertEqual(add.label, "取消")
        XCTAssertEqual(add.frame.midX, addFrame.midX, accuracy: 1)
        XCTAssertEqual(add.frame.midY, addFrame.midY, accuracy: 1)
        XCTAssertEqual(add.frame.width, addFrame.width, accuracy: 1)
        capture("添加记录-深色来源浮层")
        app.buttons["source.library"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        add.tap()
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        XCTAssertEqual(add.label, "添加记录")
        XCTAssertTrue(app.buttons["calendar.mode"].exists)

        app.launchArguments = ["--ui-testing", "--preview-calendar-fixtures", "--appearance=light"]
        app.launch()
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        XCTAssertTrue(app.buttons["source.library"].waitForExistence(timeout: 5))
        XCTAssertEqual(add.label, "取消")
        capture("添加记录-浅色来源浮层")
        add.tap()
        XCTAssertEqual(add.label, "添加记录")
    }

    func testRepeatedTabDraggingKeepsChromeStableAndInteractive() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--preview-calendar-fixtures"]
        app.launch()
        let calendar = app.buttons["nav.calendar"]
        let stamps = app.buttons["nav.stamps"]
        let map = app.buttons["nav.map"]
        let add = app.buttons["nav.add"]
        let settings = app.buttons["nav.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        let originalTabs = [calendar.frame, stamps.frame, map.frame]
        let originalSettings = settings.frame
        let originalAdd = add.frame

        for _ in 0..<3 {
            calendar.press(forDuration: 0.8, thenDragTo: map)
            XCTAssertTrue(app.otherElements["map.page"].waitForExistence(timeout: 6))
            XCTAssertTrue(map.isSelected)
            map.press(forDuration: 0.8, thenDragTo: stamps)
            XCTAssertTrue(app.buttons["stamps.catalogue"].waitForExistence(timeout: 6))
            XCTAssertTrue(stamps.isSelected)
            stamps.press(forDuration: 0.8, thenDragTo: calendar)
            XCTAssertTrue(settings.waitForExistence(timeout: 6))
            XCTAssertTrue(calendar.isSelected)
            for (button, frame) in zip([calendar, stamps, map, settings, add],
                                      originalTabs + [originalSettings, originalAdd]) {
                XCTAssertEqual(button.frame.midX, frame.midX, accuracy: 1, button.identifier)
                XCTAssertEqual(button.frame.midY, frame.midY, accuracy: 1, button.identifier)
            }
            // Exercise the next touch instead of relying on the system lens's
            // accessibility hit-point flag immediately after a held drag.
            calendar.tap()
            XCTAssertTrue(app.buttons["calendar.mode"].exists)
        }
        // A completed drag must leave both the native tabs and utility actions usable.
        stamps.tap()
        XCTAssertTrue(app.buttons["stamps.catalogue"].waitForExistence(timeout: 6))
        calendar.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 6))
        settings.tap()
        XCTAssertTrue(app.buttons["nav.home"].waitForExistence(timeout: 6))
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.7)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
