import SwiftUI
import UIKit

/// Uses UIKit's native Liquid Glass button, including its press interaction.
struct BrewGlassButton: View {
    var symbol: String? = nil
    var title: String? = nil
    var size: CGFloat = 46
    var customImage: UIImage? = nil
    var loading = false
    var prominent = false
    var label: String
    var identifier: String
    var action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                NativeGlassAction(symbol: symbol, title: title, label: label,
                                  identifier: identifier, customImage: customImage,
                                   loading: loading, prominent: prominent, action: action)
            } else {
                Button(action: action) {
                    Group {
                        if loading { ProgressView() }
                        else if let customImage { Image(uiImage: customImage).renderingMode(.template) }
                        else if let symbol { Image(systemName: symbol).font(.system(size: 18)) }
                        else { Text(title ?? "").font(.system(size: 17, weight: .black, design: .serif)) }
                    }
                    .foregroundStyle(BrewStyle.icon)
                    .frame(width: size, height: size)
                    .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel(label).accessibilityIdentifier(identifier)
            }
        }
        .frame(width: size, height: size)
    }

    static var cupImage: UIImage { NavigationTabImages.images[0] }
}

struct BrewMenuItem {
    var title: String
    var image: String? = nil
    var children: [BrewMenuItem] = []
    var action: () -> Void = {}
}

struct BrewGlassMenu: View {
    var size: CGFloat = 46
    var label: String
    var identifier: String
    var items: [BrewMenuItem]

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                NativeGlassAction(symbol: nil, title: nil, label: label, identifier: identifier,
                                  customImage: NavigationTabImages.filterImage, loading: false,
                                  prominent: false, menuItems: items, action: {})
            } else {
                Menu {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        if item.children.isEmpty { Button(item.title, action: item.action) }
                        else {
                            Section(item.title) {
                                ForEach(item.children.indices, id: \.self) { child in
                                    Button(item.children[child].title, action: item.children[child].action)
                                }
                            }
                        }
                    }
                } label: {
                    Image(uiImage: NavigationTabImages.filterImage).renderingMode(.template)
                        .foregroundStyle(BrewStyle.icon).frame(width: size, height: size)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(label).accessibilityIdentifier(identifier)
    }
}

@available(iOS 26.0, *)
private struct NativeGlassAction: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    var symbol: String?
    var title: String?
    var label: String
    var identifier: String
    var customImage: UIImage?
    var loading: Bool
    var prominent: Bool
    var menuItems: [BrewMenuItem]? = nil
    var action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.addTarget(context.coordinator, action: #selector(Coordinator.pressed), for: .touchUpInside)
        update(button, coordinator: context.coordinator)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        update(button, coordinator: context.coordinator)
    }
    struct VisualSignature: Equatable {
        var symbol: String?
        var title: String?
        var image: ObjectIdentifier?
        var loading: Bool
        var prominent: Bool
        var colorScheme: ColorScheme
    }

    private func update(_ button: UIButton, coordinator: Coordinator) {
        let visual = VisualSignature(symbol: symbol, title: title, image: customImage.map { ObjectIdentifier($0) },
                                     loading: loading, prominent: prominent, colorScheme: colorScheme)
        if coordinator.visual != visual {
            configureAppearance(button)
            coordinator.visual = visual
        }
        // Actions stay current even when only the enclosing page's position changes.
        if let menuItems { button.menu = UIMenu(children: menuItems.map(menuElement)) }
        else if button.menu != nil { button.menu = nil }
        if button.showsMenuAsPrimaryAction != (menuItems != nil) { button.showsMenuAsPrimaryAction = menuItems != nil }
        if button.isEnabled != isEnabled { button.isEnabled = isEnabled }
        if button.accessibilityLabel != label { button.accessibilityLabel = label }
        if button.accessibilityIdentifier != identifier { button.accessibilityIdentifier = identifier }
    }

    private func configureAppearance(_ button: UIButton) {
        var configuration = prominent ? UIButton.Configuration.prominentGlass() : UIButton.Configuration.glass()
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = UIColor(prominent ? BrewStyle.photoInk : BrewStyle.icon)
        if prominent { configuration.baseBackgroundColor = UIColor(BrewStyle.gold) }
        configuration.image = customImage ?? symbol.flatMap { UIImage(systemName: $0) }
        configuration.showsActivityIndicator = loading
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        configuration.title = title
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attributes = incoming
            let font = UIFont.systemFont(ofSize: 17, weight: .black)
            attributes.font = UIFont(descriptor: font.fontDescriptor.withDesign(.serif) ?? font.fontDescriptor, size: 17)
            return attributes
        }
        button.configuration = configuration
    }
    private func menuElement(_ item: BrewMenuItem) -> UIMenuElement {
        if !item.children.isEmpty {
            return UIMenu(title: item.title, options: .displayInline, children: item.children.map(menuElement))
        }
        return UIAction(title: item.title, image: item.image.flatMap { UIImage(systemName: $0) }) { _ in item.action() }
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        var visual: VisualSignature?
        init(action: @escaping () -> Void) { self.action = action }
        @objc func pressed() { action() }
    }
}

struct NativeTabChrome: Equatable {
    var vertical = false
    var columnX: CGFloat = 0
    var barFrame = CGRect.zero
    var topSafeArea: CGFloat = 0
    var pageFrame = CGRect.zero
    var trackingFrame = CGRect.zero
}

/// The actual system tab bar owns its glass, tracking lens, labels and gestures.
/// The separate add action is placed by the surrounding SwiftUI layout.
@available(iOS 26.0, *)
struct NativeCoffeeTabs: UIViewControllerRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    var selection: BrewScreen
    var leftHanded: Bool
    var onSelect: (BrewScreen) -> Void
    var onChrome: (NativeTabChrome) -> Void
    private static let destinations: [BrewScreen] = [.home, .stamps, .map]

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> NativeTabHostController {
        let container = NativeTabHostController()
        let controller = container.tabs
        controller.delegate = context.coordinator
        controller.mode = .tabBar
        controller.tabBarMinimizeBehavior = .never
        controller.viewControllers = Self.destinations.indices.map { index in
            let page = UIViewController()
            page.view.backgroundColor = .clear
            let item = UITabBarItem(title: ["日历", "印章", "地图"][index], image: NavigationTabImages.images[index], tag: index)
            item.accessibilityIdentifier = ["nav.calendar", "nav.stamps", "nav.map"][index]
            page.tabBarItem = item
            return page
        }
        controller.customizableViewControllers = []
        controller.tabBar.accessibilityIdentifier = "navigation.systemTabBar"
        controller.leftHanded = leftHanded
        controller.selectedIndex = Self.destinations.firstIndex(of: selection) ?? 0
        controller.tabBar.tintColor = UIColor(BrewStyle.gold)
        controller.tabBar.unselectedItemTintColor = UIColor(BrewStyle.icon)
        context.coordinator.colorScheme = colorScheme
        controller.onChrome = { [weak container, weak coordinator = context.coordinator] chrome in
            if let trackingView = container?.trackingView {
                trackingView.trackingFrame = trackingView.convert(chrome.trackingFrame, from: trackingView.window)
            }
            coordinator?.parent.onChrome(chrome)
        }
        return container
    }
    func updateUIViewController(_ container: NativeTabHostController, context: Context) {
        context.coordinator.parent = self
        let controller = container.tabs
        let handednessChanged = controller.leftHanded != leftHanded
        if handednessChanged { controller.leftHanded = leftHanded }
        let index = Self.destinations.firstIndex(of: selection) ?? 0
        if controller.selectedIndex != index { controller.selectedIndex = index }
        if context.coordinator.colorScheme != colorScheme {
            controller.tabBar.tintColor = UIColor(BrewStyle.gold)
            controller.tabBar.unselectedItemTintColor = UIColor(BrewStyle.icon)
            context.coordinator.colorScheme = colorScheme
        }
        // Content animation updates must not force the system tab bar to relayout.
        // UIKit already handles size, safe-area and selected-controller changes.
        if handednessChanged { container.view.setNeedsLayout() }
    }
    static func dismantleUIViewController(_ container: NativeTabHostController, coordinator: Coordinator) {
        // A geometry delivery queued before a fold must not replace the new
        // controller's measurements after SwiftUI retires this instance.
        container.tabs.onChrome = nil
        container.tabs.delegate = nil
    }
    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var parent: NativeCoffeeTabs
        var colorScheme: ColorScheme?
        init(parent: NativeCoffeeTabs) { self.parent = parent }
        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            guard let index = tabBarController.viewControllers?.firstIndex(of: viewController) else { return }
            // Commit only after UIKit finishes selecting. Publishing from
            // shouldSelect can write selectedIndex back during slide tracking.
            parent.onSelect(NativeCoffeeTabs.destinations[index])
        }
    }
}

@available(iOS 26.0, *)
final class CoffeeTabController: UITabBarController {
    var onChrome: ((NativeTabChrome) -> Void)?
    var leftHanded = false
    private var lastChrome = NativeTabChrome()
    private var applyingLayout = false
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !applyingLayout else { return }
        applyingLayout = true; defer { applyingLayout = false }
        let vertical = tabBar.bounds.height > tabBar.bounds.width
        // UIKit owns the bar's frame, including its interactive glass layout.
        // Reserve horizontal add-button space in the host, never by moving the bar.
        // The system rail uses the same 48 pt edge axis as the status cluster.
        // Its 132 pt bar rectangle includes an asymmetric content-side gutter;
        // UIBarItem accessibilityFrame can also be zero or track the held lens.
        // Neither is a stable center for the separate utility buttons.
        let columnX = vertical
            ? (tabBar.frame.midX < view.bounds.midX ? tabBar.frame.minX + 48 : tabBar.frame.maxX - 48)
            : tabBar.frame.midX
        let barInWindow = tabBar.convert(tabBar.bounds, to: view.window)
        let safeFrame = selectedViewController.map {
            $0.view.convert($0.view.safeAreaLayoutGuide.layoutFrame, to: view.window)
        } ?? .zero
        let pageBottom = vertical ? (view.window?.bounds.height ?? view.bounds.height) - (view.window?.safeAreaInsets.bottom ?? 0)
            : safeFrame.maxY
        let hostFrame = parent.map { $0.view.convert($0.view.bounds, to: view.window) } ?? safeFrame
        let pageFrame = CGRect(x: vertical ? safeFrame.minX : hostFrame.minX, y: 0,
                               width: vertical ? safeFrame.width : hostFrame.width, height: pageBottom)
        let windowColumnX = view.convert(CGPoint(x: columnX, y: 0), to: view.window).x
        let trackingFrame = vertical
            ? CGRect(x: windowColumnX - 34, y: view.bounds.height - (view.window?.safeAreaInsets.bottom ?? 0) - 156,
                     width: 68, height: 174)
            : barInWindow.insetBy(dx: -4, dy: -6)
        let chrome = NativeTabChrome(vertical: vertical, columnX: windowColumnX,
                                     barFrame: barInWindow, topSafeArea: view.window?.safeAreaInsets.top ?? 0,
                                     pageFrame: pageFrame, trackingFrame: trackingFrame)
        if chrome != lastChrome {
            if chrome.vertical != lastChrome.vertical { parent?.view.setNeedsLayout() }
            lastChrome = chrome
            DispatchQueue.main.async { [weak self] in self?.onChrome?(chrome) }
        }
    }
}

/// Only the actual system navigation region intercepts touches. Page content
/// remains in the main SwiftUI hierarchy with its full window-sized viewport.
@available(iOS 26.0, *)
final class NativeTabTrackingView: UIView {
    var trackingFrame = CGRect.zero
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard trackingFrame.contains(point) else { return nil }
        // The selected lens and long-press tracking surfaces are not always
        // UIControls or accessibility buttons. UIKit must receive the entire
        // capsule; controls outside this bounded region still pass through.
        return super.hitTest(point, with: event)
    }
}

@available(iOS 26.0, *)
final class NativeTabHostController: UIViewController {
    let tabs = CoffeeTabController()
    let trackingView = NativeTabTrackingView()
    private var activationObserver: NSObjectProtocol?
    override func loadView() { view = trackingView }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(tabs)
        view.addSubview(tabs.view)
        tabs.didMove(toParent: self)
        activationObserver = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let scene = notification.object as? UIWindowScene,
                  scene === self.view.window?.windowScene else { return }
            self.refreshWindowLayout()
        }
        if #available(iOS 27.1, *) {
            registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) { (controller: NativeTabHostController, _: UITraitCollection) in
                controller.refreshWindowLayout()
            }
        }
    }
    deinit {
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        refreshWindowLayout()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshWindowLayout()
    }
    private func refreshWindowLayout() {
        view.setNeedsLayout()
        tabs.view.setNeedsLayout()
        if #available(iOS 27.1, *) {
            setNeedsUpdateOfVerticalBarConfiguration()
            tabs.setNeedsUpdateOfVerticalBarConfiguration()
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let window = view.window else { return }
        // Never use the tab bar's previous frame to size its parent. Cropping
        // the parent by 72 pt after an unfold removes the system sidebar from
        // the child's region, keeping the bar horizontal even after refolding.
        let frame = Self.tabFrame(in: view.bounds, hasSystemSidebar: window.safeAreaInsets.right > 40, leftHanded: tabs.leftHanded)
        if tabs.view.frame != frame { tabs.view.frame = frame }
    }

    static func tabFrame(in bounds: CGRect, hasSystemSidebar: Bool, leftHanded: Bool) -> CGRect {
        guard !hasSystemSidebar else { return bounds }
        var frame = bounds
        frame.origin.x += leftHanded ? 72 : 0
        frame.size.width = max(200, frame.width - 72)
        return frame
    }
}

@MainActor private enum NavigationTabImages {
    static let filterImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 26, height: 30)).image { context in
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4, y: 6)); path.addLine(to: CGPoint(x: 22, y: 6))
        path.addLine(to: CGPoint(x: 15, y: 14)); path.addLine(to: CGPoint(x: 15, y: 22))
        path.addLine(to: CGPoint(x: 11, y: 24)); path.addLine(to: CGPoint(x: 11, y: 14)); path.closeSubpath()
        UIColor.black.setStroke()
        context.cgContext.addPath(path); context.cgContext.setLineWidth(1.5)
        context.cgContext.setLineCap(.round); context.cgContext.setLineJoin(.round); context.cgContext.strokePath()
    }.withRenderingMode(.alwaysTemplate)
    static let images: [UIImage] = [image(TakeawayCup()), image(RubberStamp()),
                                    mapImage()]
    private static func mapImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 26, height: 30)).image { _ in
            UIImage(systemName: "map")?.draw(in: CGRect(x: 4, y: 5, width: 18, height: 20))
        }.withRenderingMode(.alwaysTemplate)
    }
    private static func image<S: Shape>(_ shape: S) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 26, height: 30)).image { context in
            UIColor.black.setStroke()
            let path = shape.path(in: CGRect(x: 4, y: 4, width: 18, height: 22)).cgPath
            let bounds = path.boundingBoxOfPath
            context.cgContext.translateBy(x: 13 - bounds.midX, y: 15 - bounds.midY)
            context.cgContext.addPath(path)
            context.cgContext.setLineWidth(1.5); context.cgContext.setLineCap(.round); context.cgContext.setLineJoin(.round)
            context.cgContext.strokePath()
        }.withRenderingMode(.alwaysTemplate)
    }
}

struct NativeTabPage: View {
    var baseLayout: BrewLayout
    var chrome: NativeTabChrome
    var page: AnyView
    var onFolderFrame: (CGRect) -> Void
    var body: some View {
        GeometryReader { geometry in
            let layout = contentLayout(geometry.size)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.brewLayout, layout)
        }
        .ignoresSafeArea(.container, edges: .top)
        .coordinateSpace(name: "brewRoot")
        .onPreferenceChange(FolderFrameKey.self) { frame in if !frame.isEmpty { onFolderFrame(frame) } }
    }
    private func contentLayout(_ size: CGSize) -> BrewLayout {
        var result = baseLayout; result.windowSize = baseLayout.size; result.size = size; result.nativeNavigation = true
        result.systemTopInset = chrome.topSafeArea
        return result
    }
}


@available(iOS 26.0, *)
struct NativeAddRecordButton: UIViewRepresentable {
    var isCancel = false
    var reduceMotion = false
    var action: () -> Void
    var onPressChanged: (Bool) -> Bool = { _ in false }
    func makeCoordinator() -> Coordinator { Coordinator(action: action, onPressChanged: onPressChanged) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        configure(button)
        button.addTarget(context.coordinator, action: #selector(Coordinator.began), for: .touchDown)
        button.addTarget(context.coordinator, action: #selector(Coordinator.cancelled), for: [.touchUpOutside, .touchCancel, .touchDragExit])
        button.addTarget(context.coordinator, action: #selector(Coordinator.pressed), for: .touchUpInside)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.action = action
        context.coordinator.onPressChanged = onPressChanged
        let changed = button.accessibilityLabel != (isCancel ? "取消" : "添加记录")
        if changed && button.window != nil && !reduceMotion {
            UIView.transition(with: button, duration: 0.18,
                              options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState]) {
                configure(button)
                button.layoutIfNeeded()
            }
        } else {
            configure(button)
        }
    }
    private func configure(_ button: UIButton) {
        var configuration = isCancel ? UIButton.Configuration.glass() : UIButton.Configuration.prominentGlass()
        configuration.image = UIImage(systemName: isCancel ? "xmark" : "plus")
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        configuration.contentInsets = .zero
        if !isCancel { configuration.baseBackgroundColor = UIColor(BrewStyle.gold) }
        configuration.baseForegroundColor = UIColor(isCancel ? BrewStyle.icon : BrewStyle.photoInk)
        configuration.cornerStyle = .capsule
        button.configuration = configuration
        button.accessibilityLabel = isCancel ? "取消" : "添加记录"
        button.accessibilityIdentifier = "nav.add"
    }
    final class Coordinator: NSObject {
        var action: () -> Void
        var onPressChanged: (Bool) -> Bool
        private var consumedPress = false
        init(action: @escaping () -> Void, onPressChanged: @escaping (Bool) -> Bool) {
            self.action = action
            self.onPressChanged = onPressChanged
        }
        @objc func began() {
            // Latch ownership at touch-down: reaching full during this same
            // press must not suddenly open the source picker on release.
            consumedPress = onPressChanged(true)
        }
        @objc func cancelled() {
            consumedPress = onPressChanged(false) || consumedPress
        }
        @objc func pressed() {
            consumedPress = onPressChanged(false) || consumedPress
            if !consumedPress { action() }
        }
    }
}

/// The animation clock belongs to the toy so filling never redraws the calendar.
@MainActor
final class PlayfulMugState: ObservableObject {
    @Published private(set) var fill: CGFloat = 0
    @Published private(set) var charging = false
    @Published private(set) var burst = 0
    private(set) var consumedHold = false
    private var pressed = false
    private var motion: Task<Void, Never>?
    private var tapCount = 0
    private var lastTap: TimeInterval = 0
    // Separate player so calendar landing feedback cannot interrupt the pour.
    private let risingFeedback: any BrewContinuousHaptics
    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "haptics") == nil || UserDefaults.standard.bool(forKey: "haptics")
    }

    init(risingFeedback: (any BrewContinuousHaptics)? = nil) {
        self.risingFeedback = risingFeedback ?? BrewHaptics()
    }

    func tap() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        tapCount = now - lastTap <= 0.8 ? tapCount + 1 : 1
        lastTap = now
        guard tapCount == 10 else { return false }
        tapCount = 0
        return true
    }

    func setPressed(_ value: Bool) {
        guard value != pressed else { return }
        pressed = value
        motion?.cancel()
        risingFeedback.stopContinuous()
        if value {
            consumedHold = false
            // A full cup releases the add button back to its normal action.
            guard fill < 1 else { return }
            let needsDelay = fill == 0
            if !needsDelay {
                consumedHold = true
                charging = true
            }
            if hapticsEnabled { risingFeedback.prepare() }
            motion = Task { @MainActor [weak self] in
                if needsDelay { try? await Task.sleep(for: .milliseconds(300)) }
                guard !Task.isCancelled, let self else { return }
                self.consumedHold = true
                self.charging = true
                guard self.fill < 1 else { return }
                let start = ProcessInfo.processInfo.systemUptime
                let initial = self.fill
                if self.hapticsEnabled {
                    self.risingFeedback.startContinuous(duration: Double(1 - initial) * 1.5)
                }
                while !Task.isCancelled {
                    let elapsed = ProcessInfo.processInfo.systemUptime - start
                    self.fill = min(1, initial + CGFloat(elapsed / 1.5))
                    if self.fill >= 1 {
                        self.burst += 1
                        self.risingFeedback.stopContinuous()
                        if self.hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                        break
                    }
                    if !self.hapticsEnabled { self.risingFeedback.stopContinuous() }
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
        } else {
            charging = false
            guard fill > 0, fill < 1 else { return }
            let initial = fill
            motion = Task { @MainActor [weak self] in
                let start = ProcessInfo.processInfo.systemUptime
                while !Task.isCancelled {
                    guard let self else { return }
                    let elapsed = ProcessInfo.processInfo.systemUptime - start
                    self.fill = max(0, initial - CGFloat(elapsed / 1.35))
                    if self.fill == 0 { break }
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
        }
    }

    func cancel() {
        setPressed(false)
        risingFeedback.stopContinuous()
        tapCount = 0
    }
}

struct PlayfulMugButton: View {
    @ObservedObject var state: PlayfulMugState
    var size: CGFloat = 46
    var reduceMotion = false
    var onSecret: () -> Void
    @State private var sparkleStart: Date?
    @State private var fullDate: Date?

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                mugButton.glassEffect(.regular.interactive(), in: Circle())
            } else {
                mugButton.background(.ultraThinMaterial, in: Circle())
            }
        }
        .scaleEffect(state.charging && !reduceMotion ? 1.08 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.65), value: state.charging)
        .onChange(of: state.fill, initial: true) { _, fill in
            fullDate = fill >= 1 ? Date() : nil
        }
        .task(id: state.burst) {
            guard state.burst > 0 else { return }
            sparkleStart = Date()
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            sparkleStart = nil
        }
    }

    private var mugButton: some View {
        Button {
            if state.tap() { onSecret() }
        } label: {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: (!state.charging || state.fill >= 1) && sparkleStart == nil)) { timeline in
                Canvas { context, _ in
                    context.translateBy(x: 16, y: 16)
                    let canvas = CGSize(width: size, height: size)
                    drawMug(context: &context, size: canvas, time: timeline.date.timeIntervalSinceReferenceDate)
                    if let sparkleStart {
                        let elapsed = timeline.date.timeIntervalSince(sparkleStart)
                        if elapsed < 0.65 { drawSparkles(context: &context, size: canvas, progress: elapsed / 0.65) }
                    }
                }
                .frame(width: size + 32, height: size + 32)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("马克杯")
        .accessibilityIdentifier("home.playfulMug")
        .accessibilityValue("\(Int(state.fill * 100))%")
    }

    private func drawMug(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let unit = size.width / 46
        context.scaleBy(x: unit, y: unit)
        context.translateBy(x: 23, y: 23)
        context.rotate(by: .degrees(-16))
        context.translateBy(x: -23, y: -23)
        let ink = BrewStyle.icon
        let stroke = StrokeStyle(lineWidth: 1.45, lineCap: .round, lineJoin: .round)

        // A round ceramic cup, viewed from above: oval rim, curved belly, loop handle.
        var handle = Path()
        handle.move(to: CGPoint(x: 32, y: 20))
        handle.addCurve(to: CGPoint(x: 30, y: 30), control1: CGPoint(x: 43, y: 16), control2: CGPoint(x: 43, y: 33))
        context.stroke(handle, with: .color(ink), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
        var body = Path()
        body.move(to: CGPoint(x: 9.5, y: 19))
        body.addCurve(to: CGPoint(x: 14, y: 33), control1: CGPoint(x: 10, y: 25), control2: CGPoint(x: 10.7, y: 30.5))
        body.addCurve(to: CGPoint(x: 28, y: 33), control1: CGPoint(x: 17.5, y: 35.8), control2: CGPoint(x: 24.5, y: 35.8))
        body.addCurve(to: CGPoint(x: 32.5, y: 19), control1: CGPoint(x: 31.3, y: 30.5), control2: CGPoint(x: 32, y: 25))
        context.fill(body, with: .linearGradient(Gradient(colors: [ink.opacity(0.18), ink.opacity(0.06)]),
            startPoint: CGPoint(x: 13, y: 23), endPoint: CGPoint(x: 30, y: 33)))
        context.stroke(body, with: .color(ink), style: stroke)

        let opening = Path(ellipseIn: CGRect(x: 9.5, y: 11.5, width: 23, height: 15))
        context.fill(opening, with: .color(BrewStyle.ink.opacity(0.35)))
        var surface = context
        surface.clip(to: Path(ellipseIn: CGRect(x: 11, y: 12.8, width: 20, height: 12.4)))
        if state.fill > 0 {
            let bob = state.charging && state.fill < 1 && !reduceMotion ? sin(time * 5) * 0.35 : 0
            let rise = (1 - state.fill) * 11 + bob
            surface.translateBy(x: 0, y: rise)
            let coffee = Path(ellipseIn: CGRect(x: 11, y: 12.8, width: 20, height: 12.4))
            surface.fill(coffee, with: .linearGradient(Gradient(colors: [BrewStyle.gold, Color(red: 0.63, green: 0.39, blue: 0.18)]),
                startPoint: CGPoint(x: 18, y: 13), endPoint: CGPoint(x: 24, y: 27)))
            surface.stroke(Path(ellipseIn: CGRect(x: 12.2, y: 13.7, width: 17.6, height: 10.5)),
                with: .color(Color.white.opacity(0.23)), lineWidth: 0.55)
            let reveal = fullDate.map { min(1, max(0, (time - $0.timeIntervalSinceReferenceDate) / 0.45)) } ?? 0
            drawLatte(context: &surface, reveal: reduceMotion && state.fill >= 1 ? 1 : CGFloat(reveal))
        }
        context.stroke(opening, with: .color(ink), style: stroke)
        var shine = Path()
        shine.move(to: CGPoint(x: 12.5, y: 27))
        shine.addQuadCurve(to: CGPoint(x: 15, y: 31.5), control: CGPoint(x: 13, y: 30))
        context.stroke(shine, with: .color(ink.opacity(0.3)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
    }

    private func drawLatte(context: inout GraphicsContext, reveal: CGFloat) {
        var foam = context
        foam.opacity = Double(reveal)
        foam.translateBy(x: 21, y: 19.3)
        foam.scaleBy(x: 0.8 + 0.2 * reveal, y: (0.8 + 0.2 * reveal) * 0.7)
        let cream = Color(red: 1, green: 0.96, blue: 0.85)
        // Three poured hearts and two sweeping leaves form a tiny tulip latte.
        for index in 0..<3 {
            let width = CGFloat(3.2 + Double(index) * 1.6)
            let y = CGFloat(-5.4 + Double(index) * 2.7)
            var heart = Path()
            heart.move(to: CGPoint(x: 0, y: y + 3))
            heart.addCurve(to: CGPoint(x: -width / 2, y: y), control1: CGPoint(x: -0.9, y: y + 1.8), control2: CGPoint(x: -width * 0.7, y: y + 1.4))
            heart.addCurve(to: CGPoint(x: 0, y: y + 0.3), control1: CGPoint(x: -width * 0.45, y: y - 1.7), control2: CGPoint(x: -0.5, y: y - 1.3))
            heart.addCurve(to: CGPoint(x: width / 2, y: y), control1: CGPoint(x: 0.5, y: y - 1.3), control2: CGPoint(x: width * 0.45, y: y - 1.7))
            heart.addCurve(to: CGPoint(x: 0, y: y + 3), control1: CGPoint(x: width * 0.7, y: y + 1.4), control2: CGPoint(x: 0.9, y: y + 1.8))
            foam.fill(heart, with: .color(cream))
        }
        for side: CGFloat in [-1, 1] {
            var leaf = Path()
            leaf.move(to: CGPoint(x: 0, y: 5.3))
            leaf.addCurve(to: CGPoint(x: side * 7.2, y: -0.4), control1: CGPoint(x: side * 5.6, y: 5.5), control2: CGPoint(x: side * 8, y: 2.4))
            leaf.addCurve(to: CGPoint(x: 0, y: 5.3), control1: CGPoint(x: side * 5, y: 2.4), control2: CGPoint(x: side * 4, y: 3.4))
            foam.fill(leaf, with: .color(cream.opacity(0.9)))
        }
    }

    private func drawSparkles(context: inout GraphicsContext, size: CGSize, progress: Double) {
        // Uneven four-point glints, each with its own angle, size and travel.
        for index in 0..<6 {
            let angle = Double(index) * 1.07 - 1.8
            let travel = reduceMotion ? 0 : progress * (9 + Double(index % 3) * 3)
            let radius = size.width * 0.4 + travel
            let center = CGPoint(x: size.width / 2 + cos(angle) * radius,
                                 y: size.height / 2 + sin(angle) * radius)
            let length = CGFloat(2.6 + Double(index % 3)) * CGFloat(sin(.pi * progress))
            var star = Path()
            star.move(to: CGPoint(x: 0, y: -length * 1.4))
            star.addQuadCurve(to: CGPoint(x: length * 0.8, y: 0), control: CGPoint(x: length * 0.18, y: -length * 0.15))
            star.addQuadCurve(to: CGPoint(x: 0, y: length), control: CGPoint(x: length * 0.12, y: length * 0.2))
            star.addQuadCurve(to: CGPoint(x: -length, y: 0), control: CGPoint(x: -length * 0.2, y: length * 0.1))
            star.addQuadCurve(to: CGPoint(x: 0, y: -length * 1.4), control: CGPoint(x: -length * 0.16, y: -length * 0.2))
            var glint = context
            glint.translateBy(x: center.x, y: center.y)
            glint.rotate(by: .radians(angle * 0.4))
            glint.opacity = 1 - progress
            glint.fill(star, with: .color(BrewStyle.gold))
        }
    }
}
