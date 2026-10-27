import SwiftUI
import PhotosUI
import UIKit

enum BrewScreen: String, CaseIterable {
    case home, drinks, cards, stamps, map, settings
}

struct ContentView: View {
    @EnvironmentObject private var store: BrewStore
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
    @State private var editing: DrinkRecord?
    @State private var editImage: UIImage?
    @State private var sourceSheet = false
    @State private var showCamera = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var mapSelection: String?
    @State private var stampRoute: StampRoute = .collection
    @State private var stampCityFilter: String?
    @State private var folderFrame = CGRect.zero
    @State private var albumVisible = false
    @State private var albumProgress: CGFloat = 0
    @State private var albumTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let layout = BrewLayout(size: geometry.size, hinge: effectiveHinge,
                                    leftHanded: handedness == "left",
                                    reduceMotion: reduceMotion || systemReduceMotion,
                                    keyboardInset: keyboardInset)
            ZStack {
                BrewBackground()
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
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .opacity))
                    } else {
                        Group {
                            if layout.bottomNavigation {
                                mainPage
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .overlay(alignment: .topLeading) { utilityButtons.padding(16) }
                                    .overlay(alignment: .bottom) { bottomNavigation(layout).padding(.bottom, 28).zIndex(10) }
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
                        .blur(radius: albumProgress * 12)
                        .allowsHitTesting(!albumVisible)
                        .accessibilityHidden(albumVisible)
                    }
                }
                .environment(\.brewLayout, layout)
                .environment(\.folderPhotosHidden, albumVisible)
                if albumVisible {
                    PhotoAlbumOverlay(month: $selectedMonth, folderFrame: folderFrame, progress: albumProgress,
                                      onClose: { closeAlbum(layout: layout) })
                        .environment(\.brewLayout, layout)
                        .environment(\.brewControlSurface, BrewStyle.albumControl)
                        .transition(.identity).zIndex(20)
                }
            }
            .animation(layout.animation, value: editing?.id)
            .animation(layout.animation, value: layout.leftHanded)
            .coordinateSpace(name: "brewRoot")
            .onPreferenceChange(FolderFrameKey.self) { frame in
                if !frame.isEmpty { folderFrame = frame }
            }
            .background(HingeObserver(state: $hinge).allowsHitTesting(false))
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
        .sheet(isPresented: $sourceSheet) { sourceChooser }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                if let image { openEditor(photo: image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        sourceSheet = false
                        openEditor(photo: image)
                        selectedPhoto = nil
                    }
                }
            }
        }
        .onChange(of: selectedMonth) { _, month in
            if albumVisible { selectedDate = month }
        }
        .onAppear(perform: configurePreview)
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
                openEditor(photo: photo)
            }
            if arguments.contains("--preview-saved-cutout"), let photo,
               let png = try? Data(contentsOf: documents.appendingPathComponent("cutout-test.png")) {
                let record = DrinkRecord(shop: "测试店铺", name: "Cutout Fixture")
                if (try? store.add(record, photo: photo, stickerData: png)) != nil {
                    if !arguments.contains("--preview-home-photo") { editing = store.records.last }
                }
            }
        }
        #endif
    }

    @ViewBuilder private var mainPage: some View {
        switch screen {
        case .home:
            HomePage(month: $selectedMonth, selectedDate: $selectedDate, weekMode: $weekMode,
                     onRecord: { editing = $0; editImage = nil },
                     onDrinks: { screen = .drinks }, onCards: { openAlbum() })
        case .drinks:
            DrinksPage(month: $selectedMonth) { editing = $0; editImage = nil }
        case .cards:
            CardsPage(month: $selectedMonth)
        case .stamps:
            StampsPage(route: $stampRoute, filter: $stampCityFilter)
        case .map:
            BrewMapPage(selectedShop: $mapSelection)
        case .settings:
            SettingsPage()
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
            } else if screen == .home {
                Button { screen = .settings } label: {
                    RoundIcon(symbol: "gearshape")
                }
                .accessibilityLabel("设置").accessibilityIdentifier("nav.settings")
                Button { withAnimation(layout.animation) { weekMode.toggle() } } label: {
                    Text(weekMode ? "W" : "M").font(.system(size: 22, weight: .black, design: .serif))
                        .foregroundStyle(BrewStyle.muted)
                        .frame(width: 46, height: 46)
                        .background(BrewStyle.control, in: Circle())
                }
                .accessibilityLabel(weekMode ? "切换月视图" : "切换周视图")
                .accessibilityIdentifier("calendar.mode")
            } else {
                Button { screen = .home; mapSelection = nil } label: {
                    RoundIcon(symbol: "xmark")
                }
                .accessibilityLabel("返回首页").accessibilityIdentifier("nav.home")
                if screen == .stamps || screen == .map {
                    Button { screen = .settings } label: {
                        RoundIcon(symbol: "gearshape")
                    }
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
            Button { sourceSheet = true } label: {
                RoundIcon(symbol: "plus", size: 48, accent: true)
            }
            .accessibilityLabel("添加记录").accessibilityIdentifier("nav.add")
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
                        .frame(width: 20, height: 26)
                } else if destination == .stamps {
                    RubberStamp().stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 20, height: 27)
                } else {
                    Image(systemName: symbol).font(.system(size: 21, weight: .regular))
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
        HStack(spacing: 12) {
            if screen == .stamps {
                stampTools(vertical: false)
            } else if screen == .home {
                Button { screen = .settings } label: { RoundIcon(symbol: "gearshape", size: 40) }
                    .accessibilityLabel("设置").accessibilityIdentifier("nav.settings")
                Button { withAnimation { weekMode.toggle() } } label: {
                    Text(weekMode ? "W" : "M").font(.system(size: 19, weight: .black, design: .serif))
                        .foregroundStyle(BrewStyle.icon).frame(width: 40, height: 40)
                        .background(BrewStyle.control, in: Circle())
                }.accessibilityLabel(weekMode ? "切换月视图" : "切换周视图").accessibilityIdentifier("calendar.mode")
            } else {
                Button { screen = .home } label: { RoundIcon(symbol: "xmark", size: 40) }
                    .accessibilityLabel("返回首页").accessibilityIdentifier("nav.home")
            }
        }
    }

    private func stampTools(vertical: Bool) -> some View {
        let arrangement = vertical ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
        return arrangement {
            if stampRoute == .collection {
                Menu {
                    Button("所有印章") { stampCityFilter = nil }
                    ForEach(store.cities, id: \.self) { city in
                        Button(city) { stampCityFilter = city }
                    }
                } label: { RoundIcon(symbol: "line.3.horizontal", size: vertical ? 46 : 40) }
                    .accessibilityLabel("筛选印章").accessibilityIdentifier("stamps.filter")
            } else {
                Button {
                    withAnimation { stampRoute = stampRoute == .caffeTogether ? .catalogue : .collection }
                } label: { RoundIcon(symbol: "chevron.left", size: vertical ? 46 : 40) }
                    .accessibilityLabel("返回上一级").accessibilityIdentifier("stamps.back")
            }
            Button {
                withAnimation { stampRoute = stampRoute == .collection ? .catalogue : .collection }
            } label: { RoundIcon(symbol: "seal", size: vertical ? 46 : 40, accent: stampRoute != .collection) }
                .accessibilityLabel("印章图鉴").accessibilityIdentifier("stamps.catalogue")
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
        Button { sourceSheet = true } label: { RoundIcon(symbol: "plus", size: 54, accent: true) }
            .accessibilityLabel("添加记录").accessibilityIdentifier("nav.add")
    }

    private func openAlbum() {
        guard !albumVisible else { return }
        albumTask?.cancel()
        albumProgress = 0
        albumVisible = true
        albumTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion || systemReduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.83)) {
                albumProgress = 1
            }
        }
    }

    private func closeAlbum(layout: BrewLayout) {
        albumTask?.cancel()
        withAnimation(layout.reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.88)) { albumProgress = 0 }
        albumTask = Task { @MainActor in
            if !layout.reduceMotion { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            albumVisible = false
        }
    }

    private var sourceChooser: some View {
        VStack(spacing: 18) {
            Capsule().fill(BrewStyle.muted).frame(width: 40, height: 5).padding(.top, 12)
            Text("添加记录").font(.title2.bold())
            Button {
                sourceSheet = false
                if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
            } label: {
                Label("拍照", systemImage: "camera").brewRow()
            }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("从相册选择", systemImage: "photo").brewRow()
            }
            Button("取消") { sourceSheet = false }
                .padding(.top, 8)
            Spacer()
        }
        .padding(20)
        .presentationDetents([.height(300)])
        .presentationBackground(BrewStyle.ink)
        .task { await SubjectCutoutService.shared.prepareIfNeeded() }
    }

    private func openEditor(photo: UIImage) {
        editImage = photo
        editing = DrinkRecord(date: Date())
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            completion(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
    }
}
