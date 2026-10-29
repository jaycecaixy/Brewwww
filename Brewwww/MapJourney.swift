import SwiftUI
import MapKit

enum MapWishError: LocalizedError {
    case missingLocation
    var errorDescription: String? { "请选择带有地图位置的店铺，再加入想喝清单。" }
}

enum CafeMapStatus: String, CaseIterable {
    case visited, wishlist, fulfilled
    var title: String {
        switch self {
        case .visited: "喝过的店"
        case .wishlist: "想喝的店"
        case .fulfilled: "想喝已打卡"
        }
    }
    var color: Color {
        switch self {
        case .visited: BrewStyle.mapPin
        case .wishlist: BrewStyle.adaptive(light: 0x54816C, dark: 0x80B29A)
        case .fulfilled: BrewStyle.adaptive(light: 0x9063A8, dark: 0xB28FC9)
        }
    }
}

struct MapCafe: Identifiable {
    var place: ShopPlace
    var isWish: Bool
    var records: [DrinkRecord]
    var id: String { place.id }
    var status: CafeMapStatus { isWish ? (records.isEmpty ? .wishlist : .fulfilled) : .visited }
}

extension BrewStore {
    /// One annotation per branch. Wishlist ownership remains after its first drink.
    var mapCafes: [MapCafe] {
        var cafes = wishlistPlaces.filter { $0.coordinate != nil }.map { MapCafe(place: $0, isWish: true, records: []) }
        for record in records where !record.shop.isEmpty && record.shopPlace.coordinate != nil {
            let place = record.shopPlace
            if let index = cafes.firstIndex(where: { $0.place.isSameBranch(as: place) }) {
                cafes[index].records.append(record)
            } else {
                cafes.append(MapCafe(place: place, isWish: false, records: [record]))
            }
        }
        for index in cafes.indices {
            cafes[index].records = cafes[index].records.enumerated().sorted {
                $0.element.date == $1.element.date ? $0.offset > $1.offset : $0.element.date > $1.element.date
            }.map(\.element)
        }
        return cafes
    }
}

enum MapZoom {
    static let regionalSpan = 8.0
    static let locationSpan = 0.012
}

@MainActor final class MapJourney: ObservableObject {
    @Published var globe = true
    @Published var position: MapCameraPosition = .automatic
    @Published var selectedCafeID: String?
    @Published var searchPresented = false
    @Published var city: String?
    @Published var status: CafeMapStatus?
    @Published var listPresented = false
    // A user-positioned binding is a camera policy, not a restorable viewport.
    // Keep the actual rendered camera without publishing per-camera updates.
    private var lastCamera: MapCamera?

    func rememberCamera(_ camera: MapCamera) { lastCamera = camera }

    func preserveViewport() {
        guard !globe, let lastCamera else { return }
        position = .camera(lastCamera)
    }

    func followUserLocation(near coordinate: CLLocationCoordinate2D) {
        lastCamera = nil
        // Let MapKit resolve the native user annotation. Raw GPS coordinates
        // can differ from the local basemap datum, and a later, more accurate
        // fix must remain centered rather than leaving the blue dot offset.
        position = .userLocation(followsHeading: false, fallback: .region(MKCoordinateRegion(
            center: coordinate, span: MKCoordinateSpan(latitudeDelta: MapZoom.locationSpan, longitudeDelta: MapZoom.locationSpan))))
    }

    func zoom(to coordinate: CLLocationCoordinate2D, span: Double = 0.012, animated: Bool = true) {
        zoom(to: MKCoordinateRegion(center: coordinate,
                                   span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span)), animated: animated)
    }

    func zoom(to region: MKCoordinateRegion, animated: Bool = true) {
        lastCamera = nil
        globe = false
        withAnimation(animated ? .easeInOut(duration: 0.9) : nil) {
            position = .region(region)
        }
    }
    func showGlobe() {
        lastCamera = nil
        selectedCafeID = nil; city = nil; status = nil; globe = true
    }
}

@MainActor final class MapLocation: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var fix: CLLocation?
    @Published private(set) var revision = 0
    @Published private(set) var locating = false
    @Published var error: String?
    private let manager = CLLocationManager()
    private var timeout: Task<Void, Never>?

    override init() {
        super.init(); manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    func locate() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--map-fixtures") {
            fix = CLLocation(latitude: 31.2304, longitude: 121.4737); revision += 1; return
        }
        #endif
        guard !locating else { return }
        error = nil; locating = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: requestFix()
        case .restricted, .denied: fail("尚未允许定位。可在系统设置中开启，或通过搜索查看店铺。")
        @unknown default: fail("暂时无法获取定位，请稍后再试。")
        }
    }
    private func requestFix() {
        manager.requestLocation(); timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.fail("获取位置超时，请到信号较好的地方重试。")
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard locating else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: requestFix()
        case .denied, .restricted: fail("尚未允许定位。可在系统设置中开启，或通过搜索查看店铺。")
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locating, let location = locations.last(where: {
            $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 120
        }) else { return }
        timeout?.cancel(); locating = false; fix = location; revision += 1
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard locating else { return }
        fail("暂时无法获取定位，请检查定位权限或稍后重试。")
    }
    private func fail(_ message: String) {
        timeout?.cancel(); manager.stopUpdatingLocation(); locating = false; error = message
    }
    func stop() { timeout?.cancel(); manager.stopUpdatingLocation(); locating = false }
}
