import Foundation
import UIKit

/// Typed relay endpoints used by the app.
struct RelayAPI: Sendable {
    let client: RelayClient

    // MARK: - Pairing (no auth)

    struct DeviceInfoBody: Encodable {
        let platform: String
        let deviceName: String
        let appVersion: String
        let buildNumber: String
        let bundleId: String
        let installationId: String
        let deviceModel: String
        let systemVersion: String
    }

    struct RedeemBody: Encodable {
        let code: String
        let device: DeviceInfoBody
        let client: ClientInfoBody
        struct ClientInfoBody: Encodable { let environment: String }
    }

    @MainActor
    static func deviceInfo() -> DeviceInfoBody {
        let device = UIDevice.current
        let bundle = Bundle.main
        return DeviceInfoBody(
            platform: "ios",
            deviceName: device.name,
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            bundleId: bundle.bundleIdentifier ?? "me.clawpilot.hermes-agent",
            installationId: RelaySessionStore.installationId,
            deviceModel: device.model,
            systemVersion: device.systemVersion
        )
    }

    /// Redeems an 8-char pairing code against `relayBaseURL` (must end with /v1). No auth.
    static func redeem(relayBaseURL: String, code: String, device: DeviceInfoBody) async throws -> RedeemResponse {
        let base = relayBaseURL.hasSuffix("/") ? String(relayBaseURL.dropLast()) : relayBaseURL
        guard let url = URL(string: base + "/phone-pairing/redeem") else { throw RelayAPIError.decoding("bad URL") }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONEncoder().encode(RedeemBody(
            code: code,
            device: device,
            client: .init(environment: "production")
        ))
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw RelayAPIError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw RelayAPIError.unreachable }
        guard (200..<300).contains(http.statusCode) else {
            let env = try? RelayCoders.makeDecoder().decode(RelayEnvelope<RelayClient.Empty>.self, from: data)
            throw RelayAPIError.http(http.statusCode, code: env?.error?.code, message: env?.error?.message)
        }
        let env = try RelayCoders.makeDecoder().decode(RelayEnvelope<RedeemResponse>.self, from: data)
        guard let value = env.data else { throw RelayAPIError.decoding("redeem") }
        return value
    }

    // MARK: - Session

    func session() async throws -> SessionResponse {
        try await client.get("/session")
    }

    func revoke() async throws {
        let _: RelayClient.Empty = try await client.post("/auth/revoke", body: Optional<RelayClient.Empty>.none)
    }

    // MARK: - Conversation

    func currentConversation() async throws -> RelayConversation {
        struct Wrapper: Decodable { let conversation: RelayConversation }
        let wrapper: Wrapper = try await client.get("/conversations/current")
        return wrapper.conversation
    }

    func clearConversation() async throws -> RelayConversation {
        struct Wrapper: Decodable { let conversation: RelayConversation }
        let wrapper: Wrapper = try await client.post("/conversations/current/clear", body: Optional<RelayClient.Empty>.none)
        return wrapper.conversation
    }

    // MARK: - Messages

    struct AttachmentBody: Encodable {
        let type: String
        let mimeType: String
        let data: String
        let filename: String
    }

    struct SendBody: Encodable {
        let text: String
        let clientMessageId: String
        let model: String?
        let thinkingBudgetTokens: Int?
        let attachments: [AttachmentBody]?

        enum CodingKeys: String, CodingKey { case text, clientMessageId, model, thinkingBudgetTokens, attachments }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(text, forKey: .text)
            try c.encode(clientMessageId, forKey: .clientMessageId)
            try c.encodeIfPresent(model, forKey: .model)
            try c.encodeIfPresent(thinkingBudgetTokens, forKey: .thinkingBudgetTokens)
            try c.encodeIfPresent(attachments, forKey: .attachments)
        }
    }

    func sendMessage(
        text: String,
        clientMessageId: String,
        model: String? = nil,
        thinkingBudget: ThinkingBudget? = nil,
        attachments: [AttachmentBody]? = nil
    ) async throws -> MessageCreateResponse {
        try await client.post("/messages", body: SendBody(
            text: text,
            clientMessageId: clientMessageId,
            model: model,
            thinkingBudgetTokens: thinkingBudget?.tokenBudget,
            attachments: attachments
        ))
    }
}
