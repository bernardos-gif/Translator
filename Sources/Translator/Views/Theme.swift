import AppKit
import SwiftUI

enum Theme {
    static let indigo = Color(red: 0.31, green: 0.36, blue: 1.0)
    static let violet = Color(red: 0.58, green: 0.27, blue: 0.95)
    static let pink = Color(red: 0.92, green: 0.29, blue: 0.62)

    static let brand = LinearGradient(colors: [indigo, violet, pink],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
    static let brandSoft = LinearGradient(colors: [indigo.opacity(0.18), violet.opacity(0.14), pink.opacity(0.10)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Distinct, stable colour per bottle so they're easy to tell apart.
    static func color(for key: String) -> Color {
        let palette: [Color] = [indigo, violet, pink, .orange, .teal, .green, .blue, .mint]
        let hash = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return palette[hash % palette.count]
    }

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardStroke = Color.primary.opacity(0.08)
}

/// A rounded card with a soft border and shadow.
struct Card: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.cardStroke))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

extension View {
    func card(padding: CGFloat = 16, radius: CGFloat = 14) -> some View {
        modifier(Card(padding: padding, radius: radius))
    }
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
            .padding(.vertical, large ? 13 : 7)
            .background(Theme.brand, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: Theme.violet.opacity(isEnabled ? 0.35 : 0), radius: 10, y: 4)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Secondary pill button.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07), in: Capsule())
            .contentShape(Capsule())
    }
}

/// Icon for a Windows program: the real embedded icon when it can be read, otherwise a monogram.
struct ProgramIcon: View {
    let url: URL
    var name: String? = nil
    var size: CGFloat = 56

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            if let cached = IconExtractor.cachedIcon(for: url) {
                image = cached
                return
            }
            let target = url
            image = await Task.detached(priority: .utility) { IconExtractor.icon(for: target) }.value
        }
    }

    private var monogram: some View {
        let title = name ?? url.deletingPathExtension().lastPathComponent
        let letter = title.first.map { String($0).uppercased() } ?? "?"
        return RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [Theme.color(for: title), Theme.color(for: title).opacity(0.65)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Text(letter)
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .padding(size * 0.06)
    }
}

/// The coloured rounded square that represents a bottle.
struct BottleBadge: View {
    let name: String
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [Theme.color(for: name), Theme.color(for: name).opacity(0.7)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// A transient message shown at the bottom of the window.
struct ToastView: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.cardStroke))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

/// The app's own icon (from the bundle when packaged, a gradient glyph during development).
struct AppIconView: View {
    var size: CGFloat = 96
    var body: some View {
        if let icon = NSImage(named: "AppIcon") ?? Bundle.main.image(forResource: "AppIcon") {
            Image(nsImage: icon).resizable().frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(Theme.brand)
                .frame(width: size * 0.82, height: size * 0.82)
                .overlay(Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white))
                .frame(width: size, height: size)
        }
    }
}
