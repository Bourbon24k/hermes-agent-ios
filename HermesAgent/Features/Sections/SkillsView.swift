import SwiftUI

struct SkillsView: View {
    @Environment(AppState.self) private var appState
    @State private var skills: [AgentSkill] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var search = ""
    @State private var selectedSkill: AgentSkill?
    @State private var showCreate = false

    private var grouped: [(category: String, skills: [AgentSkill])] {
        let filtered = search.isEmpty ? skills : skills.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            ($0.description ?? "").localizedCaseInsensitiveContains(search) ||
            ($0.category ?? "").localizedCaseInsensitiveContains(search)
        }
        let byCategory = Dictionary(grouping: filtered) { $0.category ?? "general" }
        return byCategory.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                TextField("Search skills…", text: $search)
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
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

            if isLoading {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(grouped, id: \.category) { group in
                        Section {
                            ForEach(group.skills) { skill in skillRow(skill) }
                        } header: {
                            Text(group.category.uppercased())
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    if let errorText {
                        Text(errorText).font(.footnote).foregroundStyle(Theme.failure)
                            .listRowBackground(Theme.background)
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .refreshable { await load() }
            }
        }
        .background(Theme.background)
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 2) {
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise").foregroundStyle(Theme.textSecondary)
                    }
                    Button { showCreate = true } label: {
                        Image(systemName: "plus").foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .task { await load() }
        .sheet(item: $selectedSkill) { skill in
            SkillDetailSheet(skill: skill)
        }
        .sheet(isPresented: $showCreate) {
            CreateSkillSheet { await load() }
        }
    }

    private func skillRow(_ skill: AgentSkill) -> some View {
        Button { selectedSkill = skill } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.surfaceElevated).frame(width: 42, height: 42)
                    Image(systemName: "hammer.fill").font(.system(size: 16)).foregroundStyle(Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(skill.name)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    if let desc = skill.description, !desc.isEmpty {
                        Text(desc).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.background)
        .listRowSeparator(.visible)
        .listRowSeparatorTint(Theme.separator)
    }

    private func load() async {
        isLoading = true; errorText = nil
        do { skills = try await appState.agent.skills() } catch { if !error.isCancellation { errorText = error.localizedDescription } }
        isLoading = false
    }
}

// MARK: - Skill Detail Sheet

struct SkillDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let skill: AgentSkill

    @State private var fileContent: String?
    @State private var editedContent: String = ""
    @State private var isEditing = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorText: String?

    private var skillPath: String {
        if let p = skill.path { return p }
        let cat = skill.category ?? "general"
        return "~/.hermes/skills/\(cat)/\(skill.name)/SKILL.md"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                // Header info
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Theme.surfaceElevated).frame(width: 44, height: 44)
                            Image(systemName: "hammer.fill").font(.system(size: 18)).foregroundStyle(Theme.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill.name)
                                .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                            if let cat = skill.category {
                                Text(cat.uppercased())
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Spacer()
                    }
                    if let desc = skill.description, !desc.isEmpty {
                        Text(desc).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                    }
                    Text(skillPath)
                        .font(Theme.monoFont(11)).foregroundStyle(Theme.textTertiary)
                        .lineLimit(2)
                }
                .padding(16)

                Divider().background(Theme.separator)

                if isLoading {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isEditing {
                    TextEditor(text: $editedContent)
                        .font(Theme.monoFont(13))
                        .foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .background(Theme.background)
                        .padding(8)
                } else {
                    ScrollView {
                        Text(fileContent ?? "(empty)")
                            .font(Theme.monoFont(13))
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Theme.background)
                }

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.failure).padding()
                }
            }
            .background(Theme.background)
            .navigationTitle("Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button {
                            Task { await saveEdit() }
                        } label: {
                            if isSaving {
                                ProgressView().controlSize(.small).tint(Theme.accent)
                            } else {
                                Text("Save").fontWeight(.semibold).foregroundStyle(Theme.accent)
                            }
                        }
                        .disabled(isSaving)
                    } else {
                        Button {
                            editedContent = fileContent ?? ""
                            isEditing = true
                        } label: {
                            Label("Edit", systemImage: "pencil").foregroundStyle(Theme.accent)
                        }
                        .disabled(fileContent == nil)
                    }
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.large])
        .task { await loadFile() }
    }

    private func loadFile() async {
        isLoading = true; errorText = nil
        do {
            let result = try await appState.agent.fileContent(path: skillPath)
            fileContent = result.content
            if let err = result.error { errorText = err }
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
        }
        isLoading = false
    }

    private func saveEdit() async {
        isSaving = true; errorText = nil
        do {
            try await appState.agent.saveFileContent(path: skillPath, content: editedContent)
            fileContent = editedContent
            isEditing = false
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
        }
        isSaving = false
    }
}


// MARK: - Create Skill Sheet

struct CreateSkillSheet: View {
    let onCreated: () async -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category = "general"
    @State private var descriptionText = ""
    @State private var content = ""
    @State private var isSaving = false
    @State private var errorText: String?

    private var slug: String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    private var canCreate: Bool {
        !slug.isEmpty && !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Skill") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        TextField("my-skill", text: $name)
                            .font(.system(size: 16)).foregroundStyle(Theme.textPrimary)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    .listRowBackground(Theme.card)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Category").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        TextField("general", text: $category)
                            .font(.system(size: 16)).foregroundStyle(Theme.textPrimary)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    .listRowBackground(Theme.card)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        TextField("What this skill does", text: $descriptionText, axis: .vertical)
                            .lineLimit(2...4)
                            .font(.system(size: 15)).foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)
                }

                Section("Instructions (markdown)") {
                    TextEditor(text: $content)
                        .font(Theme.monoFont(13)).foregroundStyle(Theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                        .listRowBackground(Theme.card)
                }

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Theme.failure)
                        .listRowBackground(Theme.background)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("New Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await create() }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        } else {
                            Text("Create").fontWeight(.semibold)
                                .foregroundStyle(canCreate ? Theme.accent : Theme.textTertiary)
                        }
                    }
                    .disabled(!canCreate || isSaving)
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.large])
    }

    private func create() async {
        isSaving = true; errorText = nil
        let cat = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "general" : category
        let body = """
        ---
        name: \(slug)
        description: "\(descriptionText.replacingOccurrences(of: "\"", with: "'"))"
        ---

        \(content.isEmpty ? "# \(name)\n\nInstructions for the agent." : content)
        """
        do {
            try await appState.agent.saveFileContent(path: ".hermes/skills/\(cat)/\(slug)/SKILL.md", content: body)
            Haptics.success()
            await onCreated()
            dismiss()
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
            Haptics.error()
        }
        isSaving = false
    }
}
