import SwiftUI
import UIKit

enum BrewAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

// Dark: native 3× recordings, converted from CoreMedia709 to sRGB.
// Light: supplied light-mode stamp screenshots, plus coordinated companion surfaces
// where no light reference exists. See 设计取色/深浅色主题.md for provenance.
enum BrewStyle {
    static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let ink = adaptive(light: 0xF8F7F0, dark: 0x2B2A23)
    static let text = adaptive(light: 0x3C2723, dark: 0xD3D0CB)
    static let panel = adaptive(light: 0xF0EDE7, dark: 0x463E36)
    static let panelLight = adaptive(light: 0xE4DFD7, dark: 0x655A54)
    static let muted = adaptive(light: 0x968E89, dark: 0xA19B96)
    static let gold = adaptive(light: 0xC5925E, dark: 0xDCAB70)
    static let orange = adaptive(light: 0xDC7F45, dark: 0xB84D07)
    static let weekday = adaptive(light: 0x958D83, dark: 0x867F77)
    static let calendarNumber = adaptive(light: 0x63564C, dark: 0xD3D0C9)
    static let calendarCorner = adaptive(light: 0xCDBCA7, dark: 0x332924)
    static let calendarCornerInk = adaptive(light: 0x59443A, dark: 0xF5F0E3)
    static let todayNumber = adaptive(light: 0xFAF9F4, dark: 0xD3D0C9)
    static let control = adaptive(light: 0xF1F0EC, dark: 0x383734)
    static let icon = adaptive(light: 0x897B79, dark: 0xA39A96)
    static let selection = adaptive(light: 0xE4E1DE, dark: 0x666561)
    static let border = adaptive(light: 0xFFFFFF, dark: 0x635B53)
    static let placeholder = adaptive(light: 0xA49B91, dark: 0x776D67)
    static let confirmation = rgb(0xFAF9F4)
    static let photoFrame = rgb(0xDFB16F)
    static let photoInk = rgb(0x321500)
    static let photoCaption = rgb(0x795521)
    static let photoWhite = rgb(0xFEFEFE)
    static let toggleOff = adaptive(light: 0xD8D4CE, dark: 0xE7E5DE)
    static let souvenirPanel = adaptive(light: 0xEAE5DC, dark: 0x5B5249)
    static let folderBack = adaptive(light: 0xD5CBB9, dark: 0x443D36)
    static let folderLeft = adaptive(light: 0xDBCAA9, dark: 0x726550)
    static let folderCenter = adaptive(light: 0xE2D1B1, dark: 0x7A6C54)
    static let folderRight = adaptive(light: 0xD6CBB9, dark: 0x70685D)
    static let folderBottom = adaptive(light: 0xCDBB9C, dark: 0x6E6353)
    static let folderTab = adaptive(light: 0xDDD0B8, dark: 0x746A5A)
    static let albumTop = adaptive(light: 0xF0EEEA, dark: 0x3F3A39)
    static let albumMiddle = adaptive(light: 0xE9E5DE, dark: 0x47433F)
    static let albumBottom = adaptive(light: 0xEFEBE5, dark: 0x3F3B3A)
    static let albumControl = adaptive(light: 0xF1EFEB, dark: 0x403F3D)
    static let stampPink = rgb(0xD97F69)
    static let stampGold = rgb(0xC59A65)
    static let mapPanel = adaptive(light: 0xF5F3EE, dark: 0x32363D)
    static let mapPin = rgb(0xD25400)
    static let mapControl = adaptive(light: 0xF1F0ED, dark: 0x32394A)
    static let mapNavigation = adaptive(light: 0xF1F0ED, dark: 0x363D46)
    static let mapSelection = adaptive(light: 0xE4E1DD, dark: 0x65686D)
}

struct BrewBackground: View {
    @AppStorage("passportStyle") private var passportStyle = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            BrewStyle.ink
            Image(uiImage: BrewPaperTexture.image(
                named: passportStyle == 1 ? "PaperPreview2" : passportStyle == 2 ? "PaperPreview3" : "PaperReference",
                dark: colorScheme == .dark))
                .resizable(resizingMode: .tile)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Reference crops contain lighting gradients and are not repeatable textures.
/// Keep their grain and average colour, remove uneven illumination, then reflect
/// both axes so every repeated edge meets the same pixels. Original assets stay intact.
@MainActor private enum BrewPaperTexture {
    private static var cache: [String: UIImage] = [:]

    static func image(named name: String, dark: Bool) -> UIImage {
        let key = "\(name)-\(dark)"
        if let image = cache[key] { return image }
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        guard let source = UIImage(named: name, in: .main, compatibleWith: traits),
              let cgImage = source.cgImage else { return UIImage() }
        let width = cgImage.width, height = cgImage.height
        let stride = width + 1
        let colourSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: colourSpace, bitmapInfo: bitmapInfo) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return source }
        var balanced = pixels
        let radius = max(12, min(width, height) / 4)
        for channel in 0..<3 {
            var integral = [Double](repeating: 0, count: stride * (height + 1))
            for y in 0..<height {
                var row: Double = 0
                for x in 0..<width {
                    row += Double(pixels[(y * width + x) * 4 + channel])
                    integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + row
                }
            }
            let average = integral[height * stride + width] / Double(width * height)
            for y in 0..<height {
                let top = max(0, y - radius), bottom = min(height, y + radius + 1)
                for x in 0..<width {
                    let left = max(0, x - radius), right = min(width, x + radius + 1)
                    let sum = integral[bottom * stride + right] - integral[top * stride + right]
                        - integral[bottom * stride + left] + integral[top * stride + left]
                    let local = sum / Double((right - left) * (bottom - top))
                    let index = (y * width + x) * 4 + channel
                    balanced[index] = UInt8(clamping: Int((Double(pixels[index]) - local + average).rounded()))
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(balanced) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: colourSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return source }
        let tile = UIImage(cgImage: image, scale: source.scale, orientation: .up)
        let format = UIGraphicsImageRendererFormat()
        format.scale = source.scale; format.opaque = true
        let result = UIGraphicsImageRenderer(size: CGSize(width: tile.size.width * 2, height: tile.size.height * 2),
                                            format: format).image { renderer in
            let context = renderer.cgContext
            for y in 0..<2 {
                for x in 0..<2 {
                    context.saveGState()
                    context.translateBy(x: x == 0 ? 0 : tile.size.width * 2, y: y == 0 ? 0 : tile.size.height * 2)
                    context.scaleBy(x: x == 0 ? 1 : -1, y: y == 0 ? 1 : -1)
                    tile.draw(at: .zero)
                    context.restoreGState()
                }
            }
        }
        cache[key] = result
        return result
    }
}

struct BrewPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    var mapSurface: Bool

    init(mapSurface: Bool = false, @ViewBuilder content: () -> Content) {
        self.mapSurface = mapSurface
        self.content = content()
    }

    var body: some View {
        content
            .background {
                if mapSurface && colorScheme == .dark { Image("MapCardReference").resizable(resizingMode: .tile) }
                else if mapSurface { BrewStyle.mapPanel }
                else { BrewStyle.panel }
            }
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(BrewStyle.border, lineWidth: 1))
    }
}

struct RoundIcon: View {
    var symbol: String
    var active = false
    var size: CGFloat = 46
    var accent = false
    @Environment(\.brewControlSurface) private var surface

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(active ? BrewStyle.confirmation : accent ? BrewStyle.gold : BrewStyle.icon)
            .frame(width: size, height: size)
            .background(active ? BrewStyle.gold : surface)
            .clipShape(Circle())
            .overlay(Circle().stroke(BrewStyle.border, lineWidth: 1))
    }
}

struct TakeawayCup: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = CGAffineTransform(a: rect.width / 24, b: 0, c: 0, d: rect.height / 28,
                                 tx: rect.minX, ty: rect.minY)
        p.addRoundedRect(in: CGRect(x: 3, y: 6, width: 18, height: 4), cornerSize: CGSize(width: 1, height: 1))
        p.move(to: CGPoint(x: 5, y: 6)); p.addLine(to: CGPoint(x: 6, y: 3))
        p.addLine(to: CGPoint(x: 18, y: 3)); p.addLine(to: CGPoint(x: 19, y: 6))
        p.move(to: CGPoint(x: 5, y: 10)); p.addLine(to: CGPoint(x: 7, y: 25))
        p.addLine(to: CGPoint(x: 17, y: 25)); p.addLine(to: CGPoint(x: 19, y: 10))
        p.move(to: CGPoint(x: 6, y: 14)); p.addLine(to: CGPoint(x: 18, y: 14))
        return p.applying(t)
    }
}

struct RubberStamp: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = CGAffineTransform(a: rect.width / 24, b: 0, c: 0, d: rect.height / 28,
                                 tx: rect.minX, ty: rect.minY)
        p.move(to: CGPoint(x: 8, y: 17))
        p.addCurve(to: CGPoint(x: 8, y: 7), control1: CGPoint(x: 10, y: 14), control2: CGPoint(x: 8, y: 11))
        p.addCurve(to: CGPoint(x: 16, y: 7), control1: CGPoint(x: 5, y: 0), control2: CGPoint(x: 19, y: 0))
        p.addCurve(to: CGPoint(x: 16, y: 17), control1: CGPoint(x: 16, y: 11), control2: CGPoint(x: 14, y: 14))
        p.addRoundedRect(in: CGRect(x: 4, y: 17, width: 16, height: 5), cornerSize: CGSize(width: 1.5, height: 1.5))
        p.addRoundedRect(in: CGRect(x: 6, y: 22, width: 12, height: 3), cornerSize: CGSize(width: 1, height: 1))
        return p.applying(t)
    }
}

struct DrinkSticker: View {
    var image: UIImage?
    var cutout: UIImage? = nil
    var size: CGFloat = 70

    var body: some View {
        Group {
            if let cutout {
                Image(uiImage: cutout)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.25)
                        .stroke(.white, lineWidth: max(3, size * 0.06)))
            } else {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: size * 0.50, weight: .light))
                    .foregroundStyle(BrewStyle.gold)
                    .frame(width: size, height: size)
                    .background(BrewStyle.panelLight)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.25)
                        .stroke(.white, lineWidth: max(3, size * 0.06)))
            }
        }
        .rotationEffect(.degrees(-7))
        .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
    }
}

struct EmptyPage: View {
    var title: String
    var symbol: String
    var detail: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 66, weight: .ultraLight))
                .foregroundStyle(BrewStyle.gold)
            Text(title).font(.title3.bold())
            Text(detail).font(.subheadline).foregroundStyle(BrewStyle.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

extension View {
    func brewRow() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
            .background(BrewStyle.panel)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(BrewStyle.border, lineWidth: 1))
    }
}

private struct BrewControlSurfaceKey: EnvironmentKey {
    static let defaultValue = BrewStyle.control
}
extension EnvironmentValues {
    var brewControlSurface: Color {
        get { self[BrewControlSurfaceKey.self] }
        set { self[BrewControlSurfaceKey.self] = newValue }
    }
}

struct BrewToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label.foregroundStyle(configuration.isOn ? BrewStyle.text : BrewStyle.icon)
            Spacer()
            Button { withAnimation(.easeInOut(duration: 0.18)) { configuration.isOn.toggle() } } label: {
                Capsule().fill(configuration.isOn ? BrewStyle.gold : BrewStyle.toggleOff)
                    .frame(width: 38, height: 24)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(BrewStyle.photoWhite).frame(width: 20, height: 20).padding(2)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(configuration.isOn ? "关闭" : "开启"))
        }
        .accessibilityRepresentation {
            Toggle(isOn: Binding(get: { configuration.isOn }, set: { configuration.isOn = $0 })) {
                configuration.label
            }.toggleStyle(.switch)
        }
    }
}
