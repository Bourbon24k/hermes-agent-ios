import SwiftUI

struct ProfilesView: View {
    @Environment(AppState.self) private var appState
    @State private var profiles: [AgentProfile] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var activatingName: String?
    @State private var showCreate = false
    @State private var profileToRename: AgentProfile?
    @State private var profileToDelete: AgentProfile?
    @State private var detailProfile: AgentProfile?

    var body: some View {
        List {
            if profiles.isEmpty && !isLoading {
                Text("No profiles found.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Theme.background)
            }
            ForEach(profiles) { profile in
                row(profile)
            }
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(Theme.failure)
                    .listRowBackground(Theme.background)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Profiles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus").foregroundStyle(Theme.accent)
                }
            }
        }
        .overlay { if isLoading && profiles.isEmpty { ProgressView().tint(Theme.accent) } }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            CreateProfileSheet { name, description in
                await create(name: name, description: description)
            }
        }
        .sheet(item: $profileToRename) { profile in
            RenameProfileSheet(profile: profile) { newName in
                await rename(profile, to: newName)
            }
        }
        .sheet(item: $detailProfile) { profile in
            ProfileDetailSheet(profile: profile)
        }
        .confirmationDialog(
            "Delete profile \"\(profileToDelete?.name ?? "")\"? This removes its home directory.",
            isPresented: Binding(get: { profileToDelete != nil }, set: { if !$0 { profileToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let p = profileToDelete { Task { await delete(p) } }
            }
        }
    }

    private func row(_ profile: AgentProfile) -> some View {
        Button { detailProfile = profile } label: {
            HStack(spacing: 12) {
                Text(String(profile.name.prefix(2)).uppercased())
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(profile.active == true ? Theme.accent : Theme.textTertiary, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    if profile.active == true {
                        Text("Active").font(.system(size: 12)).foregroundStyle(Theme.success)
                    }
                }
                Spacer()

                if profile.active == true {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                } else {
                    Button {
                        Task { await activate(name: profile.name) }
                    } label: {
                        if activatingName == profile.name {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        } else {
                            Text("Use")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Theme.accent.opacity(0.12), in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(activatingName != nil)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.card)
        .contextMenu {
            Button { profileToRename = profile } label: { Label("Rename", systemImage: "pencil") }
            if profile.active != true {
                Button(role: .destructive) { profileToDelete = profile } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    private func load() async {
        isLoading = true; errorText = nil
        do { profiles = try await appState.agent.profiles() } catch { if !error.isCancellation { errorText = error.localizedDescription } }
        isLoading = false
    }

    private func activate(name: String) async {
        activatingName = name; errorText = nil
        do {
            try await appState.agent.useProfile(name: name)
            Haptics.success()
            await load()
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
            Haptics.error()
        }
        activatingName = nil
    }

    private func create(name: String, description: String) async {
        do {
            try await appState.agent.createProfile(name: name, description: description.isEmpty ? nil : description)
            Haptics.success()
            await load()
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
            Haptics.error()
        }
    }

    private func rename(_ profile: AgentProfile, to newName: String) async {
        do {
            try await appState.agent.renameProfile(profile.name, to: newName)
            Haptics.success()
            await load()
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
            Haptics.error()
        }
    }

    private func delete(_ profile: AgentProfile) async {
        do {
            try await appState.agent.deleteProfile(name: profile.name)
            Haptics.success()
            await load()
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
            Haptics.error()
        }
        profileToDelete = nil
    }
}

// MARK: - Create Profile Sheet

struct CreateProfileSheet: View {
    let onCreate: (String, String) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var descriptionText = ""
    @State private var isCreating = false

    private var slug: String {
        name.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("New Profile") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name (lowercase, alphanumeric)").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        TextField("work", text: $name)
                            .font(.system(size: 16)).foregroundStyle(Theme.textPrimary)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                    }
                    .listRowBackground(Theme.card)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description (optional)").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        TextField("Agent for work tasks", text: $descriptionText, axis: .vertical)
                            .lineLimit(2...4)
                            .font(.system(size: 15)).foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                        Task {
                            await onCreate(slug, descriptionText)
                            dismiss()
                        }
                    } label: {
                        if isCreating {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        } else {
                            Text("Create").fontWeight(.semibold)
                                .foregroundStyle(slug.isEmpty ? Theme.textTertiary : Theme.accent)
                        }
                    }
                    .disabled(slug.isEmpty || isCreating)
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.medium])
    }
}

// MARK: - Rename Profile Sheet

struct RenameProfileSheet: View {
    let profile: AgentProfile
    let onRename: (String) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var isSaving = false

    init(profile: AgentProfile, onRename: @escaping (String) async -> Void) {
        self.profile = profile
        self.onRename = onRename
        _name = State(initialValue: profile.name)
    }

    private var slug: String {
        name.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Rename \(profile.name)") {
                    TextField("new name", text: $name)
                        .font(.system(size: 16)).foregroundStyle(Theme.textPrimary)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Rename Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSaving = true
                        Task {
                            await onRename(slug)
                            dismiss()
                        }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        } else {
                            Text("Save").fontWeight(.semibold)
                                .foregroundStyle(slug.isEmpty || slug == profile.name ? Theme.textTertiary : Theme.accent)
                        }
                    }
                    .disabled(slug.isEmpty || slug == profile.name || isSaving)
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.medium])
    }
}

// MARK: - Profile Detail Sheet

struct ProfileDetailSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let profile: AgentProfile

    @State private var details: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Text(String(profile.name.prefix(2)).uppercased())
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 48, height: 48)
                            .background(profile.active == true ? Theme.accent : Theme.textTertiary, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.textPrimary)
                            Text(profile.active == true ? "Active profile" : "Inactive")
                                .font(.system(size: 13))
                                .foregroundStyle(profile.active == true ? Theme.success : Theme.textTertiary)
                        }
                        Spacer()
                    }

                    if isLoading {
                        ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 30)
                    } else if let details, !details.isEmpty {
                        Text(details)
                            .font(Theme.monoFont(12))
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        Text("No details available.")
                            .font(.subheadline).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.medium, .large])
        .task {
            details = (try? await appState.agent.profileDetails(name: profile.name))?.details
            isLoading = false
        }
    }
}
