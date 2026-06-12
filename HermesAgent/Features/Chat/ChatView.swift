import SwiftUI
import UIKit

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: ChatViewModel
    @State private var inputText = ""
    @State private var showSettings = false
    @State private var showClearConfirm = false
    @State private var pendingImage: UIImage?
    @State private var slashCommandAlert: String?

    init(api: RelayAPI) {
        _viewModel = State(initialValue: ChatViewModel(api: api))
    }

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
                    showClearConfirm = true
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
        .task { await viewModel.load() }
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
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: viewModel.messages.last?.content) {
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: viewModel.messages.count) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34))
                .foregroundStyle(Theme.textTertiary)
            Text("Send a message to start the conversation.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Slash command handling

    private func handleSlashCommand(_ cmd: String) async {
        switch cmd {
        case "reset", "clear":
            await viewModel.clear()
        case "memory":
            await viewModel.send(text: "/memory", model: appState.selectedModel, thinking: appState.thinkingBudget)
        case "sessions":
            await viewModel.send(text: "/sessions", model: appState.selectedModel, thinking: appState.thinkingBudget)
        case "tasks":
            await viewModel.send(text: "/tasks", model: appState.selectedModel, thinking: appState.thinkingBudget)
        case "skills":
            await viewModel.send(text: "/skills", model: appState.selectedModel, thinking: appState.thinkingBudget)
        case "help":
            await viewModel.send(text: "/help", model: appState.selectedModel, thinking: appState.thinkingBudget)
        default:
            break
        }
    }
}
