import SwiftUI

struct SessionsView: View {
    @Environment(AppState.self) private var appState
    @State private var sessions: [AgentSession] = []
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        List {
            if sessions.isEmpty && !isLoading {
                Text("No sessions yet.").font(.subheadline).foregroundStyle(Theme.textSecondary).listRowBackground(Theme.background)
            }
            ForEach(sessions) { session in
                NavigationLink(value: session) {
                    row(session)
                }
                .listRowBackground(Theme.card)
            }
            if let errorText { Text(errorText).font(.footnote).foregroundStyle(Theme.failure).listRowBackground(Theme.background) }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("Sessions")
        // NOTE: the AgentSession destination is registered once at the HomeView root.
        // Re-declaring it here would conflict within the same NavigationStack and render blank.
        .overlay { if isLoading { ProgressView().tint(Theme.accent) } }
        .refreshable { await load() }
        .task { await load() }
    }

    private func row(_ session: AgentSession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.shownTitle)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                // Subtitle: N messages · source · model
                HStack(spacing: 4) {
                    if let count = session.messageCount {
                        Text("\(count) msg")
                    }
                    if let source = session.source, !source.isEmpty {
                        Text("·")
                        Text(source)
                    }
                    if let model = session.model, !model.isEmpty {
                        Text("·")
                        Text(shortModel(model)).lineLimit(1)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let started = session.startedAt {
                    Text(started.relativeShort)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                if let source = session.source, !source.isEmpty {
                    Text(source)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func shortModel(_ model: String) -> String {
        let parts = model.split(separator: "-")
        if parts.count >= 3, let first = parts.dropFirst().first {
            let name = first.capitalized
            let ver = parts.dropFirst(2).joined(separator: ".")
            return "\(name) \(ver)"
        }
        return model
    }

    private func load() async {
        isLoading = true; errorText = nil
        do { sessions = try await appState.agent.sessions() } catch { errorText = error.localizedDescription }
        isLoading = false
    }
}

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    let session: AgentSession
    @State private var messages: [AgentSessionMessage] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if messages.isEmpty && !isLoading {
                    VStack(spacing: 10) {
                        Image(systemName: "text.bubble").font(.system(size: 30)).foregroundStyle(Theme.textTertiary)
                        Text("No readable messages in this session.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 100)
                }
                ForEach(messages) { message in
                    MessageView(message: ChatMessage(id: message.id, role: message.role, content: message.text))
                }
            }
            .padding(.horizontal, 16).padding(.top, 12)
        }
        .background(Theme.background)
        .navigationTitle(session.shownTitle)
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView().tint(Theme.accent) } }
        .task {
            messages = (try? await appState.agent.messages(sessionId: session.id)) ?? []
            isLoading = false
        }
    }
}
