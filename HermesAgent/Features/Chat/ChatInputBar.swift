import SwiftUI
import PhotosUI
import UIKit

// MARK: - Slash Command Definition

struct SlashCommand: Identifiable {
    let id: String
    let icon: String
    let title: String
    let detail: String
    let completion: String
}

private let kSlashCommands: [SlashCommand] = [
    SlashCommand(id: "reset",    icon: "square.and.pencil",   title: "/reset",    detail: "Start a new conversation",       completion: "/reset"),
    SlashCommand(id: "model",    icon: "cpu",                  title: "/model",    detail: "Switch AI model",                completion: "/model"),
    SlashCommand(id: "think",    icon: "sparkles",             title: "/think",    detail: "Set reasoning level",            completion: "/think"),
    SlashCommand(id: "memory",   icon: "brain",                title: "/memory",   detail: "View & edit agent memory",       completion: "/memory"),
    SlashCommand(id: "sessions", icon: "clock",                title: "/sessions", detail: "Browse past sessions",           completion: "/sessions"),
    SlashCommand(id: "tasks",    icon: "calendar.badge.clock", title: "/tasks",    detail: "Scheduled tasks",                completion: "/tasks"),
    SlashCommand(id: "skills",   icon: "hammer.fill",          title: "/skills",   detail: "Available skills",               completion: "/skills"),
    SlashCommand(id: "files",    icon: "folder",               title: "/files",    detail: "Browse agent files",             completion: "/files"),
    SlashCommand(id: "clear",    icon: "trash",                title: "/clear",    detail: "Clear and archive conversation", completion: "/clear"),
    SlashCommand(id: "help",     icon: "questionmark.circle",  title: "/help",     detail: "Show available commands",        completion: "/help"),
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
    @State private var showCamera = false
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
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera") }
                    }
                    Button { showPhotoPicker = true } label: { Label("Photo Library", systemImage: "photo") }
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
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result {
                let needsScope = url.startAccessingSecurityScopedResource()
                defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                    selectedImage = img
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let image { selectedImage = image }
            }
            .ignoresSafeArea()
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedImage != nil
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
        Haptics.selection()
        text = ""
        switch cmd.id {
        case "model":
            showModelPicker = true
        case "think":
            showThinkingPicker = true
        default:
            onCommand?(cmd.id)
        }
    }

    private func shortModelName(_ model: String) -> String {
        // "anthropic/claude-sonnet-4.6" → "Claude Sonnet 4.6"
        // "nvidia/nemotron-3-super-120b-a12b" → "Nemotron 3 Super"
        let raw = model.split(separator: "/").last.map(String.init) ?? model
        let words = raw.split(separator: "-").map(String.init)
        let pretty = words.prefix(3).map { w in
            w.first.map { String($0).uppercased() + w.dropFirst() } ?? w
        }
        return pretty.joined(separator: " ")
    }
}

// MARK: - Model Picker Sheet

struct ModelPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var models: [AgentModel] = []
    @State private var currentModel: String?
    @State private var isLoading = true
    @State private var switchingId: String?
    @State private var errorText: String?

    private var filtered: [AgentModel] {
        search.isEmpty ? models : models.filter {
            $0.displayName.localizedCaseInsensitiveContains(search) ||
            $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    /// Models grouped by provider, current provider's group first.
    private var groupedByProvider: [(provider: String, models: [AgentModel])] {
        let groups = Dictionary(grouping: filtered) { $0.provider ?? "other" }
        let currentProv = models.first(where: { $0.id == currentModel })?.provider
        return groups.sorted { a, b in
            if a.key == currentProv { return true }
            if b.key == currentProv { return false }
            return a.key < b.key
        }.map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                    TextField("Search models", text: $search)
                        .foregroundStyle(Theme.textPrimary).tint(Theme.accent)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)

                if let errorText {
                    Text(errorText)
                        .font(.footnote).foregroundStyle(Theme.failure)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isLoading {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedByProvider, id: \.provider) { group in
                            Section {
                                ForEach(group.models) { model in
                                    modelRow(model)
                                }
                            } header: {
                                Text(group.provider.uppercased())
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
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
        .task { await load() }
    }

    private func modelRow(_ model: AgentModel) -> some View {
        let isSelected = currentModel == model.id
        return Button {
            Task { await select(model) }
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .strokeBorder(isSelected ? Theme.accent : Theme.separator, lineWidth: 2)
                    .background(Circle().fill(isSelected ? Theme.accent.opacity(0.15) : Color.clear))
                    .frame(width: 22, height: 22)
                    .overlay {
                        if isSelected {
                            Circle().fill(Theme.accent).frame(width: 10, height: 10)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        Text(model.id)
                            .font(Theme.monoFont(12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                        if let provider = model.provider {
                            Text(provider)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.accent.opacity(0.12), in: Capsule())
                        }
                    }
                }
                Spacer()
                if switchingId == model.id {
                    ProgressView().controlSize(.small).tint(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(switchingId != nil)
        .listRowBackground(Theme.card)
    }

    private func load() async {
        isLoading = true; errorText = nil
        do {
            let resp = try await appState.agent.models()
            models = resp.models
            currentModel = resp.current.model
            if let m = resp.current.model { appState.selectedModel = m }
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
        }
        isLoading = false
    }

    private func select(_ model: AgentModel) async {
        guard model.id != currentModel else { dismiss(); return }
        switchingId = model.id; errorText = nil
        do {
            try await appState.agent.setModel(model.id, provider: model.provider)
            currentModel = model.id
            appState.selectedModel = model.id
            Haptics.success()
            dismiss()
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
            Haptics.error()
        }
        switchingId = nil
    }
}

// MARK: - Thinking Picker Sheet

struct ThinkingPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var savingBudget: ThinkingBudget?

    var body: some View {
        NavigationStack {
            List {
                ForEach(ThinkingBudget.allCases) { budget in
                    Button {
                        savingBudget = budget
                        Task {
                            // Apply to the agent host (agent.reasoning_effort); keep local copy regardless.
                            try? await appState.agent.setReasoning(budget.rawValue)
                            appState.thinkingBudget = budget
                            savingBudget = nil
                            dismiss()
                        }
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
                            if savingBudget == budget {
                                ProgressView().controlSize(.small).tint(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(savingBudget != nil)
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
