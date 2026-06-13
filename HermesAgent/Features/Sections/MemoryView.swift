import SwiftUI

struct MemoryView: View {
    @Environment(AppState.self) private var appState
    @State private var memory: AgentMemory?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var editState: MemoryEditState?
    @State private var expandedKeys: Set<String> = []
    @State private var extraFiles: [DiscoveredMemoryFile] = []

    /// Lines shown in collapsed mode before "Show more" appears.
    private let collapsedLineCount = 10

    private let memoryFiles: [(key: String, title: String, icon: String)] = [
        ("memory",   "MEMORY.md",   "brain"),
        ("user",     "USER.md",     "person.fill"),
        ("agents",   "AGENTS.md",   "cpu"),
        ("identity", "IDENTITY.md", "person.badge.key"),
        ("tools",    "TOOLS.md",    "wrench"),
        ("context",  "CONTEXT.md",  "doc.text"),
        ("custom",   "CUSTOM.md",   "star"),
    ]

    /// Known filenames from `memoryFiles` so we can skip them in discovery.
    private var knownFilenames: Set<String> {
        Set(memoryFiles.map(\.title))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let memory {
                    ForEach(memoryFiles, id: \.key) { file in
                        memorySection(
                            key: file.key,
                            title: file.title,
                            icon: file.icon,
                            content: knownFileContent(key: file.key, memory: memory)
                        )
                    }
                    if let status = memory.status, !status.isEmpty {
                        statusSection(status)
                    }
                } else if !isLoading {
                    Text("No memory data.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }

                // Discovered extra .md files from ~/.hermes/memory/
                if !extraFiles.isEmpty {
                    extraFilesHeader
                    ForEach(extraFiles) { file in
                        memorySection(
                            key: file.id,
                            title: file.name,
                            icon: "doc.text.fill",
                            content: file.content
                        )
                    }
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

    // MARK: - Content resolvers

    private func knownFileContent(key: String, memory: AgentMemory) -> String? {
        switch key {
        case "memory":   return memory.memory
        case "user":     return memory.user
        case "agents":   return memory.agents
        case "identity": return memory.identity
        default:         return nil // TOOLS, CONTEXT, CUSTOM – not in AgentMemory
        }
    }

    // MARK: - Memory card

    private func memorySection(key: String, title: String, icon: String, content: String?) -> some View {
        let isExpanded = expandedKeys.contains(key)
        let lines = content?.components(separatedBy: .newlines) ?? []
        let needsTruncation = lines.count > collapsedLineCount
        let displayText: String? = {
            guard let content, !content.isEmpty else { return nil }
            if !needsTruncation || isExpanded { return content }
            return lines.prefix(collapsedLineCount).joined(separator: "\n")
        }()

        return VStack(alignment: .leading, spacing: 0) {
            // Header
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

            // Body
            if let displayText {
                Text(displayText)
                    .font(Theme.monoFont(12)).foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if needsTruncation {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if isExpanded { expandedKeys.remove(key) }
                            else { expandedKeys.insert(key) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Show less" : "Show more (\(lines.count - collapsedLineCount) lines)")
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 14).padding(.bottom, 12)
                    }
                    .buttonStyle(.plain)
                }
            } else if content == nil {
                Text("Not configured")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textTertiary)
                    .padding(14)
            } else {
                Text("Empty")
                    .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                    .padding(14)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.separator, lineWidth: 1))
    }

    // MARK: - Extra files header

    private var extraFilesHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            Text("Additional Memory Files")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Status

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

    // MARK: - Save

    private func save(key: String, content: String) async {
        do {
            // Extra discovered files use file path as key – save via file API
            if key.hasPrefix("~/.hermes/") {
                try await appState.agent.saveFileContent(path: key, content: content)
            } else {
                try await appState.agent.saveMemory(key: key, content: content)
            }
            editState = nil
            await load()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Load

    private func load() async {
        isLoading = true; errorText = nil
        do { memory = try await appState.agent.memory() } catch { errorText = error.localizedDescription }
        await loadExtraFiles()
        isLoading = false
    }

    /// Discover additional .md files from ~/.hermes/memory/ that aren't in the known set.
    private func loadExtraFiles() async {
        do {
            let listing = try await appState.agent.files(path: "~/.hermes/memory")
            let mdEntries = listing.entries.filter { entry in
                !entry.isDirectory
                && entry.name.hasSuffix(".md")
                && !knownFilenames.contains(entry.name)
            }

            var discovered: [DiscoveredMemoryFile] = []
            for entry in mdEntries {
                let path = "~/.hermes/memory/\(entry.name)"
                let content: String? = try? await appState.agent.fileContent(path: path).content
                discovered.append(DiscoveredMemoryFile(name: entry.name, path: path, content: content))
            }
            extraFiles = discovered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            // Discovery is best-effort — silently ignore failures
            extraFiles = []
        }
    }

}

// MARK: - Discovered file model

private struct DiscoveredMemoryFile: Identifiable {
    let name: String
    let path: String
    let content: String?
    var id: String { path }
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
