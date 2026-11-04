import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

enum Theme {
    static let blue = Color(red: 0.16, green: 0.42, blue: 1.0)
    static let teal = Color(red: 0.0, green: 0.66, blue: 0.72)
    static let green = Color(red: 0.16, green: 0.74, blue: 0.45)

    static let brand = LinearGradient(colors: [blue, teal, green],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardStroke = Color.primary.opacity(0.08)
}

struct Card: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardStroke))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(Card(padding: padding)) }
}

/// The main call-to-action button: brand gradient, white text.
struct GradientButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(large ? .title3.weight(.semibold) : .body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 28 : 16)
            .padding(.vertical, large ? 12 : 7)
            .background(Theme.brand, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: Theme.teal.opacity(isEnabled ? 0.3 : 0), radius: 10, y: 4)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The app's icon from the bundle, or a gradient shield while running unbundled.
struct AppIconView: View {
    var size: CGFloat = 88
    var body: some View {
        if let icon = NSImage(named: "AppIcon") ?? Bundle.main.image(forResource: "AppIcon") {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(Theme.brand)
                .frame(width: size * 0.82, height: size * 0.82)
                .overlay(Image(systemName: "lock.shield.fill")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white))
                .frame(width: size, height: size)
        }
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
            Text(text).font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.cardStroke))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

/// Scrolling, auto-following output from the server.
struct LogView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines.indices, id: \.self) { index in
                        Text(lines[index])
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(lines[index].hasPrefix("==>") ? HierarchicalShapeStyle.primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(12)
                .textSelection(.enabled)
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: lines.count) { count in
                if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
    }
}

enum QRCode {
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: output.extent.width, height: output.extent.height))
    }
}
