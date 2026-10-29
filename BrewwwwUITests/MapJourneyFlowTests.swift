import XCTest

final class MapJourneyFlowTests: XCTestCase {
    func testCityFlightAndWorldAndLocationButtons() {
        let app = launch(["--globe-city-fixtures", "--map-viewport-audit"])
        let cluster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "globe.city.")).firstMatch
        XCTAssertTrue(cluster.waitForExistence(timeout: 12))
        XCTAssertTrue(cluster.label.contains("上海市，喝过2家店"))
        cluster.tap()
        XCTAssertTrue(app.buttons["map.world"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.otherElements["map.globe"].exists)
        let page = app.otherElements["map.page"]
        XCTAssertTrue((page.value as? String)?.contains("following=0") == true)
        app.buttons["map.locate"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let following = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (page.value as? String)?.contains("following=1") == true
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [following], timeout: 8), .completed)
        app.buttons["map.world"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.otherElements["map.globe"].waitForExistence(timeout: 8))
        XCTAssertTrue(cluster.waitForExistence(timeout: 8))
    }

    func testOverlappingMarkersSelectVisuallyTopCafe() {
        let app = launch(["--map-overlap-fixture"])
        let top = app.descendants(matching: .any).matching(identifier: "map.cafe.Overlap Z").firstMatch
        let lower = app.descendants(matching: .any).matching(identifier: "map.cafe.Overlap A").firstMatch
        XCTAssertTrue(top.waitForExistence(timeout: 12))
        XCTAssertEqual(top.value as? String, "显示店名")
        XCTAssertEqual(lower.value as? String, "隐藏店名")
        capture("地图-重叠时仅显示上层店名")
        top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let detail = app.otherElements["map.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(detail.staticTexts["Overlap Z"].exists)
        app.buttons["map.closeDetail"].tap()
        app.buttons["map.filters"].tap()
        app.buttons["查看店铺清单"].tap()
        app.buttons.containing(.staticText, identifier: "Overlap A").firstMatch.tap()
        XCTAssertTrue(detail.staticTexts["Overlap A"].waitForExistence(timeout: 5))
        XCTAssertEqual(lower.value as? String, "显示店名")
        XCTAssertEqual(top.value as? String, "隐藏店名")
        capture("地图-下层店铺选中后只显示其店名")
        app.buttons["map.closeDetail"].tap()
        XCTAssertEqual(top.value as? String, "显示店名")
        XCTAssertEqual(lower.value as? String, "隐藏店名")
    }

    func testGlobeCityNameSettingIsImmediateAndPersists() {
        let app = launch(["--globe-city-fixtures"])
        func setNames(_ enabled: Bool) {
            app.buttons["nav.calendar"].tap()
            app.buttons["nav.settings"].tap()
            app.buttons["settings.通用"].tap()
            let toggle = app.switches["settings.globeDistrictNames"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            if (toggle.value as? String == "1") != enabled {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            }
            XCTAssertEqual(toggle.value as? String, enabled ? "1" : "0")
            app.buttons["nav.home"].tap()
            app.buttons["nav.home"].tap()
            app.buttons["nav.map"].tap()
        }
        setNames(false)
        let globe = app.otherElements["map.globe"]
        XCTAssertTrue(globe.waitForExistence(timeout: 8))
        XCTAssertTrue((globe.value as? String)?.contains("城市名称已隐藏") == true)
        let cluster = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "globe.city.")).firstMatch
        XCTAssertTrue(cluster.exists) // Hiding names preserves markers and their actions.
        capture("地球-关闭城市名称")
        app.terminate()
        app.launch()
        XCTAssertTrue(globe.waitForExistence(timeout: 12))
        XCTAssertTrue((globe.value as? String)?.contains("城市名称已隐藏") == true)
        setNames(true)
        XCTAssertTrue((globe.value as? String)?.contains("城市名称已显示") == true)
        capture("地球-显示城市名称")
    }

    override func setUpWithError() throws {
        continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait
    }
    func testWishSearchFirstDrinkAndPersistentPlusWithThirdMarkerState() {
        let app = launch()
        XCTAssertTrue(app.otherElements["map.globe"].waitForExistence(timeout: 12))
        capture("地图-旋转地球")
        app.buttons["map.wish"].tap()
        let search = app.textFields["wish.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Corner\n")
        let result = app.buttons["wish.result.0"]
        XCTAssertTrue(result.waitForExistence(timeout: 6))
        // The system sheet changes detent after the search keyboard closes.
        capture("原生地图-搜索待选择")
        result.tap()
        XCTAssertEqual(result.value as? String, "selected")
        XCTAssertTrue(app.buttons["wish.confirm"].isEnabled)
        capture("地图-想喝搜索")
        app.buttons["wish.confirm"].tap()
        let detail = app.otherElements["map.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        XCTAssertEqual(detail.value as? String, "wishlist")
        capture("地图-想喝详情")
        app.buttons["map.addDrink"].tap()
        XCTAssertTrue(app.buttons["field.storefront"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["field.storefront"].label.contains("杭州店"))
        XCTAssertEqual(app.textFields["field.mappin"].value as? String, "杭州市")
        XCTAssertTrue(app.buttons["editor.photo"].exists)
        let name = app.textFields["field.cup.and.saucer"]
        name.tap(); name.typeText("Latte")
        app.buttons["editor.save"].tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        XCTAssertEqual(detail.value as? String, "fulfilled")
        XCTAssertTrue(app.buttons["map.addDrink"].exists)
        XCTAssertTrue(app.buttons["map.addDrink"].isHittable)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '1 次打卡'")).firstMatch.exists)
        capture("地图-想喝已打卡")
        app.buttons["map.addDrink"].tap()
        XCTAssertTrue(app.buttons["field.storefront"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["field.mappin"].value as? String, "杭州市")
        app.buttons["editor.cancel"].tap()
        XCTAssertTrue(app.buttons["map.addDrink"].waitForExistence(timeout: 5))
    }

    func testMapEditorRoundTripsPreserveViewportAndPhotoAnchor() {
        // Start at a selected wish so this regression does not depend on search
        // sheet detents, keyboard timing, or network results.
        let app = launch(["--map-editor-fixture", "--map-viewport-audit"])
        let detail = app.otherElements["map.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 12))
        let street = app.descendants(matching: .any).matching(identifier: "map.street").firstMatch
        let originalViewport = viewport(in: app)
        let blank = street.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25))
        blank.doubleTap()
        blank.press(forDuration: 0.1, thenDragTo: street.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
        let movedViewport = viewport(in: app)
        XCTAssertNotEqual(originalViewport, movedViewport)
        let verticalRail = abs(app.buttons["nav.calendar"].frame.midX - app.buttons["nav.map"].frame.midX) < 5
        let axis = app.buttons["nav.add"].frame.midX
        app.buttons["map.addDrink"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["field.storefront"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["field.storefront"].label.contains("杭州店"))
        XCTAssertEqual(app.textFields["field.mappin"].value as? String, "杭州市")
        XCTAssertTrue(app.buttons["editor.photo"].exists)
        if verticalRail {
            XCTAssertEqual(app.buttons["editor.cancel"].frame.midX, axis, accuracy: 2)
            XCTAssertEqual(app.buttons["editor.save"].frame.midX, axis, accuracy: 2)
        }
        let photo = app.buttons["editor.photo"]
        let photoFrame = photo.frame
        photo.tap()
        let library = app.buttons["editor.photo.library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        if verticalRail {
            XCTAssertLessThan(abs(library.frame.midY - photoFrame.midY), 180)
        }
        capture("地图添加饮品-照片选择锚点")
        if app.buttons["取消"].exists { app.buttons["取消"].tap() }
        else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.45)).tap() }
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !library.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        app.buttons["editor.cancel"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        assertViewport(movedViewport, in: app)
        app.buttons["map.addDrink"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["editor.photo"].waitForExistence(timeout: 5))
        let name = app.textFields["field.cup.and.saucer"]
        name.tap(); name.typeText("Latte")
        app.buttons["editor.save"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        XCTAssertEqual(detail.value as? String, "fulfilled")
        assertViewport(movedViewport, in: app)
        XCTAssertTrue(app.buttons["map.addDrink"].exists)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '1 次打卡'")).firstMatch.exists)
        capture("地图-想喝已打卡")
        let drink = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'map.drink.'")).firstMatch
        drink.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["editor.cancel"].waitForExistence(timeout: 5))
        if verticalRail { XCTAssertEqual(app.buttons["editor.cancel"].frame.midX, axis, accuracy: 2) }
        app.buttons["editor.cancel"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        assertViewport(movedViewport, in: app)
        drink.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["editor.save"].waitForExistence(timeout: 5))
        app.buttons["editor.save"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        assertViewport(movedViewport, in: app)
        app.buttons["map.addDrink"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["field.storefront"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["field.mappin"].value as? String, "杭州市")
        app.buttons["editor.cancel"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["map.addDrink"].waitForExistence(timeout: 5))
    }

    func testWishPhotoOptionsReopenImmediatelyAfterOutsideTap() {
        let app = launch(["--map-editor-fixture"])
        XCTAssertTrue(app.buttons["map.addDrink"].waitForExistence(timeout: 12))
        app.buttons["map.addDrink"].tap()
        let photo = app.buttons["editor.photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        let library = app.buttons["editor.photo.library"]
        let blank = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.45))
        photo.tap()
        XCTAssertTrue(library.waitForExistence(timeout: 3))
        XCTAssertLessThan(abs(library.frame.midY - photo.frame.midY), 180)
        for _ in 0..<5 {
            // No dismissal wait: the very next tap must reopen the choices.
            blank.tap()
            photo.tap()
            XCTAssertTrue(library.exists)
            XCTAssertTrue(library.isHittable)
        }
        capture("照片选项-连续快速重开")
        library.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        photo.tap()
        XCTAssertTrue(library.waitForExistence(timeout: 3))
        blank.tap()
        app.buttons["editor.cancel"].tap()
        XCTAssertTrue(app.otherElements["map.detail"].waitForExistence(timeout: 5))
    }

    func testCurrentLocationVisitedPinAndReturnToGlobe() {
        let app = launch()
        let globe = app.otherElements["map.globe"]
        XCTAssertTrue(globe.waitForExistence(timeout: 12))
        globe.pinch(withScale: 1.8, velocity: 1.2)
        XCTAssertTrue(globe.exists)
        XCTAssertFalse(app.buttons["map.world"].exists, "Pinching the globe must never enter the street map")
        globe.doubleTap()
        XCTAssertTrue(globe.exists, "双击地球不应进入真实地图")
        XCTAssertFalse(app.buttons["map.world"].exists)
        app.buttons["map.locate"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !globe.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 8), .completed)
        let cafe = app.buttons["map.cafe.MIND BALANCE"]
        XCTAssertTrue(cafe.waitForExistence(timeout: 8))
        // Annotation coordinates continue moving during MapKit's camera flight.
        Thread.sleep(forTimeInterval: 1)
        capture("地图-当前位置")
        cafe.tap()
        let detail = app.otherElements["map.detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertEqual(detail.value as? String, "visited")
        XCTAssertFalse(app.buttons["map.addDrink"].exists)
        capture("地图-喝过详情")
        app.buttons["map.closeDetail"].tap()
        app.buttons["map.world"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.otherElements["map.globe"].waitForExistence(timeout: 5))
        app.buttons["map.wish"].tap()
        app.buttons["wish.cancel"].tap()
        XCTAssertTrue(app.otherElements["map.globe"].waitForExistence(timeout: 5))
    }

    func testRepeatedGlobePinchesStayOnGlobe() {
        let app = launch()
        let globe = app.otherElements["map.globe"]
        XCTAssertTrue(globe.waitForExistence(timeout: 12))
        for _ in 0..<5 {
            globe.pinch(withScale: 1.8, velocity: 1.2)
            XCTAssertTrue(globe.exists)
            XCTAssertFalse(app.buttons["map.world"].exists)
        }
        globe.pinch(withScale: 0.5, velocity: -1)
        XCTAssertTrue(globe.exists)
        XCTAssertFalse(app.buttons["map.world"].exists)
    }

    func testLocationRecentersAfterUserMovesMap() {
        let app = launch(["--map-viewport-audit"])
        XCTAssertTrue(app.buttons["map.locate"].waitForExistence(timeout: 12))
        app.buttons["map.locate"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let street = app.descendants(matching: .any).matching(identifier: "map.street").firstMatch
        let centered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = app.otherElements["map.page"].value as? String ?? ""
            return !app.otherElements["map.globe"].exists && value.contains("following=1;busy=0")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [centered], timeout: 10), .completed)
        // The native user position is expressed in the provider's map datum,
        // which can differ from the raw GPS fix on mainland-China basemaps.
        // Compare the rendered user-centered camera before/after a manual pan.
        Thread.sleep(forTimeInterval: 0.5)
        let before = viewport(in: app)
        let blank = street.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.25))
        blank.press(forDuration: 0.1, thenDragTo: street.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.35)))
        let moved = viewport(in: app)
        XCTAssertNotEqual(moved, before)
        app.buttons["map.locate"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let recentered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = app.otherElements["map.page"].value as? String ?? ""
            let values = value.split(separator: ";").first?.split(separator: ",").compactMap { Double($0) } ?? []
            return value.contains("following=1;busy=0") && values.count == 5 && before.count == 5 &&
                abs(values[0] - before[0]) < 0.0001 && abs(values[1] - before[1]) < 0.0001
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [recentered], timeout: 8), .completed,
                       "Before: \(before); moved: \(moved); after locating again: \(viewport(in: app))")
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--screen=map", "--appearance=light", "--shop-fixtures", "--map-fixtures"] + arguments
        app.launch(); return app
    }
    private func viewport(in app: XCUIApplication) -> [Double] {
        let page = app.otherElements["map.page"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (page.value as? String)?.split(separator: ";").first?.split(separator: ",").count == 5
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        return (page.value as? String ?? "").split(separator: ";").first?.split(separator: ",").compactMap { Double($0) } ?? []
    }
    private func assertViewport(_ expected: [Double], in app: XCUIApplication) {
        let actual = viewport(in: app)
        XCTAssertEqual(actual.count, 5)
        guard actual.count == 5, expected.count == 5 else { return }
        XCTAssertEqual(actual[0], expected[0], accuracy: 0.00001)
        XCTAssertEqual(actual[1], expected[1], accuracy: 0.00001)
        XCTAssertEqual(actual[2], expected[2], accuracy: max(5, expected[2] * 0.005))
        XCTAssertEqual(actual[3], expected[3], accuracy: 0.1)
        XCTAssertEqual(actual[4], expected[4], accuracy: 0.1)
    }
    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
