import SwiftUI

/// A small branded badge pinned at the top-center of the screen, overlapping
/// the Dynamic Island / notch — the same pattern VK, Telegram and SwiftGram use
/// to mark a modded/sideloaded build. Purely an in-app overlay (no Live Activity).
struct DynamicIslandBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.accent)
            Text("HERMES")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.accent)
                .tracking(1.0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(Color(white: 0.08))
        )
        .overlay(
            Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 5, y: 1)
    }
}

/// Overlays the badge at the very top of the screen, in the status-bar / island band.
struct DynamicIslandBadgeOverlay: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            DynamicIslandBadge()
                .offset(y: 4)
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .top)
        }
    }
}

extension View {
    func dynamicIslandBadge() -> some View {
        modifier(DynamicIslandBadgeOverlay())
    }
}
