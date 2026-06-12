import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var status: SessionResponse?
    @State private var agentStatus: AgentStatus?
    @State private var isLoading = true
    @State private var showUnpairConfirm = false

    var body: some View {
        @Bindable var appState = appState
        List {
            // Account
            Section("Account") {
                row("Name", appState.displayName)
                connectionRow
                if let push = status?.push?.tokenRegistered {
                    row("Push", push ? "Registered" : "Off")
                }
            }
            .listRowBackground(Theme.card)

            // Relay
            Section("Relay") {
                row("URL", appState.relayURL)
                if let endpoint = status?.session.backendEndpoint {
                    row("Backend", endpoint)
                }
            }
            .listRowBackground(Theme.card)

            // Model preferences
            Section("AI Preferences") {
                NavigationLink {
                    ModelPickerSheet()
                } label: {
                    HStack {
                        Text("Model").foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(appState.selectedModel)
                            .font(Theme.monoFont(12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .listRowBackground(Theme.card)

                HStack {
                    Text("Thinking").foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Picker("", selection: Bindable(appState).thinkingBudget) {
                        ForEach(ThinkingBudget.allCases) { b in
                            Text(b.displayName).tag(b)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                }
                .listRowBackground(Theme.card)
            }

            // Agent info
            Section("Agent") {
                if let version = agentStatus?.hermesVersion {
                    row("Version", version)
                }
                row("Device", UIDevice.current.name)
                row("App", appVersion)
            }
            .listRowBackground(Theme.card)

            // Danger zone
            Section {
                Button(role: .destructive) {
                    showUnpairConfirm = true
                } label: {
                    Label("Unpair Device", systemImage: "link.badge.plus").foregroundStyle(Theme.failure)
                }
            }
            .listRowBackground(Theme.card)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Unpair from this relay?", isPresented: $showUnpairConfirm, titleVisibility: .visible) {
            Button("Unpair", role: .destructive) {
                Task { await appState.unpair(); dismiss() }
            }
        }
        .task { [api = appState.api, agent = appState.agent] in
            async let s = try? api.session()
            async let a = try? agent.status()
            status = await s
            agentStatus = await a
            isLoading = false
        }
    }

    // MARK: - Connection row

    private var connectionRow: some View {
        HStack {
            Text("Connection").foregroundStyle(Theme.textPrimary)
            Spacer()
            if isLoading {
                ProgressView().controlSize(.mini).tint(Theme.accent)
            } else {
                let connection = status?.session.connectionStatus ?? "unknown"
                let isConnected = connection == "connected"
                HStack(spacing: 5) {
                    Circle()
                        .fill(isConnected ? Theme.success : Theme.failure)
                        .frame(width: 8, height: 8)
                    Text(connection.capitalized)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isConnected ? Theme.success : Theme.failure)
                }
            }
        }
    }

    // MARK: - Helpers

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }
}
