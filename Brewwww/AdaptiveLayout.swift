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

    var landscape: Bool { size.width > size.height * 1.12 }
    var expanded: Bool { size.width >= 600 }
    var bottomNavigation: Bool { expanded && !landscape }
    var tabletop: Bool { hinge == .partiallyOpen && landscape }
    var book: Bool { hinge == .partiallyOpen && !landscape && expanded }
    var twoColumns: Bool { expanded || landscape }
    var pageWidth: CGFloat { max(0, size.width - 66) }
    var bookLeadingWidth: CGFloat { max(180, size.width / 2 - (leftHanded ? 66 : 0) - 26) }
    var animation: Animation? { reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88) }
    var titleTop: CGFloat { landscape ? 8 : min(36, size.height * 0.045) }
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
                DispatchQueue.main.async { state = next }
            }
            view.addInteraction(interaction)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !systemReduceMotion && !reduceMotion ? 0.95 : 1)
            .animation(systemReduceMotion || reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.8),
                       value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: configuration.isPressed) { _, pressed in
                pressed && haptics
            }
    }
}
