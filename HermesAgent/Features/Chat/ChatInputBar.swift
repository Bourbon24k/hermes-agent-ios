import SwiftUI
import PhotosUI

// MARK: - Slash Command Definition

struct SlashCommand: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let completion: String
}

private let kSlashCommands: [SlashCommand] = [
    SlashCommand(id: "reset",    icon: "square.and.pencil",   title: "/reset",          detail: "Start a new conversation",       completion: "/reset"),
    SlashCommand(id: "model",    icon: "cpu",                  title: "/model",          detail: "Switch AI model",                completion: "/model "),
    SlashCommand(id: "think",    icon: "sparkles",             title: "/think",          detail: "Set thinking level: off/low/medium/high", completion: "/think "),
    SlashCommand(id: "memory",   icon: "brain",                title: "/memory",         detail: "Show agent memory",              completion: "/memory"),
    SlashCommand(id: "sessions", icon: "clock",                title: "/sessions",       detail: "Browse past sessions",           completion: "/sessions"),
    SlashCommand(id: "tasks",    icon: "calendar.badge.clock", title: "/tasks",          detail: "Show scheduled tasks",           completion: "/tasks"),
    SlashCommand(id: "skills",   icon: "hammer.fill",          title: "/skills",         detail: "List available skills",          completion: "/skills"),
    SlashCommand(id: "clear",    icon: "trash",                title: "/clear",          detail: "Clear and archive conversation", completion: "/clear"),
    SlashCommand(id: "help",     icon: "questionmark.circle",  title: "/help",           detail: "Show available commands",        completion: "/help"),
]

struct ChatInputBar: View {
    @Binding var text: String
    let isStreaming: Bool
    let streamingPhase: StreamingPhase
    @Binding var selectedImage: UIImage?
    let onSend: () -> Void
    let onStop: () -> Void
    var onCommand: ((String) -> Void)? = nil

    @Environment(AppState.self) private var appState
    @State private var dictation = DictationManager()
    @State private var showModelPicker = false
    @State private var showThinkingPicker = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var photoPickerItem: PhotosPickerItem?
    @FocusState private var focused: Bool

    private var slashSuggestions: [SlashCommand] {
        guard text.hasPrefix("/") && !text.contains(" ") else { return [] }
        let q = text.lowercased()
        if q == "/" { return kSlashCommands }
        return kSlashCommands.filter { $0.id.hasPrefix(q.dropFirst()) || $0.title.lowercased().hasPrefix(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Slash command suggestions
            if !slashSuggestions.isEmpty {
                slashSuggestionsPanel
            }

            // Text field
            TextField("Ask anything… /commands", text: $text, axis: .vertical)
                .focused($focused)
                .lineLimit(1...6)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
                .tint(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            // Bottom controls row
            HStack(spacing: 0) {
                // Attachment / plus menu
                Menu {
                    Button { showPhotoPicker = true } label: { Label("Photo", systemImage: "photo") }
                    Button { showFilePicker = true } label: { Label("File", systemImage: "doc") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                }

                // Model selector
                Button { showModelPicker = true } label: {
                    HStack(spacing: 4) {
                        Text(shortModelName(appState.selectedModel))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.surfaceElevated, in: Capsule())
                }

                Spacer().frame(width: 6)

                // Thinking level
                Button { showThinkingPicker = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(appState.thinkingBudget == .off ? Theme.textTertiary : Theme.accent)
                        Text(appState.thinkingBudget.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(appState.thinkingBudget == .off ? Theme.textTertiary : Theme.textSecondary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.surfaceElevated, in: Capsule())
                }

                Spacer()

                // Mic
                Button {
                    if dictation.isRecording { dictation.stop() }
                    else { dictation.start { transcript in text = transcript } }
                } label: {
                    Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 17))
                        .foregroundStyle(dictation.isRecording ? Theme.accent : Theme.textSecondary)
                        .frame(width: 34, height: 34)
                }

                // Send / Stop
                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 32, height: 32)
                            .background(Theme.accent, in: Circle())
                    }
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(canSend ? .black : Theme.textTertiary)
                            .frame(width: 32, height: 32)
                            .background(canSend ? Theme.accent : Theme.surfaceElevated, in: Circle())
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.separator, lineWidth: 1))
        .sheet(isPresented: $showModelPicker) { ModelPickerSheet() }
        .sheet(isPresented: $showThinkingPicker) { ThinkingPickerSheet() }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    selectedImage = img
                }
                photoPickerItem = nil
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.item]) { _ in }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var slashSuggestionsPanel: some View {
        VStack(spacing: 0) {
            Divider().background(Theme.separator)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(slashSuggestions) { cmd in
                        Button {
                            applyCommand(cmd)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: cmd.icon)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(cmd.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(cmd.detail)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if cmd.id != slashSuggestions.last?.id {
                            Divider().frame(height: 28)
                        }
                    }
                }
            }
            .background(Theme.surfaceElevated)
        }
    }

    private func applyCommand(_ cmd: SlashCommand) {
        // Commands that execute immediately without text submission
        let immediate = ["reset", "memory", "sessions", "tasks", "skills", "help", "clear"]
        if immediate.contains(cmd.id) {
            text = ""
            onCommand?(cmd.id)
        } else {
            // Partial: fill the text field with the completion for the user to finish
            text = cmd.completion
        }
    }

    private func shortModelName(_ model: String) -> String {
        // "claude-sonnet-4-6" → "Sonnet 4.6"
        let parts = model.split(separator: "-")
        if parts.count >= 3, let first = parts.dropFirst().first {
            let name = first.capitalized
            let ver = parts.dropFirst(2).joined(separator: ".")
            return "\(name) \(ver)"
        }
        return model
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private let models: [(id: String, name: String, subtitle: String)] = [
        ("claude-opus-4-8",    "Claude Opus 4.8",    "@claude-opus-4-8"),
        ("claude-sonnet-4-6",  "Claude Sonnet 4.6",  "@claude-sonnet-4-6"),
        ("claude-haiku-4-5",   "Claude Haiku 4.5",   "@claude-haiku-4-5"),
        ("claude-opus-4-5",    "Claude Opus 4.5",    "@claude-opus-4-5"),
        ("claude-sonnet-4-5",  "Claude Sonnet 4.5",  "@claude-sonnet-4-5"),
        ("claude-opus-4-7",    "Claude Opus 4.7",    "@claude-opus-4-7"),
        ("deepseek-v3",        "DeepSeek V3",        "@deepseek-v3"),
        ("gpt-4o",             "GPT-4o",             "@openai-gpt-4o"),
    ]

    private var filtered: [(id: String, name: String, subtitle: String)] {
        search.isEmpty ? models : models.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                    TextField("Search models", text: $search)
                        .foregroundStyle(Theme.textPrimary).tint(Theme.accent)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)

                List {
                    ForEach(filtered, id: \.id) { model in
                        Button {
                            appState.selectedModel = model.id
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Circle()
                                    .strokeBorder(appState.selectedModel == model.id ? Theme.accent : Theme.separator, lineWidth: 2)
                                    .background(Circle().fill(appState.selectedModel == model.id ? Theme.accent.opacity(0.15) : Color.clear))
                                    .frame(width: 22, height: 22)
                                    .overlay {
                                        if appState.selectedModel == model.id {
                                            Circle().fill(Theme.accent).frame(width: 10, height: 10)
                                        }
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(model.subtitle)
                                        .font(Theme.monoFont(12))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.card)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .background(Theme.background)
            .navigationTitle("Choose Model")
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

// MARK: - Thinking Picker Sheet

struct ThinkingPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(ThinkingBudget.allCases) { budget in
                    Button {
                        appState.thinkingBudget = budget
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .strokeBorder(appState.thinkingBudget == budget ? Theme.accent : Theme.separator, lineWidth: 2)
                                .background(Circle().fill(appState.thinkingBudget == budget ? Theme.accent.opacity(0.15) : Color.clear))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if appState.thinkingBudget == budget {
                                        Circle().fill(Theme.accent).frame(width: 10, height: 10)
                                    }
                                }
                            Image(systemName: budget.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(budget == .off ? Theme.textTertiary : Theme.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(budget.displayName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                if let tokens = budget.tokenBudget {
                                    Text("\(tokens) tokens budget")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.textTertiary)
                                } else {
                                    Text("Extended thinking disabled")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Theme.card)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Thinking Level")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.medium])
    }
}
