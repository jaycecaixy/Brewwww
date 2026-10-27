import Foundation
import MapKit
import CoreLocation

/// A branch is identified by its position as well as its name, so chains stay distinct.
struct ShopPlace: Identifiable, Codable, Equatable {
    var name: String
    var city: String
    var address: String
    var latitude: Double?
    var longitude: Double?

    var id: String {
        [name, city, address, latitude.map { String(format: "%.6f", $0) } ?? "",
         longitude.map { String(format: "%.6f", $0) } ?? ""].joined(separator: "|")
    }
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    var subtitle: String {
        [address, city].filter { !$0.isEmpty }.reduce(into: [String]()) { parts, value in
            if !parts.contains(where: { $0.contains(value) }) { parts.append(value) }
        }.joined(separator: "，")
    }
    func distance(from location: CLLocation?) -> CLLocationDistance? {
        guard let location, let coordinate else { return nil }
        return location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
    }
    static func city(from placemark: CLPlacemark) -> String {
        placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea ?? ""
    }
    init(name: String, city: String = "", address: String = "", latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name; self.city = city; self.address = address
        self.latitude = latitude; self.longitude = longitude
    }
    init(item: MKMapItem) {
        let mark = item.placemark
        self.init(name: item.name ?? mark.name ?? "未命名店铺", city: Self.city(from: mark),
                  address: [mark.thoroughfare, mark.subThoroughfare].compactMap { $0 }.joined(),
                  latitude: mark.coordinate.latitude, longitude: mark.coordinate.longitude)
        if address.isEmpty {
            address = [mark.subLocality, mark.name].compactMap { $0 }.filter { $0 != name }.joined(separator: " ")
        }
    }
}

extension DrinkRecord {
    var shopPlace: ShopPlace {
        ShopPlace(name: shop, city: city, address: shopAddress ?? "", latitude: latitude, longitude: longitude)
    }
    mutating func selectShop(_ place: ShopPlace) {
        shop = place.name
        city = place.city
        shopAddress = place.address.isEmpty ? nil : place.address
        // Manual/unlocated selections must clear a previous branch's coordinates.
        latitude = place.latitude
        longitude = place.longitude
    }
}

@MainActor protocol ShopSearching {
    func search(_ query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [ShopPlace]
}

@MainActor struct MapShopSearch: ShopSearching {
    func search(_ query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [ShopPlace] {
        if query.isEmpty, let coordinate {
            let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 2000)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.cafe, .bakery, .restaurant])
            do {
                let places = try await perform(MKLocalSearch(request: request))
                if !places.isEmpty { return places }
            } catch {
                try Task.checkCancellation()
                // The dedicated POI endpoint is unavailable in some regions (including
                // the Shanghai smoke check). Text search still supplies real local places.
            }
            let fallback = try await textSearch("咖啡", near: coordinate, radius: 4000)
            let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return fallback.filter { ($0.distance(from: origin) ?? .infinity) <= 2000 }
        }
        return try await textSearch(query, near: coordinate, radius: 10000)
    }

    private func textSearch(_ query: String, near coordinate: CLLocationCoordinate2D?, radius: Double) async throws -> [ShopPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        if let coordinate {
            request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: radius, longitudinalMeters: radius)
        }
        return try await perform(MKLocalSearch(request: request))
    }

    private func perform(_ search: MKLocalSearch) async throws -> [ShopPlace] {
        return try await withTaskCancellationHandler {
            let response = try await search.start()
            try Task.checkCancellation()
            var seen = Set<String>()
            return response.mapItems.map(ShopPlace.init(item:)).filter { seen.insert($0.id).inserted }
        } onCancel: {
            Task { @MainActor in search.cancel() }
        }
    }
}

@MainActor final class ShopSearchModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    enum LocationState: Equatable { case idle, locating, ready, denied, failed }
    @Published var query = ""
    @Published private(set) var results: [ShopPlace] = []
    @Published private(set) var nearby: [ShopPlace] = []
    @Published private(set) var searching = false
    @Published private(set) var loadingNearby = false
    @Published private(set) var searchError: String?
    @Published private(set) var nearbyError: String?
    @Published private(set) var locationState: LocationState = .idle
    @Published private(set) var location: CLLocation?
    @Published private(set) var locationRevision = 0
    var searchKey: String { query.trimmingCharacters(in: .whitespacesAndNewlines) + "|\(locationRevision)" }

    private let manager: CLLocationManager
    private let service: any ShopSearching
    private var searchRevision = 0
    private var nearbyTask: Task<Void, Never>?
    private var locationTimeout: Task<Void, Never>?
    private var started = false

    init(service: (any ShopSearching)? = nil) {
        self.service = service ?? MapShopSearch()
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        guard !started else { return }
        started = true
        #if DEBUG
        if Self.usesFixtures {
            location = CLLocation(latitude: 31.2205, longitude: 121.462)
            locationState = .ready
            refreshNearby()
            return
        }
        #endif
        locate()
    }

    func locate() {
        guard locationState != .locating else { return }
        locationState = .locating
        nearbyError = nil
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: requestLocation()
        case .denied, .restricted: locationState = .denied
        @unknown default: locationState = .failed
        }
    }

    private func requestLocation() {
        manager.requestLocation()
        locationTimeout?.cancel()
        locationTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.locationState == .locating else { return }
            self.manager.stopUpdatingLocation()
            self.locationState = .failed
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard started else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if locationState == .locating || locationState == .denied { locationState = .locating; requestLocation() }
        case .denied, .restricted:
            locationTimeout?.cancel()
            location = nil
            nearby = []
            nearbyTask?.cancel()
            loadingNearby = false
            locationState = .denied
            locationRevision += 1
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard started else { return }
        guard let fix = locations.last(where: { $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 120 }) else {
            locationState = .failed; return
        }
        locationTimeout?.cancel()
        location = fix
        locationState = .ready
        locationRevision += 1
        refreshNearby()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard started else { return }
        locationTimeout?.cancel()
        locationState = manager.authorizationStatus == .denied ? .denied : .failed
    }

    func refreshNearby() {
        guard let location else { return }
        nearbyTask?.cancel()
        loadingNearby = true
        nearbyError = nil
        nearbyTask = Task { [weak self] in
            guard let self else { return }
            do {
                let places = try await service.search("", near: location.coordinate)
                guard !Task.isCancelled else { return }
                nearby = places.sorted { ($0.distance(from: location) ?? .infinity) < ($1.distance(from: location) ?? .infinity) }
                loadingNearby = false
            } catch {
                guard !Task.isCancelled else { return }
                nearbyError = "附近店铺暂时无法加载，请检查网络后重试。"
                loadingNearby = false
            }
        }
    }

    /// A revision check also protects against providers that finish after cancellation.
    func search(debounce: Bool = true) async {
        searchRevision += 1
        let revision = searchRevision
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        results = []
        searchError = nil
        searching = !term.isEmpty
        guard !term.isEmpty else { return }
        do {
            if debounce { try await Task.sleep(for: .milliseconds(400)) }
            try Task.checkCancellation()
            let places = try await service.search(term, near: location?.coordinate)
            guard !Task.isCancelled, revision == searchRevision else { return }
            results = places
            searching = false
        } catch {
            guard !Task.isCancelled, revision == searchRevision else { return }
            searchError = "搜索暂时不可用，请检查网络，或使用输入的店铺名。"
            searching = false
        }
    }

    func resolveCity(for place: ShopPlace) async -> ShopPlace {
        guard place.city.isEmpty, let coordinate = place.coordinate else { return place }
        var resolved = place
        if let mark = try? await CLGeocoder().reverseGeocodeLocation(
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            preferredLocale: Locale(identifier: "zh_CN")).first {
            resolved.city = ShopPlace.city(from: mark)
        }
        return resolved
    }

    func stop() {
        started = false
        searching = false
        loadingNearby = false
        if locationState == .locating { locationState = .idle }
        nearbyTask?.cancel()
        locationTimeout?.cancel()
        manager.stopUpdatingLocation()
        searchRevision += 1
    }

    static func distanceText(_ distance: CLLocationDistance) -> String {
        distance < 1000 ? String(format: distance < 100 ? "%.1f m" : "%.0f m", distance)
                        : String(format: "%.1f km", distance / 1000)
    }

    #if DEBUG
    static var usesFixtures: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--shop-fixtures")
    }
    static func make() -> ShopSearchModel {
        ShopSearchModel(service: usesFixtures ? FixtureShopSearch() : MapShopSearch())
    }
    #else
    static func make() -> ShopSearchModel { ShopSearchModel() }
    #endif
}

#if DEBUG
@MainActor struct FixtureShopSearch: ShopSearching {
    static let shanghai = ShopPlace(name: "Corner咖啡", city: "上海市", address: "瑞金一路8号",
                                    latitude: 31.2206, longitude: 121.4624)
    static let hangzhou = ShopPlace(name: "Corner咖啡（杭州店）", city: "杭州市", address: "中山北路100号",
                                    latitude: 30.2741, longitude: 120.1551)
    func search(_ query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [ShopPlace] {
        try await Task.sleep(for: .milliseconds(80))
        return query.isEmpty ? [Self.shanghai, ShopPlace(name: "ALWAYS Coffee&Bar", city: "上海市", address: "长乐路338号", latitude: 31.222, longitude: 121.462)]
                             : query.contains("不存在") ? [] : [Self.hangzhou, Self.shanghai]
    }
}
#endif
