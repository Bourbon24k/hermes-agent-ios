import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var status: SessionResponse?
    @State private var agentStatus: AgentStatus?
    @State private var isLoading = true
    @State private var showUnpairConfirm = false
    @State private var systemPromptPreview: String = "..."

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

            Section("App") {
                Toggle(isOn: Bindable(appState).hapticsEnabled) {
                    Text("Haptic feedback").foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.accent)
                .listRowBackground(Theme.card)

                HStack {
                    Text("Chat text size").foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Picker("", selection: Bindable(appState).chatTextSize) {
                        ForEach(AppState.ChatTextSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                }
                .listRowBackground(Theme.card)

                Toggle(isOn: Bindable(appState).showTimestamps) {
                    Text("Message timestamps").foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.accent)
                .listRowBackground(Theme.card)

                Toggle(isOn: Bindable(appState).autoExpandThinking) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-expand thinking").foregroundStyle(Theme.textPrimary)
                        Text("Open the reasoning block while the agent thinks")
                            .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .tint(Theme.accent)
                .listRowBackground(Theme.card)

                Toggle(isOn: Bindable(appState).confirmNewChat) {
                    Text("Confirm new conversation").foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.accent)
                .listRowBackground(Theme.card)
            }

            // System Prompt
            Section("System Prompt") {
                NavigationLink {
                    SystemPromptEditor(agent: appState.agent)
                } label: {
                    HStack {
                        Text("SYSTEM.md").foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(systemPromptPreview)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .listRowBackground(Theme.card)

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
            async let sp = try? agent.systemPrompt()
            status = await s
            agentStatus = await a
            let prompt = await sp
            systemPromptPreview = prompt.flatMap { $0.isEmpty ? "Not set" : String($0.prefix(50)) } ?? "Not set"
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

// MARK: - System Prompt Editor

struct SystemPromptEditor: View {
    let agent: AgentAPI
    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $content)
                    .font(Theme.monoFont(13))
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Theme.background)
                    .tint(Theme.accent)
                    .padding(.horizontal, 12)
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(Theme.failure).padding()
            }
        }
        .background(Theme.background)
        .navigationTitle("System Prompt")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                    } else {
                        Text("Save").foregroundStyle(Theme.accent).fontWeight(.semibold)
                    }
                }
                .disabled(isSaving)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do { content = try await agent.systemPrompt() } catch { if !error.isCancellation { errorText = error.localizedDescription } }
        isLoading = false
    }

    private func save() async {
        isSaving = true; errorText = nil
        do { try await agent.saveSystemPrompt(content); dismiss() } catch { if !error.isCancellation { errorText = error.localizedDescription } }
        isSaving = false
    }
}
