import SwiftUI
import MapKit
import UIKit

struct MapUtilityTools: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @ObservedObject var journey: MapJourney
    var vertical: Bool

    var body: some View {
        let arrangement = vertical ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        arrangement {
            BrewGlassMenu(size: vertical ? 46 : 40, label: "地图筛选与店铺清单", identifier: "map.filters", items: filterItems)
            BrewGlassButton(size: vertical ? 46 : 40, customImage: BrewGlassButton.cupImage,
                            label: "添加想喝的店", identifier: "map.wish") { journey.searchPresented = true }
        }
    }
    private var filterItems: [BrewMenuItem] {
        [BrewMenuItem(title: "地球 · 全部店铺", image: "globe.asia.australia", action: { journey.showGlobe() }),
         BrewMenuItem(title: "查看店铺清单", image: "list.bullet", action: { journey.listPresented = true }),
         BrewMenuItem(title: "地图标记", children:
            [BrewMenuItem(title: "全部状态", action: { journey.status = nil; journey.selectedCafeID = nil })] +
            CafeMapStatus.allCases.map { status in BrewMenuItem(title: status.title, action: { journey.status = status; journey.selectedCafeID = nil }) }),
         BrewMenuItem(title: "城市", children:
            [BrewMenuItem(title: "全部城市", action: { journey.city = nil })] +
            Array(Set(store.mapCafes.map(\.place.city).filter { !$0.isEmpty })).sorted().map { city in
                BrewMenuItem(title: city, action: {
                    journey.city = city; journey.selectedCafeID = nil
                    if let coordinate = store.mapCafes.first(where: { $0.place.city == city })?.place.coordinate {
                        journey.zoom(to: coordinate, span: 0.15, animated: !layout.reduceMotion)
                    }
                })
            })]
    }

}

struct BrewMapPage: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.brewLayout) private var layout
    @ObservedObject var journey: MapJourney
    @StateObject private var location = MapLocation()
    @StateObject private var cities = GlobeCities()
    @State private var saveError: String?
    @State private var locationFlight: GlobeLocationFlight?
    @State private var flightTask: Task<Void, Never>?
    @State private var globeOpacity = 1.0
    @State private var flying = false
    @State private var viewportAudit = ""
    var onAdd: (ShopPlace) -> Void
    var onEdit: (DrinkRecord) -> Void

    private var cafes: [MapCafe] {
        store.mapCafes.filter { (journey.city == nil || $0.place.city == journey.city) &&
            (journey.status == nil || $0.status == journey.status) }
    }
    private var selected: MapCafe? { store.mapCafes.first { $0.id == journey.selectedCafeID } }
    private var bottom: CGFloat { layout.bottomNavigation && !layout.nativeNavigation ? 125 : 22 }
    private var leading: CGFloat { !layout.nativeNavigation && !layout.bottomNavigation && layout.leftHanded ? 80 : 16 }
    private var trailing: CGFloat { layout.nativeNavigation ? layout.controlRailInset + 16 : !layout.bottomNavigation && !layout.leftHanded ? 80 : 16 }

    var body: some View {
        ZStack {
            ZStack {
                if !journey.globe || locationFlight != nil {
                    streetMap
                        .opacity(journey.globe ? 1 - globeOpacity : 1)
                        .allowsHitTesting(!flying && !journey.globe)
                        .accessibilityHidden(journey.globe && globeOpacity >= 0.99)
                        .transition(.asymmetric(insertion: .identity, removal: .opacity))
                        .zIndex(0)
                }
                if journey.globe {
                    CoffeeGlobe(cafes: cafes, cities: cities.resolved, onCity: { cluster in
                        fly(to: cluster.fittedRegion(in: layout.size))
                    }, reduceMotion: layout.reduceMotion, locationFlight: locationFlight)
                    .background { BrewBackground().ignoresSafeArea() }
                    .opacity(globeOpacity)
                    .accessibilityIdentifier("map.globe")
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                    .zIndex(1)
                }
            }
            // Keep the outgoing map underneath the fading-in globe. The
            // opposite direction retains the existing location-flight reveal.
            .animation(layout.reduceMotion ? nil : .easeInOut(duration: 0.60), value: journey.globe)
            VStack(spacing: 5) {
                Text(journey.globe ? "在地球喝了 \(store.records.count) 杯" : journey.city ?? "咖啡足迹")
                    .font(BrewFont.heading)
                Text("\(store.mapCafes.filter { !$0.records.isEmpty }.count) 家店铺 · \(store.cities.count) 座城市 · \(store.wishlistPlaces.count) 家想喝")
                    .font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.top, layout.nativeNavigation && layout.systemTopInset > 0 ? layout.systemTopInset + 66
                     : layout.bottomNavigation ? 80 : layout.landscape ? 18 : 76)
            .padding(.leading, leading).padding(.trailing, trailing)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            if let selected {
                detail(selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.leading, leading).padding(.trailing, trailing)
                    .padding(.bottom, layout.addButtonFrame.isEmpty ? bottom : max(22, layout.size.height - layout.addButtonFrame.midY + 54))
                    .transition(layout.reduceMotion ? .opacity : .move(edge: .bottom))
                    // Keep the outgoing card above the opaque map until its
                    // removal transition finishes.
                    .zIndex(2)
            }
            GeometryReader { geometry in
                let root = geometry.frame(in: .named("brewRoot"))
                let count: CGFloat = journey.globe ? 1 : 2
                let width = count * 42 + (count - 1) * 9
                let add = layout.addButtonFrame
                let x = add.isEmpty ? geometry.size.width - trailing - width / 2
                    : layout.leftHanded ? add.maxX + 20 + width / 2 - root.minX : add.minX - 20 - width / 2 - root.minX
                // The map occupies the full window, including the space behind
                // horizontal tab chrome, so these controls share the add axis.
                let bottomChrome = layout.nativeNavigation && layout.controlRailInset == 0
                let y = add.isEmpty ? geometry.size.height - bottom - 21
                    : add.midY - root.minY - (bottomChrome ? 74 : 0)
                HStack(spacing: 9) {
                    if !journey.globe {
                        BrewGlassButton(symbol: "globe.asia.australia", size: 42,
                                        label: "回到地球", identifier: "map.world") { journey.showGlobe() }
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                    BrewGlassButton(symbol: "location", size: 42, loading: location.locating,
                                    label: "放大到当前位置", identifier: "map.locate") { location.locate() }
                        .disabled(flying || location.locating)
                }.frame(width: width, height: 42).position(x: x, y: y)
                    .animation(layout.reduceMotion ? nil : .easeInOut(duration: 0.30), value: journey.globe)
            }
        }
        .animation(layout.animation, value: selected?.id)
        .sheet(isPresented: $journey.searchPresented) {
            WishShopSearch { place in
                try store.addWish(place)
                journey.city = nil; journey.status = nil
                journey.selectedCafeID = store.mapCafes.first { $0.place.isSameBranch(as: place) }?.id
                if let coordinate = place.coordinate { journey.zoom(to: coordinate, animated: !layout.reduceMotion) }
                journey.searchPresented = false
            }
            .presentationDetents([.height(380), .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
            .presentationCornerRadius(30)
        }
        .sheet(isPresented: $journey.listPresented) { shopList }
        .onChange(of: location.revision) { _, _ in
            guard let fix = location.fix else { return }
            flyToLocation(fix.coordinate)
        }
        .task(id: cafes.filter { !$0.records.isEmpty }.map(\.place)) {
            await cities.load(cafes)
        }
        .onDisappear {
            journey.preserveViewport()
            location.stop(); cancelFlight()
        }
        .onChange(of: journey.globe) { _, showingGlobe in
            // Filter/search navigation can supersede an in-progress flight.
            if locationFlight != nil || (showingGlobe && flightTask != nil) { cancelFlight() }
        }
        .onChange(of: journey.searchPresented) { _, presented in
            if presented { cancelFlight() }
        }
        .onChange(of: journey.listPresented) { _, presented in
            if presented { cancelFlight() }
        }
        .alert("定位暂不可用", isPresented: Binding(get: { location.error != nil }, set: { if !$0 { location.error = nil } })) {
            Button("知道了", role: .cancel) { location.error = nil }
            Button("打开系统设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        } message: { Text(location.error ?? "") }
        .alert("未能保存", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("知道了", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
        .accessibilityElement(children: .contain).accessibilityIdentifier("map.page")
        .accessibilityValue(viewportAudit.isEmpty ? "" : "\(viewportAudit);following=\(journey.position.followsUserLocation ? 1 : 0);busy=\(flying ? 1 : 0)")
    }

    private func cancelFlight() {
        flightTask?.cancel(); flightTask = nil
        locationFlight = nil; globeOpacity = 1; flying = false
    }

    private func flyToLocation(_ coordinate: CLLocationCoordinate2D) {
        cancelFlight()
        journey.city = nil; journey.status = nil; journey.selectedCafeID = nil
        guard journey.globe && !layout.reduceMotion else {
            // A single native user-tracking target, rather than a raw-coordinate
            // flight followed by a second recenter in the basemap's datum.
            withAnimation(layout.reduceMotion ? nil : .easeInOut(duration: 0.9)) {
                journey.globe = false
                journey.followUserLocation(near: coordinate)
            }
            return
        }
        // Resolve the native user-centered map under the globe from the start.
        // Revealing it must not issue another camera target or tracking reset.
        journey.followUserLocation(near: coordinate)
        flying = true
        locationFlight = GlobeLocationFlight(coordinate: coordinate)
        flightTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.3))
                withAnimation(.easeOut(duration: 0.3)) { globeOpacity = 0 }
                try await Task.sleep(for: .seconds(0.32))
                try Task.checkCancellation()
                locationFlight = nil
                journey.globe = false
                globeOpacity = 1; flying = false; flightTask = nil
            } catch { }
        }
    }

    private func fly(to region: MKCoordinateRegion) {
        let coordinate = region.center
        cancelFlight()
        journey.city = nil; journey.status = nil; journey.selectedCafeID = nil
        guard journey.globe && !layout.reduceMotion else {
            journey.zoom(to: region, animated: !layout.reduceMotion)
            return
        }
        journey.position = .region(MKCoordinateRegion(center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: MapZoom.regionalSpan, longitudeDelta: MapZoom.regionalSpan)))
        flying = true
        locationFlight = GlobeLocationFlight(coordinate: coordinate)
        flightTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.3))
                withAnimation(.easeOut(duration: 0.24)) { globeOpacity = 0 }
                try await Task.sleep(for: .seconds(0.08))
                withAnimation(.easeInOut(duration: 1.45)) { journey.position = .region(region) }
                try await Task.sleep(for: .seconds(1.45))
                try Task.checkCancellation()
                locationFlight = nil
                journey.globe = false
                globeOpacity = 1; flying = false; flightTask = nil
            } catch { }
        }
    }

    private var streetMap: some View {
        CafeStreetMap(position: $journey.position, cafes: cafes,
                      selectedID: $journey.selectedCafeID, onCameraChange: { context in
            journey.rememberCamera(context.camera)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--map-viewport-audit") {
                let camera = context.camera
                viewportAudit = [camera.centerCoordinate.latitude, camera.centerCoordinate.longitude,
                                 camera.distance, camera.heading, camera.pitch].map(String.init(describing:)).joined(separator: ",")
            }
            #endif
        }, onCameraEnd: { context in
            if journey.position.positionedByUser && context.region.span.latitudeDelta > 105 { journey.showGlobe() }
        })
        .ignoresSafeArea()
    }

    private func detail(_ cafe: MapCafe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(cafe.place.name).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                    Text(cafe.records.isEmpty ? "想喝的店 · 还没有打卡" : "\(cafe.records.count) 次打卡 · \(cafe.status.title)")
                        .font(BrewFont.caption).foregroundStyle(BrewStyle.muted)
                    if !cafe.place.subtitle.isEmpty {
                        Text(cafe.place.subtitle).font(.system(size: 10)).foregroundStyle(BrewStyle.muted).lineLimit(2)
                    }
                }
                Spacer(minLength: 4)
                BrewGlassButton(symbol: "xmark", size: 38, label: "收起店铺详情", identifier: "map.closeDetail") {
                    journey.selectedCafeID = nil
                }
            }
            HStack(spacing: 16) {
                if !cafe.records.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(cafe.records) { record in
                                Button { onEdit(record) } label: {
                                    DrinkSticker(image: store.image(for: record), cutout: store.sticker(for: record), size: 64)
                                }.accessibilityLabel(record.name).accessibilityIdentifier("map.drink.\(record.id)")
                            }
                        }.padding(.horizontal, 3).padding(.vertical, 7)
                    }.scrollIndicators(.hidden).frame(height: 82)
                }
                // Keep the add action visible even after many visits to this cafe.
                if cafe.isWish {
                    Button { onAdd(cafe.place) } label: {
                        Image(systemName: "plus").font(.system(size: cafe.records.isEmpty ? 32 : 26, weight: .light))
                            .foregroundStyle(cafe.status.color)
                            .frame(width: cafe.records.isEmpty ? 82 : 64, height: cafe.records.isEmpty ? 82 : 64)
                            .background(cafe.status.color.opacity(0.10), in: Circle())
                            .overlay(Circle().stroke(cafe.status.color.opacity(0.45), lineWidth: 1))
                    }
                    .accessibilityLabel("在这家店添加饮品").accessibilityIdentifier("map.addDrink")
                    .padding(.vertical, 7)
                }
                if cafe.records.isEmpty { Spacer(minLength: 0) }
            }
            if cafe.isWish {
                Menu {
                    Button("移出想喝清单", role: .destructive) {
                        do { try store.removeWish(cafe.place); journey.selectedCafeID = nil }
                        catch { saveError = "请检查可用存储空间后重试。" }
                    }
                } label: { Text("想喝清单 · 已保存").font(.system(size: 10)).foregroundStyle(BrewStyle.muted) }
            }
        }
        .padding(18).frame(maxWidth: 650, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(BrewStyle.border.opacity(0.9), lineWidth: 1))
        .accessibilityElement(children: .contain).accessibilityIdentifier("map.detail")
        .accessibilityValue(cafe.status.rawValue)
    }

    private var shopList: some View {
        NavigationStack {
            List {
                ForEach(store.mapCafes) { cafe in
                    Button {
                        journey.city = nil; journey.status = nil; journey.selectedCafeID = cafe.id
                        if let coordinate = cafe.place.coordinate { journey.zoom(to: coordinate, animated: !layout.reduceMotion) }
                        journey.listPresented = false
                    } label: {
                        HStack {
                            Circle().fill(cafe.status.color).frame(width: 10, height: 10)
                            VStack(alignment: .leading) {
                                Text(cafe.place.name).foregroundStyle(BrewStyle.text)
                                Text("\(cafe.status.title) · \(cafe.place.city)").font(.caption).foregroundStyle(BrewStyle.muted)
                            }
                        }
                    }
                }
                if store.mapCafes.isEmpty { Text("搜索一家想喝的店，开始你的咖啡地图。") }
            }
            .navigationTitle("咖啡店铺")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { journey.listPresented = false } } }
        }.presentationDetents([.medium, .large])
    }
}

/// Entries arrive in the same back-to-front order used to paint the markers.
/// Work in screen points so the policy remains valid at every map scale.
enum CafeMarkerLabelLayout {
    struct Entry {
        var id: String
        var marker: CGRect
        var name: CGRect
    }

    static func visibleNames(_ entries: [Entry], selectedID: String?) -> Set<String> {
        guard !entries.isEmpty else { return [] }
        var parents = Array(entries.indices)
        func root(_ index: Int) -> Int {
            var node = index
            while parents[node] != node { node = parents[node] }
            return node
        }
        // Connected overlap groups get exactly one candidate name. A selected
        // marker wins even if it originally belonged to a lower drawing layer.
        for index in entries.indices {
            for other in 0..<index where entries[index].marker.intersects(entries[other].marker) {
                let first = root(index), second = root(other)
                parents[first] = second
            }
        }
        let priority = entries.indices.sorted { lhs, rhs in
            let leftSelected = entries[lhs].id == selectedID
            let rightSelected = entries[rhs].id == selectedID
            return leftSelected != rightSelected ? leftSelected : lhs > rhs
        }
        var groups = Set<Int>()
        var occupiedNames: [CGRect] = []
        var visible = Set<String>()
        for index in priority {
            guard groups.insert(root(index)).inserted else { continue }
            let entry = entries[index]
            guard !occupiedNames.contains(where: { $0.intersects(entry.name) }) else { continue }
            visible.insert(entry.id)
            occupiedNames.append(entry.name)
        }
        return visible
    }
}

private struct CafeStreetPlacement: Identifiable {
    var cafe: MapCafe
    var point: CGPoint
    var order: Int
    var selected: Bool
    var id: String { cafe.id }
    var markerHeight: CGFloat { selected ? 74 : 38 }
    var markerBounds: CGRect {
        CGRect(x: point.x - (selected ? 62 : 38) / 2, y: point.y - markerHeight,
               width: selected ? 62 : 38, height: markerHeight).insetBy(dx: -1.25, dy: -1.25)
    }
    var nameBounds: CGRect {
        let font = UIFont.systemFont(ofSize: 11, weight: .medium)
        let measured = (cafe.place.name as NSString).boundingRect(
            with: CGSize(width: 150, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
        let height = ceil(min(font.lineHeight * 2, measured.height))
        let width = min(150, ceil(measured.width))
        return CGRect(x: point.x - width / 2, y: point.y + 32 - height,
                      width: width, height: height).insetBy(dx: -3, dy: -2)
    }
    var labelEntry: CafeMarkerLabelLayout.Entry {
        .init(id: id, marker: markerBounds, name: nameBounds)
    }
}

/// SwiftUI owns both stacking and hit testing. Native annotation hit testing can
/// otherwise select an obscured annotation whose anchor is closer to the tap.
private struct CafeStreetMap: View {
    @Binding var position: MapCameraPosition
    var cafes: [MapCafe]
    @Binding var selectedID: String?
    var onCameraChange: (MapCameraUpdateContext) -> Void
    var onCameraEnd: (MapCameraUpdateContext) -> Void
    @State private var cameraRevision = 0

    var body: some View {
        MapReader { proxy in
            ZStack(alignment: .topLeading) {
                Map(position: $position) { UserAnnotation() }
                    .accessibilityIdentifier("map.street")
                    .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                    .onMapCameraChange(frequency: .continuous) { context in
                        cameraRevision &+= 1
                        onCameraChange(context)
                    }
                    .onMapCameraChange(frequency: .onEnd, onCameraEnd)
                // Reproject and resolve labels only in this layer as the camera moves.
                let _ = cameraRevision
                GeometryReader { geometry in
                    let viewport = CGRect(origin: .zero, size: geometry.size)
                    let placements: [CafeStreetPlacement] = cafes.enumerated().compactMap { index, cafe in
                        guard let coordinate = cafe.place.coordinate,
                              let point = proxy.convert(coordinate, to: .local),
                              point.x.isFinite, point.y.isFinite else { return nil }
                        let item = CafeStreetPlacement(cafe: cafe, point: point, order: index, selected: selectedID == cafe.id)
                        return item.markerBounds.intersects(viewport) || item.nameBounds.intersects(viewport) ? item : nil
                    }
                    let visibleNames = CafeMarkerLabelLayout.visibleNames(placements.map(\.labelEntry), selectedID: selectedID)
                    ZStack(alignment: .topLeading) {
                        ForEach(placements) { item in
                            let cafe = item.cafe
                            let showsName = visibleNames.contains(item.id)
                            Button { selectedID = cafe.id } label: {
                                CafeMapMarker(status: cafe.status, selected: item.selected)
                                    .contentShape(CafePinOutline(expansion: item.selected ? 1 : 0))
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .bottom) {
                                if showsName {
                                    Text(cafe.place.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .frame(width: 150).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                        .offset(y: 32).allowsHitTesting(false)
                                }
                            }
                            .position(x: item.point.x, y: item.point.y - item.markerHeight / 2)
                            .zIndex(item.selected ? Double(cafes.count) : Double(item.order))
                            .accessibilityElement(children: .ignore)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel("\(cafe.place.name)，\(cafe.status.title)，\(cafe.records.count)次打卡")
                            .accessibilityValue(showsName ? "显示店名" : "隐藏店名")
                            .accessibilityIdentifier("map.cafe.\(cafe.place.name)")
                        }
                    }
                }
                .clipped()
            }
        }
    }
}

struct CafeMapMarker: View {
    var status: CafeMapStatus
    var selected = false
    var count: Int? = nil
    var body: some View {
        ZStack(alignment: .top) {
            let outline = CafePinOutline(expansion: selected ? 1 : 0)
            outline.fill(status.color)
                .overlay(outline.stroke(.white, lineWidth: 2.5))
                .frame(width: selected ? 62 : 38, height: selected ? 74 : 38)
            Group {
                if let count, count > 1 { Text("\(count)").font(.system(size: 15, weight: .semibold)) }
                else { TakeawayCup().stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)).frame(width: 20, height: 25) }
            }
            .foregroundStyle(.white).frame(width: selected ? 62 : 38, height: selected ? 60 : 38)
        }
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }
}

private struct CafePinOutline: Shape {
    var expansion: CGFloat = 1
    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    // Both outlines share six cubic segments. Interpolating their control
    // points preserves one fill/stroke identity throughout selection, so the
    // circle grows a pin tip instead of cross-fading between two separate views.
    private static let pinPoints: [CGPoint] = [
        CGPoint(x: 50, y: 116),
        CGPoint(x: 47, y: 116), CGPoint(x: 44, y: 102), CGPoint(x: 37, y: 96),
        CGPoint(x: 16, y: 90), CGPoint(x: 4, y: 72), CGPoint(x: 4, y: 50),
        CGPoint(x: 4, y: 24), CGPoint(x: 24, y: 4), CGPoint(x: 50, y: 4),
        CGPoint(x: 76, y: 4), CGPoint(x: 96, y: 24), CGPoint(x: 96, y: 50),
        CGPoint(x: 96, y: 72), CGPoint(x: 84, y: 90), CGPoint(x: 63, y: 96),
        CGPoint(x: 56, y: 102), CGPoint(x: 53, y: 116), CGPoint(x: 50, y: 116)
    ]

    private static let circlePoints: [CGPoint] = {
        let angles: [CGFloat] = [.pi / 2, 2 * .pi / 3, .pi, 3 * .pi / 2, 2 * .pi, 7 * .pi / 3, 5 * .pi / 2]
        var points = [CGPoint(x: 0.5, y: 1)]
        for index in 0..<(angles.count - 1) {
            let start = angles[index], end = angles[index + 1]
            let tangent = 4 / CGFloat(3) * tan((end - start) / 4)
            let from = CGPoint(x: 0.5 + 0.5 * cos(start), y: 0.5 + 0.5 * sin(start))
            let to = CGPoint(x: 0.5 + 0.5 * cos(end), y: 0.5 + 0.5 * sin(end))
            points.append(CGPoint(x: from.x - tangent * 0.5 * sin(start), y: from.y + tangent * 0.5 * cos(start)))
            points.append(CGPoint(x: to.x + tangent * 0.5 * sin(end), y: to.y - tangent * 0.5 * cos(end)))
            points.append(to)
        }
        return points
    }()

    func path(in rect: CGRect) -> Path {
        let progress = min(1, max(0, expansion))
        func point(_ index: Int) -> CGPoint {
            let circle = Self.circlePoints[index], pin = Self.pinPoints[index]
            return CGPoint(x: rect.minX + (circle.x + (pin.x / 100 - circle.x) * progress) * rect.width,
                           y: rect.minY + (circle.y + (pin.y / 120 - circle.y) * progress) * rect.height)
        }
        var path = Path()
        path.move(to: point(0))
        for index in stride(from: 1, to: Self.pinPoints.count, by: 3) {
            path.addCurve(to: point(index + 2), control1: point(index), control2: point(index + 1))
        }
        path.closeSubpath()
        return path
    }
}
