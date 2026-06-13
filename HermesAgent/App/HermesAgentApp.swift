import SwiftUI

@main
struct HermesAgentApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .dynamicIslandBadge()
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch appState.phase {
            case .loading:
                ProgressView().tint(Theme.accent)
            case .unpaired:
                PairingView()
            case .paired:
                HomeView()
            }
        }
    }
}
