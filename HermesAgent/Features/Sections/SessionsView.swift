import SwiftUI

struct SessionsView: View {
    @Environment(AppState.self) private var appState
    @State private var sessions: [AgentSession] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var search = ""
    @State private var sessionToRename: AgentSession?
    @State private var sessionToDelete: AgentSession?
    @State private var busyId: String?

    private var filtered: [AgentSession] {
        search.isEmpty ? sessions : sessions.filter {
            $0.shownTitle.localizedCaseInsensitiveContains(search) ||
            ($0.model ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    /// Sessions grouped by day for date headers.
    private var grouped: [(label: String, items: [AgentSession])] {
        let cal = Calendar.current
        var buckets: [(label: String, items: [AgentSession])] = []
        for session in filtered {
            let label: String
            if let date = session.startedAt {
                if cal.isDateInToday(date) { label = "Today" }
                else if cal.isDateInYesterday(date) { label = "Yesterday" }
                else { label = date.formatted(.dateTime.day().month(.wide)) }
            } else {
                label = "Earlier"
            }
            if let last = buckets.indices.last, buckets[last].label == label {
                buckets[last].items.append(session)
            } else {
                buckets.append((label, [session]))
            }
        }
        return buckets
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) {
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                    TextField("Search sessions…", text: $search)
                        .foregroundStyle(Theme.textPrimary).tint(Theme.accent)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 4)

                if sessions.isEmpty && !isLoading {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 32)).foregroundStyle(Theme.textTertiary)
                        Text("No sessions yet.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                }

                ForEach(grouped, id: \.label) { group in
                    Text(group.label.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 8).padding(.leading, 2)
                    ForEach(group.items) { session in
                        NavigationLink(value: session) {
                            card(session)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                Task { await resume(session) }
                            } label: { Label("Continue in Chat", systemImage: "arrow.uturn.forward") }
                            Button {
                                sessionToRename = session
                            } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) {
                                sessionToDelete = session
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.failure)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        // NOTE: the AgentSession destination is registered once at the HomeView root.
        // Re-declaring it here would conflict within the same NavigationStack and render blank.
        .overlay { if isLoading && sessions.isEmpty { ProgressView().tint(Theme.accent) } }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $sessionToRename) { session in
            RenameSessionSheet(session: session) { newTitle in
                await rename(session, to: newTitle)
            }
        }
        .confirmationDialog(
            "Delete \"\(sessionToDelete?.shownTitle ?? "")\"? This cannot be undone.",
            isPresented: Binding(get: { sessionToDelete != nil }, set: { if !$0 { sessionToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let s = sessionToDelete { Task { await delete(s) } }
            }
        }
    }

    private func resume(_ session: AgentSession) async {
        await appState.chatViewModel.resume(sessionId: session.id, agent: appState.agent)
        appState.openChat()
    }

    private func rename(_ session: AgentSession, to title: String) async {
        do {
            try await appState.agent.renameSession(id: session.id, title: title)
            Haptics.success()
            await load()
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
            Haptics.error()
        }
    }

    private func delete(_ session: AgentSession) async {
        do {
            try await appState.agent.deleteSession(id: session.id)
            sessions.removeAll { $0.id == session.id }
            Haptics.success()
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
            Haptics.error()
        }
        sessionToDelete = nil
    }

    private func card(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: iconFor(session.source))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.shownTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let started = session.startedAt {
                        Text(started.relativeShort)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            HStack(spacing: 8) {
                if let count = session.messageCount {
                    chip("\(count) msg", icon: "bubble.left")
                }
                if let tools = session.toolCallCount, tools > 0 {
                    chip("\(tools) tools", icon: "wrench")
                }
                if let model = session.model, !model.isEmpty {
                    chip(shortModel(model), icon: "cpu")
                }
                Spacer()
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chip(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.surfaceElevated, in: Capsule())
    }

    private func iconFor(_ source: String?) -> String {
        switch source?.lowercased() {
        case "telegram": return "paperplane.fill"
        case "discord": return "gamecontroller.fill"
        case "cron": return "calendar.badge.clock"
        case "api", "api_server": return "antenna.radiowaves.left.and.right"
        default: return "bubble.left.and.bubble.right.fill"
        }
    }

    private func shortModel(_ model: String) -> String {
        let raw = model.split(separator: "/").last.map(String.init) ?? model
        let words = raw.split(separator: "-").map(String.init)
        return words.prefix(2).map { w in
            w.first.map { String($0).uppercased() + w.dropFirst() } ?? w
        }.joined(separator: " ")
    }

    private func load() async {
        isLoading = true; errorText = nil
        do { sessions = try await appState.agent.sessions() } catch { if !error.isCancellation { errorText = error.localizedDescription } }
        isLoading = false
    }
}

struct SessionDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let session: AgentSession
    @State private var messages: [AgentSessionMessage] = []
    @State private var isLoading = true
    @State private var isResuming = false
    @State private var showRename = false
    @State private var showDeleteConfirm = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.failure)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 80)
        }
        .background(Theme.background)
        .navigationTitle(session.shownTitle)
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView().tint(Theme.accent) } }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await resume() }
            } label: {
                HStack(spacing: 8) {
                    if isResuming {
                        ProgressView().controlSize(.small).tint(.black)
                    } else {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    Text("Continue in Chat").fontWeight(.semibold)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent, in: Capsule())
            }
            .disabled(isResuming)
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showRename = true } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showRename) {
            RenameSessionSheet(session: session) { newTitle in
                try? await appState.agent.renameSession(id: session.id, title: newTitle)
                Haptics.success()
            }
        }
        .confirmationDialog(
            "Delete this session? This cannot be undone.",
            isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await appState.agent.deleteSession(id: session.id)
                    Haptics.success()
                    dismiss()
                }
            }
        }
        .task {
            messages = (try? await appState.agent.messages(sessionId: session.id)) ?? []
            isLoading = false
        }
    }

    private func resume() async {
        isResuming = true; errorText = nil
        await appState.chatViewModel.resume(sessionId: session.id, agent: appState.agent)
        isResuming = false
        appState.openChat()
    }
}

// MARK: - Rename Session Sheet

struct RenameSessionSheet: View {
    let session: AgentSession
    let onRename: (String) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var isSaving = false

    init(session: AgentSession, onRename: @escaping (String) async -> Void) {
        self.session = session
        self.onRename = onRename
        _title = State(initialValue: session.shownTitle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session title") {
                    TextField("Title", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                        .font(.system(size: 16)).foregroundStyle(Theme.textPrimary)
                        .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Rename Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSaving = true
                        Task {
                            await onRename(title.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        } else {
                            Text("Save").fontWeight(.semibold)
                                .foregroundStyle(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.textTertiary : Theme.accent)
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.medium])
    }
}
