import SwiftUI

/// Dark theme with amber accent, inspired by the HermesPilot visual language.
enum Theme {
    static let background = Color.black
    static let surface = Color(white: 0.07)
    static let surfaceElevated = Color(white: 0.11)
    static let card = Color(white: 0.09)
    static let separator = Color(white: 0.16)
    static let accent = Color(red: 1.0, green: 0.76, blue: 0.03)
    static let accentDim = Color(red: 0.85, green: 0.62, blue: 0.0)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.62)
    static let textTertiary = Color(white: 0.42)
    static let success = Color(red: 0.22, green: 0.78, blue: 0.35)
    static let failure = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let codeBackground = Color(white: 0.08)
    static let userBubble = Color(white: 0.14)

    static func monoFont(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }
}

/// Blocky amber wordmark rendered with a custom pixel-style effect.
struct HermesWordmark: View {
    var size: CGFloat = 34

    var body: some View {
        Text("HERMES")
            .font(.system(size: size, weight: .black, design: .rounded))
            .kerning(1.5)
            .foregroundStyle(
                LinearGradient(
                    colors: [Theme.accent, Theme.accentDim],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: Theme.accent.opacity(0.35), radius: 6, y: 2)
    }
}

struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = 14) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

struct PillLabel: View {
    let text: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 11))
            }
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.surfaceElevated, in: Capsule())
        .foregroundStyle(Theme.textSecondary)
    }
}

extension Date {
    var relativeShort: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

extension String {
    var iso8601Date: Date? {
        let strategies: [Date.ISO8601FormatStyle] = [
            .init(includingFractionalSeconds: true),
            .init(includingFractionalSeconds: false),
        ]
        for strategy in strategies {
            if let date = try? Date(self, strategy: strategy) { return date }
        }
        return nil
    }
}
