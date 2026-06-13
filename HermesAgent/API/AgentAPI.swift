import Foundation

// MARK: - Agent bridge models

struct AgentSession: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let preview: String?
    let source: String?
    let model: String?
    let messageCount: Int?
    let toolCallCount: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let costUsd: Double?
    let startedAt: Date?
    let endedAt: Date?

    var shownTitle: String {
        if let title, !title.isEmpty { return title }
        if let preview, !preview.isEmpty { return preview }
        return "Session"
    }
}

struct AgentSessionMessage: Decodable, Identifiable, Hashable {
    let role: String
    let text: String
    var id: String { "\(role)-\(text.hashValue)" }
}

struct AgentCronJob: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let prompt: String?
    let script: String?
    let schedule: String?
    let enabled: Bool?
    let paused: Bool?
    let state: String?
    let noAgent: Bool?
    let deliver: String?
    let model: String?
    let skills: [String]?
    let lastStatus: String?
    let lastRunAt: String?
    let nextRunAt: String?
}

struct AgentInsights: Decodable, Hashable {
    let periodDays: Int?
    let sessions: Int?
    let messages: Int?
    let toolCalls: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let costUsd: Double?
}

struct AgentSkill: Decodable, Identifiable, Hashable {
    let category: String?
    let name: String
    let description: String?
    let path: String?
    var id: String { "\(category ?? "")/\(name)" }
}

struct AgentFileEntry: Decodable, Identifiable, Hashable {
    let name: String
    let isDirectory: Bool
    let size: Int?
    var id: String { name }
}

struct AgentFileListing: Decodable, Hashable {
    let path: String
    let entries: [AgentFileEntry]
}

struct AgentFileContent: Decodable, Hashable {
    let path: String
    let content: String?
    let size: Int?
    let error: String?
}

struct AgentProfile: Decodable, Identifiable, Hashable {
    let name: String
    let active: Bool?
    var id: String { name }
}

struct AgentProfileDetails: Decodable, Hashable {
    let name: String
    let details: String?
    let ok: Bool?
}

struct AgentMemory: Decodable, Hashable {
    let memory: String?
    let user: String?
    let agents: String?
    let identity: String?
    let status: String?
}

enum ThinkingBudget: String, CaseIterable, Identifiable {
    case off, low, medium, high
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .off: return "circle.slash"
        case .low: return "brain"
        case .medium: return "brain.head.profile"
        case .high: return "sparkles"
        }
    }
    var tokenBudget: Int? {
        switch self { case .off: return nil; case .low: return 4000; case .medium: return 10000; case .high: return 20000 }
    }
}

struct AgentStatus: Decodable, Hashable {
    let hermesVersion: String?
}

struct AgentModel: Decodable, Identifiable, Hashable {
    let id: String
    let provider: String?

    /// "anthropic/claude-sonnet-4.6" → "Claude Sonnet 4.6"
    var displayName: String {
        let raw = id.split(separator: "/").last.map(String.init) ?? id
        return raw
            .split(separator: "-")
            .map { part in
                let s = String(part)
                return s.first.map { String($0).uppercased() + s.dropFirst() } ?? s
            }
            .joined(separator: " ")
    }
}

struct AgentModelsResponse: Decodable, Hashable {
    struct Current: Decodable, Hashable {
        let model: String?
        let provider: String?
        let reasoningEffort: String?
    }
    let models: [AgentModel]
    let current: Current
}

/// Typed access to the self-hosted hermes-bridge (/agent/*).
struct AgentAPI: Sendable {
    let client: RelayClient

    func sessions() async throws -> [AgentSession] {
        struct W: Decodable { let sessions: [AgentSession] }
        let w: W = try await client.agentGet("/agent/sessions")
        // Drop cron-task runs — they're automated and only clutter the list.
        return w.sessions.filter { ($0.source ?? "").lowercased() != "cron" }
    }

    func messages(sessionId: String) async throws -> [AgentSessionMessage] {
        struct W: Decodable { let messages: [AgentSessionMessage] }
        let w: W = try await client.agentGet("/agent/sessions/\(sessionId)/messages")
        return w.messages
    }

    /// Links the current conversation to a past session and repopulates it.
    func resumeSession(id: String) async throws {
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await client.agentPost("/agent/sessions/\(id)/resume", body: Optional<RelayClient.Empty>.none)
    }

    func deleteSession(id: String) async throws {
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await client.agentDelete("/agent/sessions/\(id)")
    }

    func renameSession(id: String, title: String) async throws {
        struct Body: Encodable { let title: String }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await client.agentPost("/agent/sessions/\(id)/rename", body: Body(title: title))
    }

    func cron() async throws -> [AgentCronJob] {
        struct W: Decodable { let jobs: [AgentCronJob] }
        let w: W = try await client.agentGet("/agent/cron")
        return w.jobs
    }

    func cronAction(jobId: String, action: String) async throws {
        let _: RelayClient.Empty = try await client.agentPost("/agent/cron/\(jobId)/\(action)", body: Optional<RelayClient.Empty>.none)
    }

    func insights() async throws -> AgentInsights {
        try await client.agentGet("/agent/insights")
    }

    func skills() async throws -> [AgentSkill] {
        struct W: Decodable { let skills: [AgentSkill] }
        let w: W = try await client.agentGet("/agent/skills")
        return w.skills
    }

    func profiles() async throws -> [AgentProfile] {
        struct W: Decodable { let profiles: [AgentProfile] }
        let w: W = try await client.agentGet("/agent/profiles")
        return w.profiles
    }

    func memory() async throws -> AgentMemory {
        try await client.agentGet("/agent/memory")
    }

    func status() async throws -> AgentStatus {
        try await client.agentGet("/agent/status")
    }

    func files(path: String) async throws -> AgentFileListing {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await client.agentGet("/agent/files?path=\(encoded)")
    }

    func fileContent(path: String) async throws -> AgentFileContent {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await client.agentGet("/agent/file?path=\(encoded)")
    }

    func saveMemory(key: String, content: String) async throws {
        struct Body: Encodable { let key: String; let content: String }
        let _: RelayClient.Empty = try await client.agentPut("/agent/memory", body: Body(key: key, content: content))
    }

    func saveFileContent(path: String, content: String) async throws {
        struct Body: Encodable { let path: String; let content: String }
        let _: RelayClient.Empty = try await client.agentPut("/agent/file", body: Body(path: path, content: content))
    }

    func createCronJob(name: String, prompt: String, schedule: String) async throws {
        struct Body: Encodable { let name: String; let prompt: String; let schedule: String }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await client.agentPost("/agent/cron", body: Body(name: name, prompt: prompt, schedule: schedule))
    }

    func editCronJob(oldId: String, name: String, prompt: String, schedule: String) async throws {
        try await cronAction(jobId: oldId, action: "delete")
        try await createCronJob(name: name, prompt: prompt, schedule: schedule)
    }

    func useProfile(name: String) async throws {
        let _: RelayClient.Empty = try await client.agentPost("/agent/profiles/\(name)/use", body: Optional<RelayClient.Empty>.none)
    }

    func createProfile(name: String, description: String?) async throws {
        struct Body: Encodable { let name: String; let description: String? }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await client.agentPost("/agent/profiles", body: Body(name: name, description: description))
    }

    func deleteProfile(name: String) async throws {
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await client.agentPost("/agent/profiles/\(name)/delete", body: Optional<RelayClient.Empty>.none)
    }

    func renameProfile(_ old: String, to new: String) async throws {
        struct Body: Encodable { let name: String }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await client.agentPost("/agent/profiles/\(old)/rename", body: Body(name: new))
    }

    func profileDetails(name: String) async throws -> AgentProfileDetails {
        try await client.agentGet("/agent/profiles/\(name)")
    }

    /// Fetches the system prompt from ~/.hermes/SYSTEM.md
    func systemPrompt() async throws -> String {
        let result = try await fileContent(path: "~/.hermes/SYSTEM.md")
        return result.content ?? ""
    }

    /// Saves the system prompt
    func saveSystemPrompt(_ content: String) async throws {
        try await saveFileContent(path: "~/.hermes/SYSTEM.md", content: content)
    }

    /// Available models + current selection from the agent host.
    func models() async throws -> AgentModelsResponse {
        try await client.agentGet("/agent/models")
    }

    /// Switches the agent's default model globally (applies to new sessions).
    func setModel(_ model: String, provider: String?) async throws {
        struct Body: Encodable { let model: String; let provider: String? }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await client.agentPost("/agent/model", body: Body(model: model, provider: provider))
    }

    /// Sets agent.reasoning_effort (off/low/medium/high).
    func setReasoning(_ level: String) async throws {
        struct Body: Encodable { let level: String }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp = try await client.agentPost("/agent/reasoning", body: Body(level: level))
    }
}
