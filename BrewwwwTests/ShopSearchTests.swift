import XCTest
import CoreLocation
@testable import Brewwww

@MainActor final class ShopSearchTests: XCTestCase {
    func testSelectingRemoteBranchUpdatesCityAddressAndCoordinatesTogether() {
        var record = DrinkRecord(shop: "上海旧店", city: "上海市", latitude: 31.2, longitude: 121.4)
        record.selectShop(FixtureShopSearch.hangzhou)
        XCTAssertEqual(record.shop, "Corner咖啡（杭州店）")
        XCTAssertEqual(record.city, "杭州市")
        XCTAssertEqual(record.shopAddress, "中山北路100号")
        XCTAssertEqual(record.latitude, 30.2741)
        XCTAssertEqual(record.longitude, 120.1551)
    }

    func testManualSelectionClearsPreviousCityAndCoordinates() {
        var record = DrinkRecord(shop: "旧店", city: "上海市", latitude: 31.2, longitude: 121.4)
        record.shopAddress = "旧地址"
        record.selectShop(ShopPlace(name: "手动新店"))
        XCTAssertEqual(record.shop, "手动新店")
        XCTAssertTrue(record.city.isEmpty)
        XCTAssertNil(record.shopAddress)
        XCTAssertNil(record.latitude)
        XCTAssertNil(record.longitude)
    }

    func testLegacyRecordWithoutAddressDecodes() throws {
        let data = Data("""
        {"id":"A600E6B6-EB14-4989-A117-2B6CE5BAC734","date":0,"shop":"老店","city":"上海市","name":"美式","note":"","favorite":false}
        """.utf8)
        let record = try JSONDecoder().decode(DrinkRecord.self, from: data)
        XCTAssertEqual(record.shop, "老店")
        XCTAssertNil(record.shopAddress)
    }

    func testLocatedShopAndFavoritePersistAndSameNameBranchesStayDistinct() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrewStore(directory: directory)
        store.records = []
        store.customShops = [:]
        store.savedShopPlaces = []
        let first = FixtureShopSearch.shanghai
        var branch = first
        branch.address = "同名店另一条街"
        branch.longitude = 121.48
        store.saveShop(first); store.saveShop(first); store.saveShop(branch)
        XCTAssertEqual(store.myShopPlaces.count, 2)
        var record = DrinkRecord(name: "美式")
        record.selectShop(first)
        try store.add(record, photo: nil)
        let restored = BrewStore(directory: directory)
        XCTAssertEqual(restored.savedShopPlaces, [first, branch])
        XCTAssertEqual(restored.records.last?.shopPlace, first)
    }

    func testLateSearchCannotOverwriteNewerResults() async throws {
        let model = ShopSearchModel(service: OutOfOrderSearch())
        model.query = "慢"
        let first = Task { await model.search(debounce: false) }
        try await Task.sleep(for: .milliseconds(20))
        model.query = "快"
        await model.search(debounce: false)
        await first.value
        XCTAssertEqual(model.results.map(\.name), ["快"])
        XCTAssertFalse(model.searching)
        model.query = ""
        await model.search(debounce: false)
        XCTAssertTrue(model.results.isEmpty)
    }

    func testDismissingPickerRejectsAnInFlightResponse() async throws {
        let model = ShopSearchModel(service: OutOfOrderSearch())
        model.query = "慢"
        let pending = Task { await model.search(debounce: false) }
        try await Task.sleep(for: .milliseconds(20))
        model.stop()
        await pending.value
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertFalse(model.searching)
    }

    func testLegacyStoreWithoutFavoritePlacesStillLoads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = Data("""
        {"records":[],"customShops":{"我的老店":"上海市"}}
        """.utf8)
        try data.write(to: directory.appendingPathComponent("records.json"))
        let store = BrewStore(directory: directory)
        XCTAssertEqual(store.customShops["我的老店"], "上海市")
        XCTAssertEqual(store.myShopPlaces.first?.name, "我的老店")
        XCTAssertTrue(store.savedShopPlaces.isEmpty)
    }

    func testSearchFailureDoesNotLeaveStaleResultsOrSpinner() async {
        let model = ShopSearchModel(service: FailingSearch())
        model.query = "店铺"
        await model.search(debounce: false)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNotNil(model.searchError)
        XCTAssertFalse(model.searching)
    }

    func testSearchWorksWithoutLocation() async {
        let model = ShopSearchModel(service: NoLocationSearch())
        model.query = "杭州 咖啡"
        await model.search(debounce: false)
        XCTAssertEqual(model.results.first?.city, "杭州市")
        XCTAssertNil(model.location)
    }
}

@MainActor private struct OutOfOrderSearch: ShopSearching {
    func search(_ query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [ShopPlace] {
        try? await Task.sleep(for: .milliseconds(query == "慢" ? 180 : 5))
        return [ShopPlace(name: query)]
    }
}
@MainActor private struct FailingSearch: ShopSearching {
    func search(_ query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [ShopPlace] {
        throw URLError(.notConnectedToInternet)
    }
}
@MainActor private struct NoLocationSearch: ShopSearching {
    func search(_ query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [ShopPlace] {
        XCTAssertNil(coordinate)
        return [FixtureShopSearch.hangzhou]
    }
}
