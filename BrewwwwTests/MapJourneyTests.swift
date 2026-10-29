import XCTest
import CoreLocation
import MapKit
import SwiftUI
@testable import Brewwww

@MainActor final class MapJourneyTests: XCTestCase {
    func testOverlappingMarkerNamesFollowDrawingOrderAndSelection() {
        let same = CGRect(x: 20, y: 20, width: 40, height: 40)
        let name = CGRect(x: 0, y: 70, width: 100, height: 20)
        let entries = [CafeMarkerLabelLayout.Entry(id: "lower", marker: same, name: name),
                       .init(id: "upper", marker: same, name: name)]
        XCTAssertEqual(CafeMarkerLabelLayout.visibleNames(entries, selectedID: nil), ["upper"])
        XCTAssertEqual(CafeMarkerLabelLayout.visibleNames(entries, selectedID: "lower"), ["lower"])
        XCTAssertEqual(CafeMarkerLabelLayout.visibleNames(entries, selectedID: "upper"), ["upper"])
        XCTAssertEqual(CafeMarkerLabelLayout.visibleNames(entries.reversed(), selectedID: nil), ["lower"])
        XCTAssertTrue(CafeMarkerLabelLayout.visibleNames([], selectedID: nil).isEmpty)
    }

    func testConnectedOverlapGroupKeepsOneNameAndIndependentCafesStayVisible() {
        let entries = [0.0, 30, 60, 220].enumerated().map { index, x in
            CafeMarkerLabelLayout.Entry(id: "cafe\(index)", marker: CGRect(x: x, y: 0, width: 40, height: 40),
                                        name: CGRect(x: x, y: 45, width: 40, height: 20))
        }
        XCTAssertEqual(CafeMarkerLabelLayout.visibleNames(entries, selectedID: nil), ["cafe2", "cafe3"])
        XCTAssertEqual(CafeMarkerLabelLayout.visibleNames(entries, selectedID: "cafe0"), ["cafe0", "cafe3"])
        XCTAssertEqual(CafeMarkerLabelLayout.visibleNames(entries, selectedID: "cafe3"), ["cafe2", "cafe3"])
    }

    func testLabelsAvoidEachOtherEvenWhenMarkersDoNotTouchAndReturnAfterZoom() {
        func entries(distance: CGFloat) -> [CafeMarkerLabelLayout.Entry] {
            [CGFloat(0), distance].enumerated().map { index, x in
                .init(id: "cafe\(index)", marker: CGRect(x: x, y: 0, width: 38, height: 38),
                      name: CGRect(x: x - 55, y: 45, width: 110, height: 24))
            }
        }
        XCTAssertEqual(CafeMarkerLabelLayout.visibleNames(entries(distance: 65), selectedID: nil), ["cafe1"])
        XCTAssertEqual(CafeMarkerLabelLayout.visibleNames(entries(distance: 65), selectedID: "cafe0"), ["cafe0"])
        XCTAssertEqual(CafeMarkerLabelLayout.visibleNames(entries(distance: 180), selectedID: nil), ["cafe0", "cafe1"])
        XCTAssertEqual(CafeMarkerLabelLayout.visibleNames(entries(distance: 20), selectedID: nil), ["cafe1"])
    }

    func testCityClustersCountVisitedBranchesIncludingFulfilledWishes() throws {
        let district = GlobeCity(id: "CN|上海市", name: "上海市", latitude: 31.23, longitude: 121.47, radius: 60_000)
        let a = ShopPlace(name: "A", city: "上海市", latitude: 31.29, longitude: 121.51)
        let b = ShopPlace(name: "B", city: "上海市", latitude: 31.31, longitude: 121.53)
        let wish = ShopPlace(name: "仅想喝", city: "上海市", latitude: 31.32, longitude: 121.54)
        let cafes = [MapCafe(place: a, isWish: false, records: [DrinkRecord(), DrinkRecord()]),
                     MapCafe(place: b, isWish: true, records: [DrinkRecord()]),
                     MapCafe(place: wish, isWish: true, records: [])]
        let clusters = GlobeCluster.make(cafes, cities: [a.id: district, b.id: district, wish.id: district])
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.count, 2)
        XCTAssertEqual(clusters.first?.name, "上海市")
        XCTAssertEqual(clusters.first?.coordinate.latitude, district.latitude)
        XCTAssertEqual(clusters.first?.coordinate.longitude, district.longitude)
        let partiallyResolved = GlobeCluster.make(cafes, cities: [a.id: district])
        XCTAssertEqual(partiallyResolved.count, 1)
        XCTAssertEqual(partiallyResolved.first?.count, 2)
        let region = try XCTUnwrap(clusters.first).fittedRegion(in: CGSize(width: 402, height: 874))
        XCTAssertGreaterThan(region.span.latitudeDelta, district.region.span.latitudeDelta)
        XCTAssertGreaterThan(region.span.longitudeDelta, district.region.span.longitudeDelta)
    }

    func testUnresolvedCitiesNeverMergeNearbyShopsByCoordinateGrid() {
        let a = MapCafe(place: ShopPlace(name: "A", latitude: 31.2, longitude: 121.4), isWish: false, records: [DrinkRecord()])
        let b = MapCafe(place: ShopPlace(name: "B", latitude: 31.21, longitude: 121.41), isWish: false, records: [DrinkRecord()])
        let clusters = GlobeCluster.make([a, b])
        XCTAssertEqual(clusters.count, 2)
        XCTAssertTrue(clusters.allSatisfy { $0.count == 1 })
    }

    func testCityZoomKeepsWholeRegionAndDoesNotFollowUserLocation() throws {
        let journey = MapJourney()
        let region = MKCoordinateRegion(center: .init(latitude: 31.30, longitude: 121.52),
                                        latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        journey.followUserLocation(near: .init(latitude: 30, longitude: 120))
        journey.zoom(to: region, animated: false)
        XCTAssertFalse(journey.globe)
        XCTAssertFalse(journey.position.followsUserLocation)
        XCTAssertEqual(try XCTUnwrap(journey.position.region).span.latitudeDelta, region.span.latitudeDelta)
        journey.showGlobe()
        XCTAssertTrue(journey.globe)
        journey.followUserLocation(near: region.center)
        XCTAssertTrue(journey.position.followsUserLocation)
    }

    private var directory: URL!
    private var store: BrewStore!
    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = BrewStore(directory: directory)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }

    func testLocationCentersOnLiveUserWithResolvedFixAsFallback() throws {
        let journey = MapJourney()
        let fix = CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737)
        journey.rememberCamera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 30, longitude: 120), distance: 10_000))
        journey.followUserLocation(near: fix)
        XCTAssertTrue(journey.position.followsUserLocation)
        let fallback = try XCTUnwrap(journey.position.fallbackPosition?.region)
        XCTAssertEqual(fallback.center.latitude, fix.latitude, accuracy: 0.000001)
        XCTAssertEqual(fallback.center.longitude, fix.longitude, accuracy: 0.000001)
        XCTAssertEqual(fallback.span.latitudeDelta, MapZoom.locationSpan)
        journey.preserveViewport()
        XCTAssertTrue(journey.position.followsUserLocation, "An older camera must not override the new location request")
    }

    func testGlobeZoomLimitNeverExceedsRegionalMapStartingDetail() {
        for size in [CGSize(width: 466, height: 678), CGSize(width: 951, height: 669), CGSize(width: 402, height: 874)] {
            let maximum = GlobeZoom.maximumScale(in: size)
            XCTAssertEqual(GlobeZoom.clamped(100_000, in: size), maximum)
            XCTAssertEqual(GlobeZoom.clamped(1.2, in: size), 1.2)
            XCTAssertEqual(GlobeZoom.clamped(0.01, in: size), 0.4)
            let radius = GlobeZoom.baseRadius(in: size) * maximum
            let visibleDegrees = 2 * asin(min(size.width, size.height) / (2 * radius)) * 180 / .pi
            XCTAssertGreaterThanOrEqual(visibleDegrees, MapZoom.regionalSpan - 0.00001)
        }
    }

    func testRenderedCameraIsPreservedForEditorReturnIncludingHeadingAndPitch() throws {
        let journey = MapJourney()
        journey.zoom(to: CLLocationCoordinate2D(latitude: 31.2, longitude: 121.4), animated: false)
        let camera = MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 31.25, longitude: 121.48),
                               distance: 7_500, heading: 38, pitch: 42)
        journey.rememberCamera(camera)
        journey.preserveViewport()
        let restored = try XCTUnwrap(journey.position.camera)
        XCTAssertEqual(restored.centerCoordinate.latitude, camera.centerCoordinate.latitude, accuracy: 0.000001)
        XCTAssertEqual(restored.centerCoordinate.longitude, camera.centerCoordinate.longitude, accuracy: 0.000001)
        XCTAssertEqual(restored.distance, camera.distance, accuracy: 0.01)
        XCTAssertEqual(restored.heading, camera.heading, accuracy: 0.01)
        XCTAssertEqual(restored.pitch, camera.pitch, accuracy: 0.01)
    }

    func testNewDestinationDoesNotRestoreAnOlderRenderedCamera() throws {
        let journey = MapJourney()
        journey.zoom(to: CLLocationCoordinate2D(latitude: 31.2, longitude: 121.4), animated: false)
        journey.rememberCamera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 31.25, longitude: 121.48), distance: 7_500))
        let destination = CLLocationCoordinate2D(latitude: 30.2, longitude: 120.1)
        journey.zoom(to: destination, animated: false)
        journey.preserveViewport()
        let region = try XCTUnwrap(journey.position.region)
        XCTAssertEqual(region.center.latitude, destination.latitude, accuracy: 0.000001)
        XCTAssertEqual(region.center.longitude, destination.longitude, accuracy: 0.000001)
    }

    func testWishPersistsAndDuplicateSearchResultsDoNotCreateDuplicatePins() throws {
        let place = FixtureShopSearch.shanghai
        try store.addWish(place)
        var correction = place; correction.latitude! += 0.00005
        try store.addWish(correction)
        XCTAssertEqual(store.wishlistPlaces.count, 1)
        let restored = BrewStore(directory: directory)
        XCTAssertEqual(restored.wishlistPlaces, [place])
        XCTAssertEqual(restored.mapCafes.first?.status, .wishlist)
    }

    func testFirstDrinkChangesToThirdColorAndDeletingItRevertsToWanted() throws {
        let place = FixtureShopSearch.hangzhou
        try store.addWish(place)
        var drink = DrinkRecord(name: "拿铁"); drink.selectShop(place)
        try store.add(drink, photo: nil)
        XCTAssertEqual(store.mapCafes.count, 1)
        XCTAssertEqual(store.mapCafes[0].status, .fulfilled)
        XCTAssertTrue(store.mapCafes[0].isWish)
        XCTAssertEqual(store.mapCafes[0].records.count, 1)
        let restored = BrewStore(directory: directory)
        XCTAssertEqual(restored.mapCafes[0].status, .fulfilled)
        store.delete(drink)
        XCTAssertEqual(store.mapCafes[0].status, .wishlist)
        XCTAssertEqual(store.wishlistPlaces.count, 1)
    }

    func testOrdinaryVisitedShopCanBecomeFulfilledWithoutLosingItsDrinks() throws {
        let place = FixtureShopSearch.shanghai
        var drink = DrinkRecord(name: "美式"); drink.selectShop(place)
        try store.add(drink, photo: nil)
        XCTAssertEqual(store.mapCafes[0].status, .visited)
        try store.addWish(place)
        XCTAssertEqual(store.mapCafes[0].status, .fulfilled)
        try store.removeWish(place)
        XCTAssertEqual(store.mapCafes[0].status, .visited)
        XCTAssertEqual(store.records.count, 1)
    }

    func testSameNameBranchesStaySeparateAndVisitsAggregateOnlyAtTheRightBranch() throws {
        let first = FixtureShopSearch.shanghai
        var second = first; second.address = "另一条街"; second.longitude! += 0.01
        try store.addWish(first); try store.addWish(second)
        for date in [1.0, 10.0, 5.0] {
            var drink = DrinkRecord(date: Date(timeIntervalSince1970: date), name: "美式")
            drink.selectShop(first); try store.add(drink, photo: nil)
        }
        XCTAssertEqual(store.mapCafes.count, 2)
        XCTAssertEqual(store.mapCafes[0].records.map(\.date.timeIntervalSince1970), [10, 5, 1])
        XCTAssertEqual(store.mapCafes[1].status, .wishlist)
        XCTAssertTrue(store.mapCafes[1].records.isEmpty)
    }

    func testUnlocatedAndInvalidWishesAreRejected() {
        XCTAssertThrowsError(try store.addWish(ShopPlace(name: "手动店铺")))
        XCTAssertThrowsError(try store.addWish(ShopPlace(name: "错误位置", latitude: 95, longitude: 121)))
        XCTAssertThrowsError(try store.addWish(ShopPlace(name: "空值", latitude: .nan, longitude: 121)))
        XCTAssertTrue(store.wishlistPlaces.isEmpty)
        XCTAssertTrue(GlobeCluster.make([MapCafe(place: ShopPlace(name: "无位置"), isWish: true, records: [])]).isEmpty)
    }

    func testLegacySnapshotAndGeocodedRecordsStillAppear() throws {
        let legacy = Data("{\"records\":[],\"customShops\":{}}".utf8)
        try legacy.write(to: directory.appendingPathComponent("records.json"))
        let restored = BrewStore(directory: directory)
        XCTAssertTrue(restored.wishlistPlaces.isEmpty)
        restored.records = [DrinkRecord(shop: "旧记录", name: "摩卡", latitude: 31.2, longitude: 121.4)]
        XCTAssertEqual(restored.mapCafes.first?.status, .visited)
        restored.deleteAll()
        XCTAssertTrue(BrewStore(directory: directory).mapCafes.isEmpty)
    }

    func testGlobeProjectionHidesBackAndProjectsCenterCorrectly() throws {
        let center = CGPoint(x: 200, y: 300)
        let front = try XCTUnwrap(GlobeProjection.point(latitude: 26, longitude: 110,
            centerLongitude: 110, tilt: 26, center: center, radius: 100))
        XCTAssertEqual(front.x, center.x, accuracy: 0.001)
        XCTAssertEqual(front.y, center.y, accuracy: 0.001)
        XCTAssertNil(GlobeProjection.point(latitude: -26, longitude: -70,
            centerLongitude: 110, tilt: 26, center: center, radius: 100))
        XCTAssertNotNil(Bundle.main.url(forResource: "coastline", withExtension: "geojson"))
    }

    func testCachedProjectionMatchesGeographicFormulaAcrossDatelineAndPoles() {
        let center = CGPoint(x: 230, y: 340)
        let radius = 1_800.0
        for longitude in stride(from: -200.0, through: 200.0, by: 40) {
            for tilt in [-85.0, -26, 0, 26, 85] {
                let camera = GlobeProjection.Camera(longitude: longitude, tilt: tilt)
                for latitude in stride(from: -90.0, through: 90.0, by: 15) {
                    for meridian in stride(from: -180.0, through: 180.0, by: 30) {
                        let lat = latitude * .pi / 180, lon = (meridian - longitude) * .pi / 180
                        let pitch = tilt * .pi / 180
                        let depth = sin(lat) * sin(pitch) + cos(lat) * cos(lon) * cos(pitch)
                        let point = camera.point(.init(latitude: latitude, longitude: meridian), center: center, radius: radius)
                        if depth <= 0.015 {
                            XCTAssertNil(point)
                        } else {
                            XCTAssertNotNil(point)
                            XCTAssertEqual(point?.x ?? .nan, center.x + radius * cos(lat) * sin(lon), accuracy: 0.000_001)
                            XCTAssertEqual(point?.y ?? .nan, center.y - radius * (sin(lat) * cos(pitch) - cos(lat) * cos(lon) * sin(pitch)), accuracy: 0.000_001)
                        }
                    }
                }
            }
        }
    }
}
