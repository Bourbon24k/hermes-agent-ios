import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var path = NavigationPath()
    @State private var recentSessions: [AgentSession] = []
    @State private var isLoadingSessions = true

    private enum Destination: Hashable {
        case chat, tasks, skills, memory, insights, profiles, sessions, files, settings
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        menu
                        sessionsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 90)
                }
                .refreshable { await loadSessions() }

                chatButton.padding(.trailing, 20).padding(.bottom, 24)
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Destination.self) { dest in
                switch dest {
                case .chat: ChatView(viewModel: appState.chatViewModel)
                case .tasks: TasksView()
                case .skills: SkillsView()
                case .memory: MemoryView()
                case .insights: InsightsView()
                case .profiles: ProfilesView()
                case .sessions: SessionsView()
                case .files: FilesView()
                case .settings: SettingsView()
                }
            }
            .navigationDestination(for: AgentSession.self) { SessionDetailView(session: $0) }
        }
        .onChange(of: appState.openChatRequest) {
            path = NavigationPath()
            path.append(Destination.chat)
        }
        .task { await loadSessions() }
        #if DEBUG
        .onAppear {
            if let dest = DebugLogin.debugOpenDestination {
                let target: Destination? = switch dest.lowercased() {
                case "profiles": .profiles
                case "settings": .settings
                case "skills":   .skills
                case "memory":   .memory
                case "insights": .insights
                case "tasks":    .tasks
                case "sessions": .sessions
                case "chat":     .chat
                default:         nil
                }
                if let target {
                    print("[DebugLogin] Auto-opening \(dest)")
                    path.append(target)
                }
            }
        }
        #endif
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HermesWordmark(size: 32)
            Spacer()
            Button { path.append(Destination.settings) } label: {
                Text(String(appState.displayName.prefix(2)).uppercased())
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 34, height: 34).background(Theme.accent, in: Circle())
            }
        }
    }

    // MARK: - Menu

    private var menu: some View {
        VStack(spacing: 0) {
            menuRow("calendar.badge.clock", "Tasks", .tasks)
            menuRow("hammer", "Skills", .skills)
            menuRow("brain", "Memory", .memory)
            menuRow("chart.bar", "Insights", .insights)
            menuRow("person.2", "Profiles", .profiles, chevron: true)
            menuRow("folder", "Files", .files, chevron: true)
            menuRow("clock.arrow.circlepath", "Sessions", .sessions, chevron: true)
        }
    }

    private func menuRow(_ icon: String, _ title: String, _ dest: Destination, chevron: Bool = false) -> some View {
        Button { path.append(dest) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Theme.textPrimary).frame(width: 24)
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                if chevron { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary) }
                Spacer()
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Sessions").font(.title3.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("See all") { path.append(Destination.sessions) }
                    .font(.subheadline).foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 6)

            if isLoadingSessions && recentSessions.isEmpty {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 24)
            } else if recentSessions.isEmpty {
                Text("No sessions yet. Tap Chat to start.").font(.subheadline).foregroundStyle(Theme.textTertiary).padding(.top, 8)
            }
            ForEach(recentSessions.prefix(8)) { session in
                Button { path.append(session) } label: { sessionRow(session) }.buttonStyle(.plain)
            }
        }
    }

    private func sessionRow(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                Text(session.shownTitle).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                if let started = session.startedAt { Text(started.relativeShort).font(.system(size: 12)).foregroundStyle(Theme.textTertiary) }
            }
            HStack(spacing: 5) {
                if let count = session.messageCount { Text("\(count) messages") }
                if let model = session.model { Text("·"); Text(model).lineLimit(1) }
            }
            .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chatButton: some View {
        Button { path.append(Destination.chat) } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil").font(.system(size: 16, weight: .semibold))
                Text("Chat").font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.black).padding(.horizontal, 22).padding(.vertical, 14)
            .background(.white, in: Capsule()).shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        }
    }

    private func loadSessions() async {
        isLoadingSessions = true
        recentSessions = (try? await appState.agent.sessions()) ?? []
        isLoadingSessions = false
    }
}
