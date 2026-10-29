import XCTest

final class AppearanceFlowTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testAppearanceSelectionAndSwitchingWithOpenPages() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--appearance=system", "--screen=settings"]
        app.launch()
        let appearance = app.buttons["settings.外观"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 12))
        appearance.tap()
        let control = app.segmentedControls["settings.appearance"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertTrue(control.buttons["跟随系统"].isSelected)
        control.buttons["浅色"].tap()
        XCTAssertTrue(control.buttons["浅色"].isSelected)
        capture("主题-浅色-设置")
        app.buttons["nav.calendar"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
        capture("主题-浅色-首页")
        app.buttons["nav.stamps"].tap()
        app.buttons["stamps.catalogue"].tap()
        app.buttons["stamps.openTheme"].tap()
        capture("主题-浅色-印章")
        app.buttons["nav.calendar"].tap()
        app.buttons["nav.settings"].tap()
        // Re-entering settings creates its root page.
        appearance.tap()
        control.buttons["深色"].tap()
        XCTAssertTrue(control.buttons["深色"].isSelected)
        app.buttons["nav.calendar"].tap()
        capture("主题-深色-首页")
        app.buttons["nav.settings"].tap()
        appearance.tap()
        control.buttons["跟随系统"].tap()
        XCTAssertTrue(control.buttons["跟随系统"].isSelected)
    }

    func testLightEditorShopPickerAlbumAndMap() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--appearance=light", "--preview-editor", "--shop-fixtures"]
        app.launch()
        XCTAssertTrue(app.buttons["field.storefront"].waitForExistence(timeout: 12))
        capture("主题-浅色-编辑")
        app.buttons["field.storefront"].tap()
        XCTAssertTrue(app.textFields["shops.search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["shops.nearby.0"].waitForExistence(timeout: 5))
        capture("主题-浅色-店铺")
        app.buttons["shops.cancel"].tap()
        app.buttons["editor.cancel"].tap()
        app.buttons["nav.cards"].tap()
        XCTAssertTrue(app.buttons["album.close"].waitForExistence(timeout: 5))
        capture("主题-浅色-相册")
        app.buttons["album.close"].tap()
        let album = app.otherElements["album.overlay"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: album)
        waitForExpectations(timeout: 5)
        app.buttons["nav.map"].tap()
        XCTAssertTrue(app.otherElements["map.page"].waitForExistence(timeout: 5))
        capture("主题-浅色-地图")
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.7)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }

    func testHapticStrengthPersistsAndRespectsSwitch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--screen=settings"]
        func openPreferences() {
            let general = app.buttons["settings.通用"]
            XCTAssertTrue(general.waitForExistence(timeout: 12))
            general.tap()
            app.buttons["settings.偏好设置"].tap()
        }
        app.launch()
        openPreferences()
        let control = app.segmentedControls["settings.hapticStrength"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        let enabled = app.switches["触觉反馈"]
        func toggleHaptics() {
            // The custom switch draws its tappable capsule at the row's right edge.
            enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        if enabled.value as? String == "0" { toggleHaptics() }
        for title in ["小", "中", "大"] {
            control.buttons[title].tap()
            XCTAssertTrue(control.buttons[title].isSelected)
        }
        app.terminate()
        app.launch()
        openPreferences()
        XCTAssertTrue(control.buttons["大"].isSelected)
        toggleHaptics()
        XCTAssertEqual(enabled.value as? String, "0")
        XCTAssertFalse(control.isEnabled)
        toggleHaptics()
        XCTAssertEqual(enabled.value as? String, "1")
        XCTAssertTrue(control.isEnabled)
        XCTAssertTrue(control.buttons["大"].isSelected)
        control.buttons["中"].tap()
    }
}
