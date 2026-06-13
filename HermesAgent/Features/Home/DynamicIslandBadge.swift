import SwiftUI

/// A small branded badge pinned at the top-center of the screen, overlapping
/// the Dynamic Island / notch — the same pattern VK, Telegram and SwiftGram use
/// to mark a modded/sideloaded build. Purely an in-app overlay (no Live Activity).
struct DynamicIslandBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
            Text("HERMES")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .tracking(0.5)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.62, blue: 0.20),
                        Color(red: 0.93, green: 0.38, blue: 0.16),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        )
        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
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
