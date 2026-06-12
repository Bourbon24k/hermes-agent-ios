import SwiftUI

struct MemoryView: View {
    @Environment(AppState.self) private var appState
    @State private var memory: AgentMemory?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var editState: MemoryEditState?

    private let memoryFiles: [(key: String, title: String, icon: String)] = [
        ("memory",   "MEMORY.md",   "brain"),
        ("user",     "USER.md",     "person.fill"),
        ("agents",   "AGENTS.md",   "cpu"),
        ("identity", "IDENTITY.md", "person.badge.key"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let memory {
                    ForEach(memoryFiles, id: \.key) { file in
                        memorySection(key: file.key, title: file.title, icon: file.icon,
                                      content: fileContent(key: file.key, memory: memory))
                    }
                    if let status = memory.status, !status.isEmpty {
                        statusSection(status)
                    }
                } else if !isLoading {
                    Text("No memory data.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.failure)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView().tint(Theme.accent) } }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $editState) { state in
            MemoryEditSheet(state: state, onSave: { key, content in
                Task { await save(key: key, content: content) }
            })
        }
    }

    private func fileContent(key: String, memory: AgentMemory) -> String? {
        switch key {
        case "memory":   return memory.memory
        case "user":     return memory.user
        case "agents":   return memory.agents
        case "identity": return memory.identity
        default:         return nil
        }
    }

    private func memorySection(key: String, title: String, icon: String, content: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Theme.accent)
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
                Spacer()
                Button {
                    editState = MemoryEditState(key: key, title: title, content: content ?? "")
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)

            Divider().overlay(Theme.separator)

            if let content, !content.isEmpty {
                Text(content)
                    .font(Theme.monoFont(12)).foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(20)
            } else {
                Text("Empty")
                    .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    .padding(14)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.separator, lineWidth: 1))
    }

    private func statusSection(_ status: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Memory Status", systemImage: "info.circle")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text(status)
                .font(Theme.monoFont(11)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private func save(key: String, content: String) async {
        do {
            try await appState.agent.saveMemory(key: key, content: content)
            editState = nil
            await load()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true; errorText = nil
        do { memory = try await appState.agent.memory() } catch { errorText = error.localizedDescription }
        isLoading = false
    }
}

// MARK: - Edit state model

struct MemoryEditState: Identifiable {
    let id = UUID()
    let key: String
    let title: String
    var content: String
}

// MARK: - Edit sheet

struct MemoryEditSheet: View {
    let state: MemoryEditState
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false

    init(state: MemoryEditState, onSave: @escaping (String, String) -> Void) {
        self.state = state
        self.onSave = onSave
        _text = State(initialValue: state.content)
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(Theme.monoFont(13))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .tint(Theme.accent)
                .padding(.horizontal, 12)
                .navigationTitle(state.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isSaving = true
                            onSave(state.key, text)
                            dismiss()
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
        }
        .presentationBackground(Theme.background)
    }
}
