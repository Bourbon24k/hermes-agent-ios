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

/// Typed access to the self-hosted hermes-bridge (/agent/*).
struct AgentAPI: Sendable {
    let client: RelayClient

    func sessions() async throws -> [AgentSession] {
        struct W: Decodable { let sessions: [AgentSession] }
        let w: W = try await client.agentGet("/agent/sessions")
        return w.sessions
    }

    func messages(sessionId: String) async throws -> [AgentSessionMessage] {
        struct W: Decodable { let messages: [AgentSessionMessage] }
        let w: W = try await client.agentGet("/agent/sessions/\(sessionId)/messages")
        return w.messages
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
}
