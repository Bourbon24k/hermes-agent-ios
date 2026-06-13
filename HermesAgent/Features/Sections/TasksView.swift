import SwiftUI

struct TasksView: View {
    @Environment(AppState.self) private var appState
    @State private var jobs: [AgentCronJob] = []
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var showCreate = false
    @State private var jobToEdit: AgentCronJob?

    private var runningCount: Int { jobs.filter { $0.state == "running" }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                runningBanner
                sectionHeader

                if jobs.isEmpty && !isLoading {
                    emptyState
                }
                ForEach(jobs) { job in jobCard(job) }
                if let errorText { Text(errorText).font(.footnote).foregroundStyle(Theme.failure) }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus").foregroundStyle(Theme.accent)
                }
            }
        }
        .overlay { if isLoading { ProgressView().tint(Theme.accent) } }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            CreateTaskSheet { name, prompt, schedule in
                Task { await createJob(name: name, prompt: prompt, schedule: schedule) }
            }
        }
        .sheet(item: $jobToEdit) { job in
            EditTaskSheet(job: job) { name, prompt, schedule in
                Task { await editJob(job: job, name: name, prompt: prompt, schedule: schedule) }
            }
        }
    }

    private var runningBanner: some View {
        HStack {
            Image(systemName: "bolt.fill").foregroundStyle(Color(red: 0.2, green: 0.55, blue: 1.0))
            Text("Running now").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(runningCount)").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 16))
        .padding(.top, 8)
    }

    private var sectionHeader: some View {
        HStack {
            Text("Scheduled Jobs")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { showCreate = true } label: {
                Label("New Task", systemImage: "plus").font(.system(size: 13)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 32)).foregroundStyle(Theme.textTertiary)
            Text("No scheduled tasks.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
            Text("Tap + to create one or use `hermes cron add` in terminal.")
                .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 32)
    }

    private func jobCard(_ job: AgentCronJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(job.name ?? job.id)
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                statusBadge(job)
            }
            if let prompt = job.prompt ?? job.script {
                Text(prompt).font(.system(size: 14)).foregroundStyle(Theme.textSecondary).lineLimit(3)
            }
            VStack(spacing: 6) {
                if let schedule = job.schedule { infoRow("Schedule", schedule, mono: true) }
                if let next = job.nextRunAt?.iso8601Date { infoRow("Next", next.formatted(date: .abbreviated, time: .shortened)) }
                if let last = job.lastRunAt?.iso8601Date { infoRow("Last", last.formatted(date: .abbreviated, time: .shortened)) }
                if let deliver = job.deliver { infoRow("Deliver", deliver) }
                if let skills = job.skills, !skills.isEmpty { infoRow("Skills", skills.joined(separator: ", ")) }
                if let model = job.model { infoRow("Model", model) }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            Button { Task { await action(job, "run") } } label: { Label("Run now", systemImage: "play.fill") }
            if job.paused == true {
                Button { Task { await action(job, "resume") } } label: { Label("Resume", systemImage: "play.circle") }
            } else {
                Button { Task { await action(job, "pause") } } label: { Label("Pause", systemImage: "pause.circle") }
            }
            Button { jobToEdit = job } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { Task { await action(job, "delete") } } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func statusBadge(_ job: AgentCronJob) -> some View {
        let paused = job.paused == true || job.enabled == false
        let label = paused ? "Paused" : (job.state == "running" ? "Running" : "Active")
        let color = paused ? Theme.textTertiary : Theme.success
        return Text(label)
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.textTertiary).frame(width: 70, alignment: .leading)
            Text(value)
                .font(mono ? Theme.monoFont(13) : .system(size: 13))
                .foregroundStyle(mono ? Theme.accent : Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func action(_ job: AgentCronJob, _ action: String) async {
        try? await appState.agent.cronAction(jobId: job.id, action: action)
        await load()
    }

    private func createJob(name: String, prompt: String, schedule: String) async {
        do {
            try await appState.agent.createCronJob(name: name, prompt: prompt, schedule: schedule)
            await load()
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
        }
    }

    private func editJob(job: AgentCronJob, name: String, prompt: String, schedule: String) async {
        do {
            try await appState.agent.editCronJob(oldId: job.id, name: name, prompt: prompt, schedule: schedule)
            await load()
        } catch {
            if !error.isCancellation { errorText = error.localizedDescription }
        }
    }

    private func load() async {
        isLoading = true; errorText = nil
        do { jobs = try await appState.agent.cron() } catch { if !error.isCancellation { errorText = error.localizedDescription } }
        isLoading = false
    }
}

// MARK: - Create Task Sheet

struct CreateTaskSheet: View {
    let onCreate: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var prompt = ""
    @State private var schedule = "0 9 * * *"
    @State private var isCreating = false

    private let schedulePresets = [
        ("Every day 9am", "0 9 * * *"),
        ("Every hour",    "0 * * * *"),
        ("Every Monday",  "0 9 * * 1"),
        ("Every 6 hours", "0 */6 * * *"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Job Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        TextField("Daily summary", text: $name)
                            .font(.system(size: 16)).foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prompt").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        TextEditor(text: $prompt)
                            .font(.system(size: 15)).foregroundStyle(Theme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .frame(minHeight: 80)
                    }
                    .listRowBackground(Theme.card)
                }

                Section("Schedule (cron)") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("0 9 * * *", text: $schedule)
                            .font(Theme.monoFont(15)).foregroundStyle(Theme.accent)
                        Text("Use standard cron format: min hour day month weekday")
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    }
                    .listRowBackground(Theme.card)

                    ForEach(schedulePresets, id: \.1) { preset in
                        Button {
                            schedule = preset.1
                        } label: {
                            HStack {
                                Text(preset.0).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(preset.1).font(Theme.monoFont(12)).foregroundStyle(Theme.textTertiary)
                                if schedule == preset.1 {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .listRowBackground(Theme.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                        onCreate(name, prompt, schedule)
                        dismiss()
                    } label: {
                        if isCreating {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        } else {
                            Text("Create").fontWeight(.semibold).foregroundStyle(canCreate ? Theme.accent : Theme.textTertiary)
                        }
                    }
                    .disabled(!canCreate || isCreating)
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.large])
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Edit Task Sheet

struct EditTaskSheet: View {
    let job: AgentCronJob
    let onEdit: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var prompt: String
    @State private var schedule: String
    @State private var isSaving = false

    private let schedulePresets = [
        ("Every day 9am", "0 9 * * *"),
        ("Every hour",    "0 * * * *"),
        ("Every Monday",  "0 9 * * 1"),
        ("Every 6 hours", "0 */6 * * *"),
    ]

    init(job: AgentCronJob, onEdit: @escaping (String, String, String) -> Void) {
        self.job = job
        self.onEdit = onEdit
        _name = State(initialValue: job.name ?? "")
        _prompt = State(initialValue: job.prompt ?? job.script ?? "")
        _schedule = State(initialValue: job.schedule ?? "0 9 * * *")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Job Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        TextField("Daily summary", text: $name)
                            .font(.system(size: 16)).foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prompt").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        TextEditor(text: $prompt)
                            .font(.system(size: 15)).foregroundStyle(Theme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .frame(minHeight: 80)
                    }
                    .listRowBackground(Theme.card)
                }

                Section("Schedule (cron)") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("0 9 * * *", text: $schedule)
                            .font(Theme.monoFont(15)).foregroundStyle(Theme.accent)
                        Text("Use standard cron format: min hour day month weekday")
                            .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                    }
                    .listRowBackground(Theme.card)

                    ForEach(schedulePresets, id: \.1) { preset in
                        Button {
                            schedule = preset.1
                        } label: {
                            HStack {
                                Text(preset.0).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(preset.1).font(Theme.monoFont(12)).foregroundStyle(Theme.textTertiary)
                                if schedule == preset.1 {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .listRowBackground(Theme.card)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSaving = true
                        onEdit(name, prompt, schedule)
                        dismiss()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small).tint(Theme.accent)
                        } else {
                            Text("Save").fontWeight(.semibold).foregroundStyle(canSave ? Theme.accent : Theme.textTertiary)
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.large])
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !schedule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
