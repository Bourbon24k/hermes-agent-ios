import SwiftUI

struct FilesView: View {
    @Environment(AppState.self) private var appState
    @State private var path = ""
    @State private var entries: [AgentFileEntry] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var search = ""
    @State private var fileToView: AgentFileEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            locationBar
            searchField
            list
        }
        .padding(.horizontal, 16)
        .background(Theme.background)
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $fileToView) { entry in
            FileContentView(path: fullPath(entry.name), filename: entry.name)
        }
    }

    private var locationBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Location").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                Text(path.isEmpty ? "Root" : path)
                    .font(Theme.monoFont(12)).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).truncationMode(.head)
            }
            HStack(spacing: 8) {
                Button { path = ""; Task { await load() } } label: { PillLabel(text: "Root", icon: "house") }
                Button { goUp() } label: { PillLabel(text: "Up", icon: "arrow.up") }
                    .disabled(path.isEmpty).opacity(path.isEmpty ? 0.4 : 1)
            }
        }
        .padding(.top, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
            TextField("Search files", text: $search).foregroundStyle(Theme.textPrimary).tint(Theme.accent)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private var filtered: [AgentFileEntry] {
        search.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var list: some View {
        List {
            ForEach(filtered) { entry in
                Button {
                    if entry.isDirectory {
                        path = fullPath(entry.name)
                        Task { await load() }
                    } else {
                        fileToView = entry
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                            .font(.system(size: 16)).foregroundStyle(entry.isDirectory ? Theme.accent : Theme.textSecondary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            if let size = entry.size, !entry.isDirectory {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Spacer()
                        if entry.isDirectory {
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Theme.background)
            }
            if let errorText { Text(errorText).font(.footnote).foregroundStyle(Theme.failure).listRowBackground(Theme.background) }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .overlay { if isLoading { ProgressView().tint(Theme.accent) } }
        .refreshable { await load() }
    }

    private func fullPath(_ name: String) -> String {
        path.isEmpty ? name : "\(path)/\(name)"
    }

    private func goUp() {
        guard !path.isEmpty else { return }
        var parts = path.split(separator: "/").map(String.init)
        parts.removeLast()
        path = parts.joined(separator: "/")
        Task { await load() }
    }

    private func load() async {
        isLoading = true; errorText = nil
        do {
            let listing = try await appState.agent.files(path: path)
            entries = listing.entries
            path = listing.path
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
        }
        isLoading = false
    }
}

struct FileContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let path: String
    let filename: String
    @State private var content: String?
    @State private var errorText: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView([.vertical, .horizontal]) {
                if let content {
                    Text(content)
                        .font(Theme.monoFont(12)).foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let errorText {
                    Text(errorText).font(.subheadline).foregroundStyle(Theme.failure).padding(40)
                }
            }
            .background(Theme.background)
            .navigationTitle(filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let content {
                        ShareLink(item: content, preview: SharePreview(filename)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .foregroundStyle(Theme.accent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.accent) }
            }
            .overlay { if isLoading { ProgressView().tint(Theme.accent) } }
            .task {
                do {
                    let result = try await appState.agent.fileContent(path: path)
                    content = result.content
                    errorText = result.error.map { "Cannot open: \($0)" }
                } catch {
                    if !error.isCancellation { errorText = error.localizedDescription }
                }
                isLoading = false
            }
        }
    }
}
