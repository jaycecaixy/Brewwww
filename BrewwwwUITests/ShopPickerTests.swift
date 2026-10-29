import XCTest

final class ShopPickerTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testNearbySearchSelectionUpdatesCityAndCancelPreservesDraft() {
        let app = launch()
        openPicker(app)
        let nearby = app.buttons["shops.nearby.0"]
        XCTAssertTrue(nearby.waitForExistence(timeout: 8))
        capture("店铺选择-附近", app)
        nearby.tap()
        app.buttons["shops.confirm"].tap()
        let city = app.textFields["field.mappin"]
        XCTAssertTrue(city.waitForExistence(timeout: 5))
        XCTAssertEqual(city.value as? String, "上海市")
        XCTAssertTrue(app.buttons["field.storefront"].label.contains("Corner咖啡"))

        openPicker(app)
        let query = app.textFields["shops.search"]
        query.tap(); query.typeText("Corner")
        let result = app.buttons["shops.result.0"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        query.typeText("\n")
        capture("店铺选择-搜索", app)
        result.tap()
        app.buttons["shops.confirm"].tap()
        XCTAssertTrue(city.waitForExistence(timeout: 5))
        XCTAssertEqual(city.value as? String, "杭州市")
        XCTAssertTrue(app.buttons["field.storefront"].label.contains("杭州店"))
        capture("店铺选择-同步城市", app)

        openPicker(app)
        XCTAssertTrue(app.buttons["shops.nearby.0"].waitForExistence(timeout: 5))
        app.buttons["shops.nearby.0"].tap()
        app.buttons["shops.cancel"].tap()
        XCTAssertTrue(city.waitForExistence(timeout: 5))
        XCTAssertEqual(city.value as? String, "杭州市")
        app.buttons["editor.save"].tap()
        app.buttons["home.summary"].tap()
        let savedDrink = app.buttons["drink.古罗马美式"].firstMatch
        XCTAssertTrue(savedDrink.waitForExistence(timeout: 5))
        savedDrink.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(city.waitForExistence(timeout: 5))
        XCTAssertEqual(city.value as? String, "杭州市")
    }

    func testManualShopWithoutSearchResults() {
        let app = launch()
        openPicker(app)
        let query = app.textFields["shops.search"]
        query.tap(); query.typeText("不存在")
        let manual = app.buttons["shops.manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        query.typeText("\n")
        if !manual.isHittable { app.scrollViews.firstMatch.swipeUp() }
        manual.tap()
        app.buttons["shops.confirm"].tap()
        let city = app.textFields["field.mappin"]
        XCTAssertTrue(city.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["field.storefront"].label.contains("不存在"))
        XCTAssertEqual(city.value as? String, "城市...", "手动店铺不能沿用上次的城市")
        city.tap(); city.typeText("苏州市")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.buttons["calendar.mode"].waitForExistence(timeout: 5))
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--preview-editor", "--shop-fixtures"]
        app.launch()
        return app
    }
    private func openPicker(_ app: XCUIApplication) {
        let shop = app.buttons["field.storefront"]
        XCTAssertTrue(shop.waitForExistence(timeout: 15))
        if !shop.isHittable { app.scrollViews.firstMatch.swipeUp() }
        shop.tap()
        XCTAssertTrue(app.textFields["shops.search"].waitForExistence(timeout: 5))
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
