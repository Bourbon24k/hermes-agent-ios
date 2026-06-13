import SwiftUI
import UIKit

struct ChatView: View {
    @Environment(AppState.self) private var appState
    /// Owned by AppState — the stream and partial message survive leaving this screen.
    let viewModel: ChatViewModel
    @State private var inputText = ""
    @State private var showSettings = false
    @State private var showClearConfirm = false
    @State private var pendingImage: UIImage?

    enum CommandSheet: String, Identifiable {
        case memory, sessions, tasks, skills, files, help
        var id: String { rawValue }
    }
    @State private var commandSheet: CommandSheet?

    var body: some View {
        VStack(spacing: 0) {
            messages
            // Pending image thumbnail
            if let img = pendingImage {
                HStack {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            Button { pendingImage = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Theme.textSecondary)
                                    .background(Circle().fill(Theme.background))
                                    .offset(x: 6, y: -6)
                            }
                        }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .background(Theme.background)
            }
            ChatInputBar(
                text: $inputText,
                isStreaming: viewModel.isStreaming,
                streamingPhase: viewModel.streamingPhase,
                selectedImage: $pendingImage,
                onSend: {
                    let text = inputText
                    let img = pendingImage
                    inputText = ""
                    pendingImage = nil
                    Task { await viewModel.send(text: text, model: appState.selectedModel, thinking: appState.thinkingBudget, image: img) }
                },
                onStop: { viewModel.stop() },
                onCommand: { cmd in
                    Task { await handleSlashCommand(cmd) }
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .padding(.top, 6)
            .background(Theme.background)
        }
        .background(Theme.background)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { HermesWordmark(size: 22) }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if appState.confirmNewChat {
                        showClearConfirm = true
                    } else {
                        Task { await viewModel.clear() }
                    }
                } label: {
                    Image(systemName: "square.and.pencil").foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettings = false }.foregroundStyle(Theme.accent)
                        }
                    }
            }
        }
        .confirmationDialog("Start a new conversation? The current one is archived.", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("New conversation", role: .destructive) { Task { await viewModel.clear() } }
        }
        .sheet(item: $commandSheet) { sheet in
            if sheet == .help {
                CommandHelpSheet()
            } else {
                NavigationStack {
                    Group {
                        switch sheet {
                        case .memory:   MemoryView()
                        case .sessions: SessionsView()
                        case .tasks:    TasksView()
                        case .skills:   SkillsView()
                        case .files:    FilesView()
                        case .help:     EmptyView()
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { commandSheet = nil }.foregroundStyle(Theme.accent)
                        }
                    }
                    .navigationDestination(for: AgentSession.self) { SessionDetailView(session: $0) }
                }
                .presentationBackground(Theme.background)
            }
        }
        .task {
            await viewModel.load()
            // Reflect the agent's actual current model in the input bar pill.
            if let current = try? await appState.agent.models().current.model {
                appState.selectedModel = current
            }
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if viewModel.isLoading && viewModel.messages.isEmpty {
                        ProgressView().tint(Theme.accent).padding(.top, 80)
                    } else if viewModel.messages.isEmpty {
                        empty.padding(.top, 120)
                    }
                    ForEach(viewModel.messages) { message in
                        MessageView(
                            message: message,
                            isStreaming: viewModel.isStreaming && message.id == viewModel.messages.last?.id,
                            streamingPhase: viewModel.isStreaming && message.id == viewModel.messages.last?.id ? viewModel.streamingPhase : .idle
                        )
                        .id(message.id)
                    }
                    if let error = viewModel.errorText {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.failure)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: viewModel.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: viewModel.messages.last?.content) {
                // Follow the streaming reply only when already near the bottom is
                // handled by defaultScrollAnchor; this nudges the tail into view.
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private let suggestions: [String] = [
        "Summarize the latest news for me",
        "Write a Python script to rename files",
        "Explain how transformers work",
        "Help me debug my code",
    ]

    private var empty: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.textTertiary)
                Text("Send a message to start the conversation.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            VStack(spacing: 10) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        inputText = suggestion
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Slash command handling

    private func handleSlashCommand(_ cmd: String) async {
        switch cmd {
        case "reset", "clear":
            await viewModel.clear()
        case "memory":   commandSheet = .memory
        case "sessions": commandSheet = .sessions
        case "tasks":    commandSheet = .tasks
        case "skills":   commandSheet = .skills
        case "files":    commandSheet = .files
        case "help":     commandSheet = .help
        default:
            break
        }
    }
}

// MARK: - Help sheet

struct CommandHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let entries: [(String, String)] = [
        ("/reset", "Start a new conversation (archives the current one)"),
        ("/model", "Switch the agent's AI model"),
        ("/think", "Set reasoning level: off / low / medium / high"),
        ("/memory", "View and edit the agent's memory files"),
        ("/sessions", "Browse past agent sessions"),
        ("/tasks", "Manage scheduled cron tasks"),
        ("/skills", "Browse and edit agent skills"),
        ("/files", "Browse the agent's file system"),
        ("/clear", "Same as /reset"),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries, id: \.0) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.0)
                            .font(Theme.monoFont(15)).fontWeight(.semibold)
                            .foregroundStyle(Theme.accent)
                        Text(entry.1)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Theme.card)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.medium, .large])
    }
}

