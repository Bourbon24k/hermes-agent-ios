import SwiftUI

struct ProfilesView: View {
    @Environment(AppState.self) private var appState
    @State private var profiles: [AgentProfile] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var activatingName: String?

    var body: some View {
        List {
            if profiles.isEmpty && !isLoading {
                Text("No profiles found.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Theme.background)
            }
            ForEach(profiles) { profile in
                HStack(spacing: 12) {
                    // Avatar
                    Text(String(profile.name.prefix(2)).uppercased())
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(profile.active == true ? Theme.accent : Theme.textTertiary, in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        if profile.active == true {
                            Text("Active").font(.system(size: 12)).foregroundStyle(Theme.success)
                        }
                    }
                    Spacer()

                    if profile.active == true {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    } else {
                        Button {
                            Task { await activate(name: profile.name) }
                        } label: {
                            if activatingName == profile.name {
                                ProgressView().controlSize(.small).tint(Theme.accent)
                            } else {
                                Text("Use")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(Theme.accent.opacity(0.12), in: Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(activatingName != nil)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(Theme.card)
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(Theme.failure)
                    .listRowBackground(Theme.background)
            }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView().tint(Theme.accent) } }
        .refreshable { await load() }
        .task { await load() }
    }

    private func activate(name: String) async {
        activatingName = name
        do {
            try await appState.agent.useProfile(name: name)
            await load()
        } catch {
            errorText = error.localizedDescription
        }
        activatingName = nil
    }

    private func load() async {
        isLoading = true; errorText = nil
        do { profiles = try await appState.agent.profiles() } catch { errorText = error.localizedDescription }
        isLoading = false
    }
}
