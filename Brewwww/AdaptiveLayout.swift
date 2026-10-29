import SwiftUI
import UIKit

enum BrewHingeState: Equatable {
    case unavailable, closed, partiallyOpen, fullyOpen
}

struct BrewLayout: Equatable {
    var size: CGSize = CGSize(width: 390, height: 760)
    var hinge: BrewHingeState = .unavailable
    var leftHanded = false
    var reduceMotion = false
    var keyboardInset: CGFloat = 0
    var nativeNavigation = false
    var systemTopInset: CGFloat = 0
    var windowSize: CGSize = .zero
    var utilityRegion: CGRect = .zero
    var sidebarAxis: CGFloat = 0
    var addButtonFrame: CGRect = .zero
    var controlRailInset: CGFloat = 0

    func utilityCenterY(preferred: CGFloat, height: CGFloat, within bounds: CGRect? = nil) -> CGFloat {
        guard !utilityRegion.isEmpty else { return preferred }
        let region = bounds.map { utilityRegion.intersection($0) } ?? utilityRegion
        guard !region.isNull && region.height >= height else { return max(preferred, utilityRegion.minY + height / 2) }
        return min(max(preferred, region.minY + height / 2), region.maxY - height / 2)
    }

    var landscape: Bool { size.width > size.height * 1.12 }
    var allowsLandscape: Bool {
        switch hinge {
        case .closed: false
        case .partiallyOpen, .fullyOpen: true
        case .unavailable: min(size.width, size.height) >= 600
        }
    }
    var expanded: Bool { size.width >= 600 }
    var bottomNavigation: Bool { expanded && !landscape }
    var tabletop: Bool { hinge == .partiallyOpen && landscape }
    var book: Bool { hinge == .partiallyOpen && !landscape && expanded }
    var twoColumns: Bool { expanded || landscape }
    var contentRailInset: CGFloat { nativeNavigation ? 0 : 66 }
    var pageWidth: CGFloat { max(0, size.width - contentRailInset) }
    var bookLeadingWidth: CGFloat { max(180, size.width / 2 - (leftHanded ? contentRailInset : 0) - 26) }
    var animation: Animation? { reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88) }
    var titleTop: CGFloat {
        if nativeNavigation && systemTopInset > 0 { return systemTopInset + 12 }
        return landscape ? 8 : min(36, size.height * 0.045)
    }
    var pageInsets: EdgeInsets { EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 10) }
}

private struct BrewLayoutKey: EnvironmentKey {
    static let defaultValue = BrewLayout()
}

extension EnvironmentValues {
    var brewLayout: BrewLayout {
        get { self[BrewLayoutKey.self] }
        set { self[BrewLayoutKey.self] = newValue }
    }
}

struct BrewPagePadding: ViewModifier {
    @Environment(\.brewLayout) private var layout
    func body(content: Content) -> some View {
        content.padding(layout.pageInsets)
    }
}

extension View {
    func brewPagePadding() -> some View { modifier(BrewPagePadding()) }
}

/// The host view receives public UIKit hinge updates from its own window hierarchy.
/// Geometry, rather than a device model string, determines the usable arrangement.
struct HingeObserver: UIViewRepresentable {
    @Binding var state: BrewHingeState

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { _, update in
                let next: BrewHingeState
                switch update.hinge?.status {
                case .closed: next = .closed
                case .partiallyOpen: next = .partiallyOpen
                case .fullyOpen: next = .fullyOpen
                default: next = .unavailable
                }
                DispatchQueue.main.async { if state != next { state = next } }
            }
            view.addInteraction(interaction)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

@MainActor
final class BrewOrientationPolicy {
    static let shared = BrewOrientationPolicy()
    private let masks = NSMapTable<UIWindowScene, NSNumber>.weakToStrongObjects()

    func mask(for scene: UIWindowScene?) -> UIInterfaceOrientationMask {
        if let scene, let raw = masks.object(forKey: scene) {
            return UIInterfaceOrientationMask(rawValue: raw.uintValue)
        }
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
    }

    func apply(allowLandscape: Bool, to window: UIWindow, force: Bool = false) {
        guard let scene = window.windowScene else { return }
        let next: UIInterfaceOrientationMask = allowLandscape ? .allButUpsideDown : .portrait
        guard force || masks.object(forKey: scene)?.uintValue != next.rawValue else { return }
        masks.setObject(NSNumber(value: next.rawValue), forKey: scene)
        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: next))
    }
}

struct BrewOrientationObserver: UIViewRepresentable {
    var allowLandscape: Bool

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
        view.allowLandscape = allowLandscape
        view.apply()
    }

    final class Probe: UIView {
        var allowLandscape = false
        private var activationObserver: NSObjectProtocol?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
            activationObserver = nil
            if window != nil {
                activationObserver = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] notification in
                    guard let self, let scene = notification.object as? UIWindowScene,
                          scene === self.window?.windowScene else { return }
                    self.apply(force: true)
                }
            }
            apply()
        }
        deinit {
            if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        }
        func apply(force: Bool = false) {
            guard let window else { return }
            // Apply after SwiftUI finishes the current layout update.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                BrewOrientationPolicy.shared.apply(allowLandscape: self.allowLandscape, to: window, force: force)
            }
        }
    }
}

enum BrewFont {
    static let title = Font.system(size: 26, weight: .semibold)
    static let heading = Font.system(size: 19, weight: .semibold)
    static let body = Font.system(size: 15, weight: .medium)
    static let caption = Font.system(size: 12, weight: .regular)
}

struct BrewPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("haptics") private var haptics = true
    @AppStorage(BrewHapticStrength.storageKey) private var hapticStrength = BrewHapticStrength.defaultValue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !systemReduceMotion && !reduceMotion ? 0.95 : 1)
            .animation(systemReduceMotion || reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.8),
                       value: configuration.isPressed)
            .sensoryFeedback(hapticStrength.pressFeedback, trigger: configuration.isPressed) { _, pressed in
                pressed && haptics
            }
    }
}

struct SidebarGeometry: Equatable {
    // The system status bar can be vertical while UITabBar stays horizontal
    // after a fold. Utility controls follow the window, not the selected tab.
    var vertical: Bool? = nil
    var frame = CGRect.zero
    var axisX: CGFloat = 0
    var reservations: [CGRect] = []
}

/// Public bar layout regions follow the status cluster and Live Activities.
/// A low-frequency timer also catches region changes that don't resize the
/// application's safe-area rectangle (the vertical status bar can grow in place).
struct SidebarGeometryReader: UIViewRepresentable {
    var onChange: (SidebarGeometry) -> Void
    func makeUIView(context: Context) -> Probe {
        let view = Probe(); view.onChange = onChange; return view
    }
    func updateUIView(_ view: Probe, context: Context) { view.onChange = onChange; view.sample() }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.stop() }

    final class Probe: UIView {
        var onChange: ((SidebarGeometry) -> Void)?
        private var last = SidebarGeometry()
        private var pollTimer: Timer?
        private weak var guideWindow: UIWindow?
        private var barGuide: UILayoutGuide?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            stop()
            if window != nil {
                // Sidebar polling must not cast a 10 Hz vote in display pacing.
                let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.sample() }
                timer.tolerance = 0.02
                RunLoop.main.add(timer, forMode: .common)
                pollTimer = timer
                sample()
            }
        }
        override func layoutSubviews() { super.layoutSubviews(); sample() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); sample() }
        func stop() { pollTimer?.invalidate(); pollTimer = nil }
        func sample() {
            guard let window, window.bounds.width > 0 else { return }
            let bounds = window.bounds
            let vertical = window.safeAreaInsets.right > 40
            let axis = vertical ? bounds.maxX - 48 : bounds.maxX - 33
            var region = CGRect(x: 0, y: window.safeAreaInsets.top + 8,
                                width: bounds.width, height: max(0, bounds.height - window.safeAreaInsets.top - window.safeAreaInsets.bottom - 16))
            var reservations: [CGRect] = []
            if #available(iOS 27.1, *) {
                if vertical {
                    if guideWindow !== window || barGuide == nil {
                        guideWindow = window
                        barGuide = window.layoutGuide(for: .bar(onEdge: NSDirectionalRectEdge.trailing, extent: 84))
                    }
                    if let barGuide, !barGuide.layoutFrame.isEmpty { region = barGuide.layoutFrame }
                }
                reservations = window.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
                for reserved in reservations where reserved.minY < bounds.height * 0.55 {
                    let horizontalOverlap = !vertical || (reserved.minX < axis + 24 && reserved.maxX > axis - 24)
                    if horizontalOverlap && reserved.maxY > region.minY && reserved.height < bounds.height * 0.65 {
                        let bottom = region.maxY
                        region.origin.y = reserved.maxY + 8
                        region.size.height = max(0, bottom - region.minY)
                    }
                }
            }
            let value = SidebarGeometry(vertical: vertical, frame: region, axisX: axis, reservations: reservations)
            guard value != last else { return }
            last = value
            DispatchQueue.main.async { [weak self] in self?.onChange?(value) }
        }
    }
}
