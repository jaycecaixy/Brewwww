import SwiftUI
import PhotosUI
import CoreLocation
import UIKit
import os

enum BrewScreen: String, CaseIterable {
    case home, drinks, cards, stamps, map, settings
}

private final class FolderGeometryCache {
    // Geometry preferences arrive on every animated calendar layout frame.
    // The album reads the latest frame when opened; storing it must not
    // invalidate the entire home page while the calendar is resizing.
    var frame = CGRect.zero
}

struct ContentView: View {
    @EnvironmentObject private var store: BrewStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("handedness") private var handedness = "right"
    @State private var hinge: BrewHingeState = .unavailable
    @State private var keyboardInset: CGFloat = 0
    @Namespace private var navigationSelection
    @State private var screen: BrewScreen = .home
    @State private var selectedMonth = Date()
    @State private var selectedDate = Date()
    @State private var weekMode = false
    @State private var playfulMug = PlayfulMugState()
    @State private var editing: DrinkRecord?
    @State private var editImage: UIImage?
    @State private var sourceMenuVisible = false
    @State private var addButtonFrame = CGRect.zero
    @State private var showCamera = false
    @State private var selectedPhoto: PhotosPickerItem?
    @StateObject private var mapJourney = MapJourney()
    @StateObject private var settingsNavigation = SettingsNavigation()
    @State private var nativeChrome = NativeTabChrome()
    @State private var sidebarGeometry = SidebarGeometry()
    @State private var stampRoute: StampRoute = .collection
    @State private var stampCityFilter: String?
    @State private var folderGeometry = FolderGeometryCache()
    private var folderFrame: CGRect {
        get { folderGeometry.frame }
        nonmutating set { folderGeometry.frame = newValue }
    }
    @State private var monthVisible = false
    @State private var monthDrag: CGFloat = 0
    @State private var albumVisible = false
    @State private var albumProgress: CGFloat = 0
    @State private var albumTask: Task<Void, Never>?
    @State private var launchVisible = true
    @State private var launchStarted = false
    @State private var launchContentOpacity = 0.0
    @State private var launchLogoOpacity = 1.0
    @State private var calendarEntranceReady = false

    var body: some View {
        GeometryReader { geometry in
            let layout = BrewLayout(size: geometry.size, hinge: effectiveHinge,
                                    leftHanded: handedness == "left",
                                    reduceMotion: reduceMotion || systemReduceMotion,
                                    keyboardInset: keyboardInset,
                                    windowSize: geometry.size,
                                    utilityRegion: utilityRegion(in: geometry.size),
                                    sidebarAxis: nativeChrome.vertical && !nativeChrome.barFrame.isEmpty
                                        ? nativeChrome.columnX : sidebarGeometry.axisX,
                                    addButtonFrame: addButtonFrame,
                                    controlRailInset: nativeChrome.vertical ? max(0, geometry.size.width - nativeChrome.pageFrame.width) : 0)
            ZStack {
                BrewBackground().blur(radius: sourceMenuVisible ? 34 : 0, opaque: true)
                Group {
                    if let editing {
                    RecordEditor(record: editing, photo: editImage,
                                 onCancel: { self.editing = nil },
                                 onSave: { record, photo, stickerData in
                        if store.records.contains(where: { $0.id == record.id }) {
                            try store.update(record, photo: photo, stickerData: stickerData)
                        } else {
                            try store.add(record, photo: photo, stickerData: stickerData)
                        }
                        self.editing = nil
                        self.editImage = nil
                        selectedMonth = record.date
                        selectedDate = record.date
                    }, onDelete: store.records.contains(where: { $0.id == editing.id }) ? {
                        store.delete(editing)
                        self.editing = nil
                    } : nil)
                    .id(editing.id)
                    .transition(layout.reduceMotion ? .opacity : .move(edge: .bottom))
                    .zIndex(30)
                    } else {
                        Group {
                            if #available(iOS 26.0, *) {
                                nativeNavigation(layout)
                            } else if layout.bottomNavigation {
                                mainPage
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .overlay(alignment: .topLeading) { utilityButtons.padding(16) }
                                    .overlay(alignment: .bottom) { bottomNavigation(layout).padding(.bottom, 28).zIndex(10) }
                            } else if screen == .map {
                                mainPage
                                    .overlay(alignment: layout.leftHanded ? .leading : .trailing) {
                                        navigationRail(layout).zIndex(10)
                                    }
                            } else {
                                HStack(spacing: 0) {
                                    if layout.leftHanded { navigationRail(layout).zIndex(10) }
                                    mainPage.frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                        .id(screen)
                                    if !layout.leftHanded { navigationRail(layout).zIndex(10) }
                                }
                            }
                        }
                        .modifier(AlbumBackgroundBlur(progress: albumProgress))
                        .blur(radius: sourceMenuVisible ? 34 : 0)
                        .allowsHitTesting(!albumVisible && !monthVisible && !sourceMenuVisible)
                        .accessibilityHidden(albumVisible || monthVisible || sourceMenuVisible)
                    }
                }
                .environment(\.brewLayout, layout)
                .environment(\.folderPhotosHidden, albumVisible)
                .opacity(launchContentOpacity)
                .allowsHitTesting(!launchVisible)
                .accessibilityHidden(launchVisible)
                if monthVisible {
                    let monthLayout = monthLayout(layout, topInset: max(geometry.safeAreaInsets.top, nativeChrome.topSafeArea))
                    ZStack {
                        BrewBackground()
                            .contentShape(Rectangle())
                            .gesture(monthDismissGesture(layout))
                        DrinksPage(month: $selectedMonth, onRecord: {
                            monthVisible = false
                            editing = $0; editImage = nil
                        }, onClose: { closeMonth(layout) },
                           onDrag: { updateMonthDrag($0) }, onDragEnd: { distance, predicted in
                            finishMonthDrag(distance: distance, predicted: predicted, layout: layout)
                        }, closeButtonX: nativeChrome.vertical ? nativeChrome.columnX - geometry.frame(in: .global).minX : nil)
                        .background {
                            Color.clear.contentShape(Rectangle())
                                .gesture(monthDismissGesture(layout))
                        }
                    }
                    .environment(\.brewLayout, monthLayout)
                    .scaleEffect(1 - min(monthDrag / max(1, layout.size.height), 1) * 0.08, anchor: .top)
                    .offset(y: monthDrag)
                    .transition(layout.reduceMotion ? .opacity : .move(edge: .bottom))
                    .zIndex(19)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("month.overlay")
                    .accessibilityAction(.escape) { closeMonth(layout) }
                }
                if albumVisible {
                    PhotoAlbumOverlay(month: $selectedMonth, folderFrame: folderFrame, progress: albumProgress,
                                      onClose: { closeAlbum(layout: layout) })
                        .environment(\.brewLayout, layout)
                        .environment(\.brewControlSurface, BrewStyle.albumControl)
                        .transition(.identity).zIndex(20)
                }
                if launchVisible {
                    LaunchLogoMark()
                        .frame(width: min(geometry.size.width * 1.08, geometry.size.height * 0.80, 560) / 4,
                               height: min(geometry.size.width * 1.08, geometry.size.height * 0.80, 560) / 4)
                        .opacity(launchLogoOpacity)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .contentShape(Rectangle())
                        .allowsHitTesting(true)
                        .accessibilityIdentifier("launch.logo")
                        .zIndex(100)
                }
                SourceChoiceOverlay(visible: sourceMenuVisible, layout: layout, addButtonFrame: addButtonFrame,
                    selection: $selectedPhoto, onCamera: {
                        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
                        setSourceMenu(false)
                        showCamera = true
                    }, onCancel: { setSourceMenu(false) })
                    .zIndex(40)
                if editing == nil && !addButtonFrame.isEmpty {
                    sourceActionButton(size: addButtonFrame.width)
                        .position(x: addButtonFrame.midX, y: addButtonFrame.midY)
                        .modifier(AlbumBackgroundBlur(progress: albumProgress))
                        .opacity(launchContentOpacity)
                        .allowsHitTesting(!launchVisible && !albumVisible && !monthVisible)
                        .accessibilityHidden(launchVisible || albumVisible || monthVisible)
                        .zIndex(sourceMenuVisible ? 41 : 1)
                }
            }
            .animation(layout.animation, value: editing?.id)
            .animation(layout.settingsAnimation, value: screen == .settings)
            .animation(layout.animation, value: layout.leftHanded)
            .onChange(of: layout, initial: true) { _, value in exportFoldAudit(value) }
            .onChange(of: nativeChrome) { _, _ in exportFoldAudit(layout) }
            .onChange(of: addButtonFrame) { _, _ in exportFoldAudit(layout) }
            .onChange(of: launchVisible) { _, _ in exportFoldAudit(layout) }
            .onChange(of: screen) { _, _ in playfulMug.cancel() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in playfulMug.cancel() }
            .onDisappear { playfulMug.cancel() }
            .coordinateSpace(name: "brewRoot")
            .onPreferenceChange(AddButtonFrameKey.self) { frame in
                if !frame.isEmpty && frame != addButtonFrame { addButtonFrame = frame }
            }
            .onPreferenceChange(FolderFrameKey.self) { frame in
                if !frame.isEmpty { folderFrame = frame }
            }
            .background(HingeObserver(state: $hinge).allowsHitTesting(false))
            .background(BrewOrientationObserver(allowLandscape: layout.allowsLandscape).allowsHitTesting(false))
            .background(SidebarGeometryReader { value in
                if sidebarGeometry.frame.isEmpty { sidebarGeometry = value }
                else { withAnimation(layout.reduceMotion ? nil : .easeInOut(duration: 0.20)) { sidebarGeometry = value } }
            }.allowsHitTesting(false))
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let overlap = max(0, geometry.frame(in: .global).maxY - frame.minY)
                withAnimation(reduceMotion || systemReduceMotion ? nil : .easeOut(duration: 0.25)) {
                    keyboardInset = overlap
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardInset = 0
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .trailing])
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environment(\.brewControlSurface, screen == .cards && editing == nil ? BrewStyle.albumControl
                     : screen == .map && editing == nil ? BrewStyle.mapControl : BrewStyle.control)
        .tint(BrewStyle.gold)
        .foregroundStyle(BrewStyle.text)
        .font(BrewFont.body)
        .buttonStyle(BrewPressStyle())
        .task(id: sourceMenuVisible) {
            if sourceMenuVisible { await SubjectCutoutService.shared.prepareIfNeeded() }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image, captureDate in
                showCamera = false
                if let image { openEditor(photo: image, date: captureDate) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        setSourceMenu(false)
                        openEditor(photo: image, date: PhotoTimestamp.captureDate(in: data))
                        selectedPhoto = nil
                    }
                }
            }
        }
        .onChange(of: selectedMonth) { _, month in
            if albumVisible { selectedDate = month }
        }
        .onAppear(perform: configurePreview)
        .task { await showLaunchLogo() }
        .environment(\.calendarEntranceReady, calendarEntranceReady)
    }

    @MainActor private func showLaunchLogo() async {
        guard !launchStarted else { return }
        launchStarted = true
        do {
            try await Task.sleep(for: .seconds(1))
            try Task.checkCancellation()
            withAnimation(.easeOut(duration: reduceMotion || systemReduceMotion ? 0.14 : 0.24),
                          completionCriteria: .removed) {
                launchLogoOpacity = 0
                launchContentOpacity = 1
            } completion: {
                // The sticker tasks are released only after the home fade ends.
                launchVisible = false
                calendarEntranceReady = true
            }
        } catch {
            launchStarted = false
        }
    }

    private var effectiveHinge: BrewHingeState {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-partial-hinge") { return .partiallyOpen }
        #endif
        return hinge
    }

    private func configurePreview() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let raw = arguments.first(where: { $0.hasPrefix("--screen=") })?.split(separator: "=").last,
           let destination = BrewScreen(rawValue: String(raw)) {
            if destination == .cards { screen = .home; openAlbum() }
            else { screen = destination }
        }
        if arguments.contains("--preview-editor") {
            editing = DrinkRecord(shop: "MIND BALANCE", city: "上海市", name: "古罗马美式")
        }
        if arguments.contains("--ui-testing") {
            if arguments.contains("--globe-city-fixtures") {
                store.records = [
                    DrinkRecord(shop: "杨浦咖啡 A", city: "上海市", name: "美式", latitude: 31.29, longitude: 121.51),
                    DrinkRecord(shop: "杨浦咖啡 B", city: "上海市", name: "拿铁", latitude: 31.31, longitude: 121.53)
                ]
            }
            if arguments.contains("--map-overlap-fixture") {
                store.records = [
                    DrinkRecord(shop: "Overlap A", city: "上海市", name: "下层饮品", latitude: 31.2304, longitude: 121.4737),
                    DrinkRecord(shop: "Overlap Z", city: "上海市", name: "上层饮品", latitude: 31.2304, longitude: 121.4737)
                ]
                mapJourney.zoom(to: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737), animated: false)
            }
            if arguments.contains("--map-editor-fixture"), let coordinate = FixtureShopSearch.hangzhou.coordinate {
                let place = FixtureShopSearch.hangzhou
                try? store.addWish(place)
                mapJourney.zoom(to: coordinate, animated: false)
                mapJourney.selectedCafeID = place.id
            }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let photo = UIImage(contentsOfFile: documents.appendingPathComponent("cutout-test.jpg").path)
            if let value = arguments.first(where: { $0.hasPrefix("--stamp-count=") })?.split(separator: "=").last,
               let count = Int(value), (0...100).contains(count) {
                store.records = (0..<count).map { index in
                    DrinkRecord(date: Date(timeIntervalSince1970: Double(index) * 86400),
                                shop: "测试咖啡馆", name: "测试饮品")
                }
            }
            if arguments.contains("--preview-calendar-fixtures"), let photo,
               let png = try? Data(contentsOf: documents.appendingPathComponent("cutout-test.png")) {
                store.records = []
                for offset in 1...2 {
                    let record = DrinkRecord(date: Calendar.current.date(byAdding: .day, value: -offset, to: Date())!,
                                             shop: offset == 1 ? "Grid Coffee" : "MIND BALANCE", city: "上海市",
                                             name: "动画测试\(offset)", latitude: 31.22, longitude: 121.46)
                    try? store.add(record, photo: photo, stickerData: png)
                }
            }
            if arguments.contains("--preview-cutout-fixture"), let photo {
                let data = try? Data(contentsOf: documents.appendingPathComponent("cutout-test.jpg"))
                openEditor(photo: photo, date: data.flatMap { PhotoTimestamp.captureDate(in: $0) })
            }
            if arguments.contains("--preview-saved-cutout"), let photo,
               let png = try? Data(contentsOf: documents.appendingPathComponent("cutout-test.png")) {
                let record = DrinkRecord(shop: "测试店铺", name: "Cutout Fixture")
                if (try? store.add(record, photo: photo, stickerData: png)) != nil {
                    if !arguments.contains("--preview-home-photo") { editing = store.records.last }
                }
            }
        }
        if arguments.contains("--fold-audit") {
            if arguments.contains("--audit-week") { weekMode = true }
            if arguments.contains("--audit-source") { sourceMenuVisible = true }
            if arguments.contains("--audit-month") { monthVisible = true }
            if arguments.contains("--audit-stamp-theme") { screen = .stamps; stampRoute = .caffeTogether }
            if arguments.contains("--audit-wish") { screen = .map; mapJourney.searchPresented = true }
            if arguments.contains("--audit-record"), let record = store.records.first {
                editing = record; editImage = store.image(for: record)
            }
        }
        #endif
    }

    private func exportFoldAudit(_ layout: BrewLayout) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--fold-audit") else { return }
        func rect(_ frame: CGRect) -> [Double] { [frame.minX, frame.minY, frame.width, frame.height].map(Double.init) }
        let data: [String: Any] = ["timestamp": Date().timeIntervalSince1970,
            "width": layout.size.width, "height": layout.size.height,
            "hinge": String(describing: layout.hinge), "landscape": layout.landscape,
            "tabletop": layout.tabletop, "book": layout.book, "keyboardInset": layout.keyboardInset,
            "pageFrame": rect(nativeChrome.pageFrame), "addFrame": rect(addButtonFrame),
            "verticalNavigation": nativeChrome.vertical,
            "verticalTools": sidebarGeometry.vertical ?? nativeChrome.vertical,
            "toolAxis": sidebarGeometry.axisX,
            "utilityRegion": rect(layout.utilityRegion), "barGuide": rect(sidebarGeometry.frame),
            "reservations": sidebarGeometry.reservations.map(rect),
            "ready": !launchVisible && (editing != nil || (!nativeChrome.pageFrame.isEmpty && !addButtonFrame.isEmpty))]
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("fold-audit.json")
        if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: file, options: .atomic)
        }
        #endif
    }

    @ViewBuilder private var mainPage: some View {
        switch screen {
        case .home:
            calendarHome
        case .drinks:
            DrinksPage(month: $selectedMonth) { editing = $0; editImage = nil }
        case .cards:
            CardsPage(month: $selectedMonth)
        case .stamps:
            StampsPage(route: $stampRoute, filter: $stampCityFilter)
        case .map:
            mapPage
        case .settings:
            SettingsPage(navigation: settingsNavigation)
                .transition(.move(edge: .trailing))
        }
    }

    private var calendarHome: some View {
        HomePage(month: $selectedMonth, selectedDate: $selectedDate, weekMode: $weekMode,
                 onRecord: { editing = $0; editImage = nil }, onDrinks: {
                    monthDrag = 0
                    withAnimation(reduceMotion || systemReduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.9)) {
                        monthVisible = true
                    }
                 }, onCards: { openAlbum() }, onToggleMode: {
                     toggleCalendarMode(animation: reduceMotion || systemReduceMotion ? nil : .easeInOut(duration: 0.28))
                 })
    }
    private func monthLayout(_ layout: BrewLayout, topInset: CGFloat) -> BrewLayout {
        var result = layout
        result.nativeNavigation = true
        result.systemTopInset = topInset
        return result
    }

    private func closeMonth(_ layout: BrewLayout) {
        withAnimation(layout.animation) { monthVisible = false; monthDrag = 0 }
    }

    private func finishMonthDrag(distance: CGFloat, predicted: CGFloat, layout: BrewLayout) {
        if distance > 65 || (distance > 18 && predicted > 110) {
            closeMonth(layout)
        } else {
            withAnimation(layout.animation) { monthDrag = 0 }
        }
    }

    private func updateMonthDrag(_ distance: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { monthDrag = max(0, distance) }
    }

    private func monthDismissGesture(_ layout: BrewLayout) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                guard value.translation.height > abs(value.translation.width) else { return }
                updateMonthDrag(value.translation.height)
            }
            .onEnded { value in
                finishMonthDrag(distance: value.translation.height,
                                predicted: value.predictedEndTranslation.height, layout: layout)
            }
    }

    private var mapPage: some View {
        BrewMapPage(journey: mapJourney, onAdd: { place in
            var record = DrinkRecord(); record.selectShop(place)
            editImage = nil; editing = record
        }, onEdit: { record in editImage = nil; editing = record })
    }

    @available(iOS 26.0, *)
    private func nativeNavigation(_ layout: BrewLayout) -> some View {
        let tab: BrewScreen = screen == .stamps || screen == .map ? screen : .home
        return ZStack(alignment: .topLeading) {
            GeometryReader { geometry in
                if !nativeChrome.pageFrame.isEmpty {
                    let frame = screen == .map
                        ? CGRect(x: 0, y: 0, width: geometry.size.width, height: geometry.size.height)
                        : nativeChrome.pageFrame
                    let origin = geometry.frame(in: .global).origin
                    NativeTabPage(baseLayout: layout, chrome: nativeChrome,
                        page: AnyView(nativePage(tab)), onFolderFrame: { folderFrame = $0 })
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
                }
            }
            NativeCoffeeTabs(selection: tab, leftHanded: layout.leftHanded,
                onSelect: selectTab, onChrome: { nativeChrome = $0 })
                .padding(.bottom, nativeChrome.vertical ? 80 : 0)
        }
            .ignoresSafeArea(.container)
            .overlay {
                GeometryReader { geometry in
                    if !nativeChrome.barFrame.isEmpty {
                        let origin = geometry.frame(in: .global).origin
                        // System status-bar geometry and tab-bar orientation are
                        // independent during and after a fold transition.
                        let verticalTools = sidebarGeometry.vertical ?? nativeChrome.vertical
                        if verticalTools {
                            let axis = (sidebarGeometry.vertical == true ? sidebarGeometry.axisX : nativeChrome.columnX) - origin.x
                            navigationTools(vertical: true).frame(width: 54)
                                .fixedSize(horizontal: false, vertical: true)
                                .position(x: axis, y: layout.utilityCenterY(
                                    preferred: screen == .settings ? geometry.size.height * 0.5 : min(225, geometry.size.height * 0.34) + 51,
                                    height: screen == .home || screen == .map || screen == .stamps ? 102 : 46))
                        } else if screen == .settings {
                            navigationTools(vertical: true)
                                .position(x: layout.leftHanded ? 33 : geometry.size.width - 33,
                                          y: layout.utilityCenterY(preferred: geometry.size.height * 0.5, height: 46))
                        } else {
                            navigationTools(vertical: false).padding(.horizontal, 16)
                                .padding(.top, max(16, layout.utilityRegion.minY))
                        }
                        if nativeChrome.vertical {
                            addButtonAnchor(size: 48)
                                .position(x: nativeChrome.columnX - origin.x, y: geometry.size.height - 30)
                        } else {
                            addButtonAnchor(size: 54)
                                .position(x: layout.leftHanded ? 38 : geometry.size.width - 38,
                                          y: nativeChrome.barFrame.minY + 31 - origin.y)
                        }
                    }
                }
            }

    }

    @ViewBuilder private func nativePage(_ destination: BrewScreen) -> some View {
        switch destination {
        case .home:
            ZStack {
                calendarHome
                    .allowsHitTesting(screen != .settings)
                    .accessibilityHidden(screen == .settings)
                if screen == .drinks || screen == .cards { mainPage }
                // Prepare the settings root while home is idle. Entering it
                // then animates a retained page instead of building its tree.
                SettingsPage(navigation: settingsNavigation)
                    .offset(x: screen == .settings ? 0 : max(nativeChrome.pageFrame.maxX, nativeChrome.barFrame.maxX) + 16)
                    .allowsHitTesting(screen == .settings)
                    .accessibilityHidden(screen != .settings)
                    .zIndex(1)
            }
        case .stamps: StampsPage(route: $stampRoute, filter: $stampCityFilter)
        case .map: mapPage
        default: EmptyView()
        }
    }
    private func utilityRegion(in size: CGSize) -> CGRect {
        var frame = sidebarGeometry.frame
        if frame.isEmpty { return frame }
        let bottom = editing == nil && !albumVisible && !monthVisible && nativeChrome.vertical
            ? min(frame.maxY, nativeChrome.trackingFrame.minY - 12) : min(frame.maxY, size.height - keyboardInset - 8)
        frame.size.height = max(0, bottom - frame.minY)
        return frame
    }

    private var settingsCloseLabel: String {
        screen == .settings && !settingsNavigation.path.isEmpty ? "返回上一级" : "返回首页"
    }
    private func openSettings() {
        settingsNavigation.path = []
        let log = OSLog(subsystem: "com.xiuyuancai.brewwww", category: "Motion")
        let interval = OSSignpostID(log: log)
        os_signpost(.animationBegin, log: log, name: "SettingsEntrance", signpostID: interval)
        withAnimation(reduceMotion || systemReduceMotion ? nil : .easeOut(duration: 0.28), completionCriteria: .removed) {
            screen = .settings
        } completion: {
            os_signpost(.end, log: log, name: "SettingsEntrance", signpostID: interval)
        }
    }

    private func toggleCalendarMode(animation: Animation?) {
        let log = OSLog(subsystem: "com.xiuyuancai.brewwww", category: "Motion")
        let interval = OSSignpostID(log: log)
        os_signpost(.animationBegin, log: log, name: "CalendarMode", signpostID: interval)
        withAnimation(animation, completionCriteria: .removed) {
            weekMode.toggle()
        } completion: {
            os_signpost(.end, log: log, name: "CalendarMode", signpostID: interval)
        }
    }
    private func closeSettingsOrReturnHome() {
        if screen == .settings && settingsNavigation.pop() { return }
        screen = .home
    }

    private func selectTab(_ destination: BrewScreen) {
        guard screen != destination else { return }
        if destination == .stamps { stampRoute = .collection }
        screen = destination
    }

    private func playfulMugButton(size: CGFloat) -> some View {
        PlayfulMugButton(state: playfulMug, size: size, reduceMotion: reduceMotion || systemReduceMotion) {
            store.allStampsUnlocked.toggle()
        }
    }

    private func navigationTools(vertical: Bool) -> some View {
        let arrangement = vertical ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        let size: CGFloat = vertical ? 46 : 40
        return arrangement {
            if screen == .stamps { stampTools(vertical: vertical) }
            else if screen == .map { MapUtilityTools(journey: mapJourney, vertical: vertical) }
            else if screen == .home {
                BrewGlassButton(symbol: "gearshape", size: size, label: "设置", identifier: "nav.settings") { openSettings() }
                playfulMugButton(size: size)
            } else {
                BrewGlassButton(symbol: "xmark", size: size, label: settingsCloseLabel, identifier: "nav.home") { closeSettingsOrReturnHome() }
            }
        }
    }

    private func navigationRail(_ layout: BrewLayout) -> some View {
        VStack(spacing: layout.landscape ? 6 : 10) {
            if layout.landscape || layout.expanded {
                Spacer(minLength: 0)
            } else {
                Color.clear.frame(height: min(225, layout.size.height * 0.34))
            }
            if screen == .stamps {
                stampTools(vertical: true)
            } else if screen == .map {
                MapUtilityTools(journey: mapJourney, vertical: true)
            } else if screen == .home {
                BrewGlassButton(symbol: "gearshape", label: "设置", identifier: "nav.settings") { openSettings() }
                playfulMugButton(size: 46)
            } else {
                BrewGlassButton(symbol: "xmark", label: settingsCloseLabel, identifier: "nav.home") { closeSettingsOrReturnHome() }
                if screen == .stamps || screen == .map {
                    BrewGlassButton(symbol: "gearshape", label: "设置", identifier: "nav.settings") { openSettings() }
                }
            }
            Spacer(minLength: layout.landscape ? 6 : 18)
            VStack(spacing: 3) {
                railButton("takeoutbag.and.cup.and.straw", .home)
                railButton("seal", .stamps)
                railButton("map", .map)
            }
            .padding(4)
            .background(screen == .map ? BrewStyle.mapNavigation : screen == .cards ? BrewStyle.albumControl : BrewStyle.control, in: Capsule())
            .overlay { if colorScheme == .light { Capsule().stroke(BrewStyle.border, lineWidth: 1) } }
            addButtonAnchor(size: 48)
            if layout.expanded { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 7)
        .padding(.bottom, layout.landscape ? 8 : 24)
        .frame(width: 66)
        .frame(maxHeight: .infinity)
    }

    private func railButton(_ symbol: String, _ destination: BrewScreen) -> some View {
        Button {
            guard screen != destination else { return }
            if destination == .stamps { stampRoute = .collection }
            screen = destination
        } label: {
            Group {
                if destination == .home {
                    TakeawayCup().stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 16, height: 21)
                } else if destination == .stamps {
                    RubberStamp().stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 16, height: 22)
                } else {
                    Image(systemName: symbol).font(.system(size: 17, weight: .regular))
                }
            }
                .foregroundStyle((screen == destination || (screen == .drinks && destination == .home)) ? BrewStyle.gold : BrewStyle.icon)
                .frame(width: 45, height: 49)
                .contentShape(Rectangle())
                .background {
                    if screen == destination || (screen == .drinks && destination == .home) {
                        Capsule().fill(screen == .map ? BrewStyle.mapSelection : BrewStyle.selection)
                            .matchedGeometryEffect(id: "navigation", in: navigationSelection)
                    }
                }
        }
        .accessibilityLabel(destination == .home ? "日历" : destination == .stamps ? "印章册" : "地图")
        .accessibilityIdentifier(destination == .home ? "nav.calendar" : "nav.\(destination.rawValue)")
    }

    private var utilityButtons: some View {
        navigationTools(vertical: false)
    }

    private func stampTools(vertical: Bool) -> some View {
        let arrangement = vertical ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        return arrangement {
            if stampRoute == .collection {
                BrewGlassMenu(size: vertical ? 46 : 40, label: "筛选印章", identifier: "stamps.filter",
                    items: [BrewMenuItem(title: "所有印章", action: { stampCityFilter = nil })] +
                        store.cities.map { city in BrewMenuItem(title: city, action: { stampCityFilter = city }) })
            } else {
                BrewGlassButton(symbol: "chevron.left", size: vertical ? 46 : 40,
                                label: "返回上一级", identifier: "stamps.back") {
                    stampRoute = (stampRoute == .caffeTogether || stampRoute == .caffeExplore) ? .catalogue : .collection
                }
            }
            BrewGlassButton(symbol: "seal", size: vertical ? 46 : 40, prominent: stampRoute != .collection,
                            label: "印章图鉴", identifier: "stamps.catalogue") {
                stampRoute = stampRoute == .collection ? .catalogue : .collection
            }
        }
    }

    private func bottomNavigation(_ layout: BrewLayout) -> some View {
        HStack(spacing: 18) {
            if layout.leftHanded { addRecordButton }
            HStack(spacing: 8) {
                railButton("takeoutbag.and.cup.and.straw", .home)
                railButton("seal", .stamps)
                railButton("map", .map)
            }
            .padding(5).background(BrewStyle.control.opacity(0.88), in: Capsule())
            .overlay(Capsule().stroke(BrewStyle.border.opacity(0.5), lineWidth: 0.7))
            if !layout.leftHanded { addRecordButton }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("navigation.bottom")
    }

    private var addRecordButton: some View {
        addButtonAnchor(size: 54)
    }

    private func openAlbum() {
        guard !albumVisible else { return }
        albumTask?.cancel()
        albumProgress = 0
        albumVisible = true
        albumTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion || systemReduceMotion ? nil : .easeOut(duration: 0.36)) {
                albumProgress = 1
            }
        }
    }

    private func closeAlbum(layout: BrewLayout) {
        albumTask?.cancel()
        withAnimation(layout.reduceMotion ? nil : .easeInOut(duration: 0.36)) { albumProgress = 0 }
        albumTask = Task { @MainActor in
            if !layout.reduceMotion { try? await Task.sleep(for: .milliseconds(380)) }
            guard !Task.isCancelled else { return }
            albumVisible = false
        }
    }

    private func setSourceMenu(_ visible: Bool) {
        withAnimation(.easeOut(duration: reduceMotion || systemReduceMotion ? 0.12 : 0.18)) {
            sourceMenuVisible = visible
        }
    }

    @ViewBuilder private func sourceActionButton(size: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            NativeAddRecordButton(isCancel: sourceMenuVisible, reduceMotion: reduceMotion || systemReduceMotion) {
                setSourceMenu(!sourceMenuVisible)
            } onPressChanged: { pressing in
                guard screen == .home && !sourceMenuVisible else { return false }
                playfulMug.setPressed(pressing)
                return playfulMug.consumedHold
            }.frame(width: size, height: size)
        } else {
            BrewGlassButton(symbol: "plus", size: size, prominent: !sourceMenuVisible,
                label: sourceMenuVisible ? "取消" : "添加记录", identifier: "nav.add") {
                if screen != .home || sourceMenuVisible || !playfulMug.consumedHold {
                    setSourceMenu(!sourceMenuVisible)
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in playfulMug.setPressed(screen == .home && !sourceMenuVisible) }
                .onEnded { _ in playfulMug.setPressed(false) })
            .rotationEffect(.degrees(sourceMenuVisible ? 45 : 0))
        }
    }

    private func addButtonAnchor(size: CGFloat) -> some View {
        Color.clear.frame(width: size, height: size)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: AddButtonFrameKey.self, value: geometry.frame(in: .named("brewRoot")))
                }
            }
            .accessibilityHidden(true)
    }

    private func openEditor(photo: UIImage, date: Date? = nil) {
        editImage = photo
        editing = DrinkRecord(date: date ?? Date())
    }
}

private struct AddButtonFrameKey: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

/// The choices stay in the same hierarchy during their short transition, so
/// their lift/opacity and the page blur share one animation transaction.
private struct SourceChoiceOverlay: View {
    var visible: Bool
    var layout: BrewLayout
    var addButtonFrame: CGRect
    @Binding var selection: PhotosPickerItem?
    var onCamera: () -> Void
    var onCancel: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(220, geometry.size.width - 84)
            let width = min(520, availableWidth - 32)
            let height: CGFloat = layout.landscape ? 72 : 92
            let gap: CGFloat = layout.landscape ? 16 : 20
            let total = height * 2 + gap
            let bottom = min(geometry.size.height - 16, addButtonFrame.isEmpty ? geometry.size.height - 16 : addButtonFrame.maxY - 10)
            let x = (layout.leftHanded ? 84 : 0) + availableWidth / 2
            BrewStyle.ink.opacity(visible ? 0.30 : 0)
                .ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            VStack(spacing: gap) {
                Button(action: onCamera) { row("拍照", symbol: "camera", width: width, height: height) }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    .accessibilityIdentifier("source.camera")
                PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .current) {
                    row("从相册上传", symbol: "photo", width: width, height: height)
                }
                .accessibilityLabel("从相册选择").accessibilityIdentifier("source.library")
            }
            .buttonStyle(BrewPressStyle())
            .opacity(visible ? 1 : 0)
            .scaleEffect(layout.reduceMotion || visible ? 1 : 0.98, anchor: .bottom)
            .offset(y: layout.reduceMotion || visible ? 0 : 12)
            .position(x: x, y: max(total / 2 + 16, bottom - total / 2))
        }
        .allowsHitTesting(visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("source.overlay")
        .accessibilityAction(.escape, onCancel)
        .accessibilityHidden(!visible)
    }

    private func row(_ title: String, symbol: String, width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium))
                .foregroundStyle(BrewStyle.gold).frame(width: 44, height: 44)
                .background(BrewStyle.selection.opacity(0.55), in: Circle())
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(BrewStyle.text)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 21, weight: .regular)).foregroundStyle(BrewStyle.muted)
        }
        .padding(.leading, 24).padding(.trailing, 30)
        .frame(width: width, height: height)
        .background(BrewStyle.panel.opacity(0.30), in: RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(BrewStyle.border.opacity(0.6), lineWidth: 1.2))
        .contentShape(RoundedRectangle(cornerRadius: 25))
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?, Date?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?, Date?) -> Void
        init(completion: @escaping (UIImage?, Date?) -> Void) { self.completion = completion }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let metadata = info[.mediaMetadata] as? [String: Any] ?? [:]
            completion(info[.originalImage] as? UIImage, PhotoTimestamp.captureDate(metadata: metadata))
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil, nil) }
    }
}
