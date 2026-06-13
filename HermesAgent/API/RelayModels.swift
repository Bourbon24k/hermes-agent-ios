import Foundation

// MARK: - Envelopes

/// Relay wraps successes as { data: {...}, meta: {...} } and errors as { error: {...} }.
struct RelayEnvelope<T: Decodable>: Decodable {
    let data: T?
    let error: RelayError?
}

struct RelayError: Decodable, Error, LocalizedError {
    let code: String
    let message: String
    let retryable: Bool?

    var errorDescription: String? { message }
}

// MARK: - Pairing

/// QR payload printed by `hermes-mobile pair-phone`: {"code","relay"}.
struct PairingQR: Codable {
    let code: String
    let relay: String

    static func decode(from text: String) -> PairingQR? {
        guard let data = text.data(using: .utf8),
              let qr = try? JSONDecoder().decode(PairingQR.self, from: data),
              !qr.code.isEmpty
        else { return nil }
        return qr
    }
}

// MARK: - Auth / session

struct RelayAuth: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

struct RelayUser: Decodable {
    let id: String
    let displayName: String
}

struct RedeemResponse: Decodable {
    struct SessionInfo: Decodable {
        let connectionStatus: String?
        let backendEndpoint: String?
        let lastSyncAt: Date?
    }
    let user: RelayUser
    let deviceId: String
    let deviceRegistered: Bool?
    let session: SessionInfo
    let auth: RelayAuth
}

struct SessionResponse: Decodable {
    struct DeviceInfo: Decodable { let id: String; let registered: Bool? }
    struct SessionInfo: Decodable { let connectionStatus: String?; let backendEndpoint: String?; let lastSyncAt: Date? }
    struct PushInfo: Decodable { let tokenRegistered: Bool? }
    let user: RelayUser
    let device: DeviceInfo
    let session: SessionInfo
    let push: PushInfo?
}

// MARK: - Chat

struct RelayAttachmentMeta: Decodable, Hashable {
    let type: String?
    let filename: String?
    let mimeType: String?
    let thumbnailData: String?
}

/// A message as returned by the relay (`serialize_message`).
struct RelayMessage: Decodable, Identifiable, Hashable {
    let id: String
    let role: String
    let text: String
    let timestamp: Date?
    let deliveryStatus: String?
    let clientMessageId: String?
    let jobId: String?
    let attachments: [RelayAttachmentMeta]?
}

struct RelayConversation: Decodable {
    let id: String
    let title: String?
    let updatedAt: Date?
    let messages: [RelayMessage]
    let latestUsage: TokenUsageData?
}

struct TokenUsageData: Decodable, Hashable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens, outputTokens, totalTokens
        case input_tokens, output_tokens, total_tokens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = (try? c.decode(Int.self, forKey: .inputTokens)) ?? (try? c.decode(Int.self, forKey: .input_tokens))
        outputTokens = (try? c.decode(Int.self, forKey: .outputTokens)) ?? (try? c.decode(Int.self, forKey: .output_tokens))
        totalTokens = (try? c.decode(Int.self, forKey: .totalTokens)) ?? (try? c.decode(Int.self, forKey: .total_tokens))
    }
}

/// Response to POST /v1/messages and the body of the `done` SSE event.
struct MessageCreateResponse: Decodable {
    let replyState: String?
    let jobId: String?
    let conversation: RelayConversation?
    let userMessage: RelayMessage?
    let message: RelayMessage?
    let usage: TokenUsageData?
    let status: String?     // present on `done` events
    let error: String?
}

// MARK: - SSE progress payload

struct StreamProgressPayload: Decodable {
    let kind: String?
    let delta: String?
    let label: String?
    let detail: String?
    let command: String?
    let output: String?
    let status: String?
    let toolCallId: String?
}

// MARK: - UI models (decoupled from transport)

struct AgentEvent: Identifiable, Hashable {
    let id: String
    var title: String
    var subtitle: String?
    var detail: String?
    var status: String   // "running" | "completed" | "failed"
    var startedAt: Date? = nil
    var finishedAt: Date? = nil

    var isRunning: Bool { status == "running" }
    var isFailed: Bool { status == "failed" || status == "error" }

    var durationText: String? {
        guard let startedAt, let finishedAt else { return nil }
        let s = finishedAt.timeIntervalSince(startedAt)
        if s < 1 { return String(format: "%.0fms", s * 1000) }
        return String(format: "%.1fs", s)
    }
}

struct ChatMessage: Identifiable, Hashable {
    let id: String
    var role: String
    var content: String
    var reasoningContent: String?
    var agentEvents: [AgentEvent]
    var createdAt: Date?
    var status: String?
    var attachments: [RelayAttachmentMeta]

    init(
        id: String,
        role: String,
        content: String,
        reasoningContent: String? = nil,
        agentEvents: [AgentEvent] = [],
        createdAt: Date? = nil,
        status: String? = nil,
        attachments: [RelayAttachmentMeta] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.agentEvents = agentEvents
        self.createdAt = createdAt
        self.status = status
        self.attachments = attachments
    }

    init(relay: RelayMessage) {
        self.init(
            id: relay.id,
            role: relay.role,
            content: relay.text,
            createdAt: relay.timestamp,
            status: relay.deliveryStatus,
            attachments: relay.attachments ?? []
        )
    }
}
