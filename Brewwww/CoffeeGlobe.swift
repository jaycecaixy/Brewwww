import SwiftUI
import CoreLocation
import MapKit

struct GlobeCity: Codable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
    }
}

struct GlobeCluster: Identifiable {
    var id: String
    var coordinate: CLLocationCoordinate2D
    var status: CafeMapStatus
    var count: Int
    var name: String
    var region: MKCoordinateRegion

    static func make(_ cafes: [MapCafe], cities: [String: GlobeCity] = [:]) -> [GlobeCluster] {
        let visited = cafes.filter { !$0.records.isEmpty && $0.place.coordinate != nil }
        let knownCities = Dictionary(grouping: visited.filter { cities[$0.id] != nil && !$0.place.city.isEmpty }) { $0.place.city }
        func resolvedCity(for cafe: MapCafe) -> GlobeCity? {
            cities[cafe.id] ?? knownCities[cafe.place.city]?.first.flatMap { cities[$0.id] }
        }
        let groups = Dictionary(grouping: visited) { resolvedCity(for: $0)?.id ?? ($0.place.city.isEmpty ? $0.id : "city|" + $0.place.city) }
        return groups.sorted { $0.key < $1.key }.map { key, members in
            let city = members.compactMap { resolvedCity(for: $0) }.first
            let center = city?.coordinate ?? CLLocationCoordinate2D(
                latitude: members.map { $0.place.latitude! }.reduce(0, +) / Double(members.count),
                longitude: members.map { $0.place.longitude! }.reduce(0, +) / Double(members.count))
            var rect = city.map { MKMapRect.regionBounds($0.region) } ?? MKMapRect.null
            for cafe in members {
                let point = MKMapPoint(cafe.place.coordinate!)
                rect = rect.union(MKMapRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
            }
            if city == nil {
                rect = rect.union(.regionBounds(MKCoordinateRegion(center: center, latitudinalMeters: 60_000, longitudinalMeters: 60_000)))
            }
            let region = MKCoordinateRegion(rect)
            return GlobeCluster(id: key, coordinate: center, status: .visited, count: members.count,
                                name: city?.name ?? (members[0].place.city.isEmpty ? members[0].place.name : members[0].place.city), region: region)
        }
    }

    func fittedRegion(in size: CGSize) -> MKCoordinateRegion {
        // Leave room for the top title, bottom controls and side rail.
        let aspect = max(0.25, (size.width - 100) / max(1, size.height - 230))
        let latitude = region.span.latitudeDelta * 1.35
        let longitude = region.span.longitudeDelta * 1.35
        let cosine = max(0.1, cos(region.center.latitude * .pi / 180))
        return MKCoordinateRegion(center: region.center, span: MKCoordinateSpan(
            latitudeDelta: min(170, max(latitude, longitude * cosine / aspect)),
            longitudeDelta: min(350, max(longitude, latitude * aspect / cosine))))
    }
}

private extension MKMapRect {
    static func regionBounds(_ region: MKCoordinateRegion) -> MKMapRect {
        let a = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                                 longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let b = MKMapPoint(CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                                 longitude: region.center.longitude + region.span.longitudeDelta / 2))
        return MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

/// Resolve city centers and extents, without moving pins away from their coordinates.
/// Cache by coordinate so edits and repeated globe visits do not repeat requests.
@MainActor final class GlobeCities: ObservableObject {
    @Published private(set) var resolved: [String: GlobeCity] = [:]
    private var cache: [String: GlobeCity] = [:]
    private let key = "globeCityCache.v1"
    init() {
        cache = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: GlobeCity].self, from: $0) } ?? [:]
    }
    func load(_ cafes: [MapCafe]) async {
        let geocoder = CLGeocoder()
        let visited = cafes.filter { !$0.records.isEmpty && $0.place.coordinate != nil }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--globe-city-fixtures") {
            resolved = Dictionary(uniqueKeysWithValues: visited.map { ($0.id, GlobeCity(
                id: "CN|上海市|上海市", name: "上海市", latitude: 31.23, longitude: 121.47, radius: 60_000)) })
            return
        }
        #endif
        func cacheKey(_ cafe: MapCafe) -> String {
            String(format: "%.6f|%.6f", cafe.place.latitude!, cafe.place.longitude!)
        }
        resolved = Dictionary(uniqueKeysWithValues: visited.compactMap { cafe in cache[cacheKey(cafe)].map { (cafe.id, $0) } })
        for cafe in visited where resolved[cafe.id] == nil {
            guard !Task.isCancelled, let coordinate = cafe.place.coordinate else { return }
            do {
                let marks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), preferredLocale: Locale(identifier: "zh_CN"))
                try Task.checkCancellation()
                guard let mark = marks.first,
                      let name = mark.locality ?? mark.administrativeArea, !name.isEmpty else { continue }
                let parts = [mark.isoCountryCode, mark.administrativeArea, name].compactMap { $0 }
                let id = parts.joined(separator: "|")
                var city = cache.values.first { $0.id == id }
                if city == nil {
                    try await Task.sleep(for: .seconds(1.3))
                    let areas = try await geocoder.geocodeAddressString([mark.country, mark.administrativeArea, name].compactMap { $0 }.joined(separator: " "), in: nil, preferredLocale: Locale(identifier: "zh_CN"))
                    try Task.checkCancellation()
                    guard let area = areas.first, let boundary = area.region as? CLCircularRegion else { continue }
                    city = GlobeCity(id: id, name: name, latitude: boundary.center.latitude,
                                             longitude: boundary.center.longitude, radius: max(1_000, boundary.radius))
                }
                if let city {
                    cache[cacheKey(cafe)] = city
                    for member in visited where member.id == cafe.id || (!cafe.place.city.isEmpty && member.place.city == cafe.place.city) {
                        cache[cacheKey(member)] = city
                        resolved[member.id] = city
                    }
                    if let data = try? JSONEncoder().encode(cache) { UserDefaults.standard.set(data, forKey: key) }
                }
                try await Task.sleep(for: .seconds(1.3))
            } catch {
                if Task.isCancelled { return }
                // Keep unresolved cities near their shops until the city center is available.
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

enum GlobeProjection {
    struct Vertex {
        let x: Double
        let y: Double
        let z: Double

        init(latitude: Double, longitude: Double) {
            let lat = latitude * .pi / 180, lon = longitude * .pi / 180
            x = cos(lat) * cos(lon)
            y = sin(lat)
            z = cos(lat) * sin(lon)
        }
    }

    /// Camera trigonometry is evaluated once per frame, and coastline vertices
    /// are converted to unit vectors once when the bundled data is loaded.
    struct Camera {
        let sinLongitude: Double
        let cosLongitude: Double
        let sinPitch: Double
        let cosPitch: Double

        init(longitude: Double, tilt: Double) {
            sinLongitude = sin(longitude * .pi / 180)
            cosLongitude = cos(longitude * .pi / 180)
            sinPitch = sin(tilt * .pi / 180)
            cosPitch = cos(tilt * .pi / 180)
        }

        func point(_ vertex: Vertex, center: CGPoint, radius: CGFloat) -> CGPoint? {
            let forward = vertex.x * cosLongitude + vertex.z * sinLongitude
            let depth = vertex.y * sinPitch + forward * cosPitch
            guard depth > 0.015 else { return nil }
            let x = vertex.z * cosLongitude - vertex.x * sinLongitude
            let y = vertex.y * cosPitch - forward * sinPitch
            return CGPoint(x: center.x + radius * x, y: center.y - radius * y)
        }
    }

    static func point(latitude: Double, longitude: Double, centerLongitude: Double, tilt: Double,
                      center: CGPoint, radius: CGFloat) -> CGPoint? {
        Camera(longitude: centerLongitude, tilt: tilt)
            .point(Vertex(latitude: latitude, longitude: longitude), center: center, radius: radius)
    }
}

/// Orthographic sphere with bundled, public-domain coastline vectors. No globe
/// tile request is needed; nearby street maps are supplied by MapKit separately.
struct GlobeLocationFlight: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

enum GlobeZoom {
    static let minimumScale: CGFloat = 0.4

    static func baseRadius(in size: CGSize) -> CGFloat {
        min(size.width * 0.85, size.height * 0.55)
    }

    static func maximumScale(in size: CGSize) -> CGFloat {
        let radius = baseRadius(in: size)
        guard radius > 0 else { return 1 }
        // The shortest viewport edge must still cover the regional map's
        // starting span. A globe pinch never zooms closer than that handoff.
        let halfAngle = MapZoom.regionalSpan * .pi / 360
        return max(1, min(size.width, size.height) / (2 * radius * sin(halfAngle)))
    }

    static func clamped(_ scale: CGFloat, in size: CGSize) -> CGFloat {
        min(maximumScale(in: size), max(minimumScale, scale))
    }
}

private struct GlobeCityBadge: View {
    var cluster: GlobeCluster
    var showsName: Bool
    var onSelect: () -> Void
    var body: some View {
        Button { onSelect() } label: {
            CafeMapMarker(status: .visited)
                .overlay(alignment: .topTrailing) {
                    if cluster.count > 1 {
                        Text("\(cluster.count)").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 3)
                            .background(BrewStyle.mapPin, in: Capsule())
                            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                            .offset(x: 6, y: -8)
                    }
                }
        }
        .overlay(alignment: .bottom) {
            if showsName {
                Text(cluster.name).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BrewStyle.text).frame(width: 90).lineLimit(1)
                    .offset(y: 18).allowsHitTesting(false)
                    .accessibilityIdentifier("globe.cityName.\(cluster.id)")
            }
        }
        .accessibilityIdentifier("globe.city.\(cluster.id)")
        .accessibilityLabel("\(cluster.name)，喝过\(cluster.count)家店，放大查看城市")
    }
}

struct CoffeeGlobe: View {
    @AppStorage("showGlobeDistrictNames") private var showCityNames = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var longitude = 110.0
    @State private var tilt = 26.0
    @State private var epoch = Date()
    @State private var dragging = false
    @State private var dragOrigin: (Double, Double)?
    @GestureState private var magnification: CGFloat = 1
    @State private var globeScale: CGFloat = 1
    var cafes: [MapCafe]
    var cities: [String: GlobeCity] = [:]
    var onCity: (GlobeCluster) -> Void = { _ in }
    var reduceMotion: Bool
    var locationFlight: GlobeLocationFlight? = nil
    @State private var flightStart: Date?
    @State private var flightOrigin = (longitude: 110.0, tilt: 26.0, scale: CGFloat(1))
    private var rotating: Bool { !reduceMotion && scenePhase == .active && !dragging && locationFlight == nil }

    var body: some View {
        let clusters = GlobeCluster.make(cafes, cities: cities)
        TimelineView(.animation(minimumInterval: locationFlight == nil ? 1.0 / 30 : 1.0 / 60,
                               paused: scenePhase != .active || (!rotating && locationFlight == nil))) { timeline in
            let elapsed = flightStart.map { timeline.date.timeIntervalSince($0) } ?? 0
            let turn = eased(elapsed / 0.82)
            let zoom = eased((elapsed - 0.65) / 0.63)
            let destination = locationFlight?.coordinate
            let meridian = destination.map {
                flightOrigin.longitude + normalized($0.longitude - flightOrigin.longitude) * turn
            } ?? (longitude + (rotating ? timeline.date.timeIntervalSince(epoch) * 1.6 : 0))
            let pitch = destination.map { flightOrigin.tilt + ($0.latitude - flightOrigin.tilt) * turn } ?? tilt
            let camera = GlobeProjection.Camera(longitude: meridian, tilt: pitch)
            GeometryReader { geometry in
                let size = geometry.size
                let baseRadius = GlobeZoom.baseRadius(in: size)
                let flightScale = flightOrigin.scale + (max(5.2, flightOrigin.scale) - flightOrigin.scale) * zoom
                let scale = GlobeZoom.clamped(destination == nil ? globeScale * magnification : flightScale, in: size)
                let radius = baseRadius * scale
                let center = CGPoint(x: size.width / 2, y: size.height * (0.60 - 0.10 * zoom))
                ZStack {
                    BrewBackground()
                        .frame(width: baseRadius * 2, height: baseRadius * 2).clipShape(Circle())
                        .overlay(Circle().stroke(BrewStyle.icon.opacity(0.65), lineWidth: 1.2))
                        .drawingGroup()
                        .scaleEffect(scale)
                        .position(center)
                    Canvas { context, _ in
                        var path = Path()
                        for line in GlobeCoastlines.vertices {
                            var previous: CGPoint?
                            for vertex in line {
                                guard let point = camera.point(vertex, center: center, radius: radius) else {
                                    previous = nil; continue
                                }
                                if previous != nil { path.addLine(to: point) } else { path.move(to: point) }
                                previous = point
                            }
                        }
                        context.stroke(path, with: .color(BrewStyle.icon.opacity(0.75)), lineWidth: 0.65)
                    }
                    ForEach(clusters) { cluster in
                        if let point = camera.point(.init(latitude: cluster.coordinate.latitude, longitude: cluster.coordinate.longitude),
                                                    center: center, radius: radius) {
                            GlobeCityBadge(cluster: cluster, showsName: showCityNames) { onCity(cluster) }
                                .position(point)
                        }
                    }
                    VStack {
                        Spacer()
                        Text("拖动旋转 · 双指缩放地球 · 点城市查看地图")
                            .font(.system(size: 10)).foregroundStyle(BrewStyle.muted)
                            .padding(.bottom, size.width >= 600 && size.height > size.width ? 120 : 26)
                    }.opacity(destination == nil ? 1 : 0).allowsHitTesting(false)
                }
                .frame(width: size.width, height: size.height).clipped()
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        if dragOrigin == nil {
                            longitude = meridian; dragging = true; dragOrigin = (meridian, tilt)
                        }
                        if let origin = dragOrigin {
                            longitude = origin.0 - value.translation.width * 0.25
                            tilt = min(65, max(-65, origin.1 + value.translation.height * 0.18))
                        }
                    }
                    .onEnded { _ in dragOrigin = nil; epoch = Date(); dragging = false })
                .simultaneousGesture(MagnificationGesture()
                    .updating($magnification) { value, state, _ in state = value }
                    .onEnded { factor in
                        globeScale = GlobeZoom.clamped(globeScale * factor, in: size)
                    })
            }
        }
        .allowsHitTesting(locationFlight == nil)
        .onChange(of: locationFlight?.id) { _, _ in
            guard locationFlight != nil else { flightStart = nil; return }
            flightOrigin = (longitude + (rotating ? Date().timeIntervalSince(epoch) * 1.6 : 0), tilt, globeScale)
            // rotating is already false once a flight is supplied; capture the
            // accumulated idle rotation explicitly to avoid a jump on takeoff.
            if !reduceMotion && scenePhase == .active && !dragging {
                flightOrigin.longitude = longitude + Date().timeIntervalSince(epoch) * 1.6
            }
            flightStart = Date()
        }
        .onChange(of: scenePhase) { old, new in
            if old == .active && new != .active && !reduceMotion && !dragging {
                longitude += Date().timeIntervalSince(epoch) * 1.6
            }
            epoch = Date()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("咖啡地球")
        .accessibilityValue("\(rotating ? "缓缓旋转" : "静止")，城市名称\(showCityNames ? "已显示" : "已隐藏")")

    }
    private func eased(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * (3 - 2 * t)
    }
    private func normalized(_ longitude: Double) -> Double {
        ((longitude + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180
    }
}

private enum GlobeCoastlines {
    static let vertices: [[GlobeProjection.Vertex]] = lines.map { line in
        line.map { GlobeProjection.Vertex(latitude: $0[1], longitude: $0[0]) }
    }
    static let lines: [[[Double]]] = {
        guard let url = Bundle.main.url(forResource: "coastline", withExtension: "geojson"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = object["features"] as? [[String: Any]] else { return [] }
        return features.flatMap { feature -> [[[Double]]] in
            guard let geometry = feature["geometry"] as? [String: Any] else { return [] }
            if let line = geometry["coordinates"] as? [[Double]] { return [line] }
            return geometry["coordinates"] as? [[[Double]]] ?? []
        }
    }()
}
