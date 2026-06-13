import Foundation

enum RelayAPIError: LocalizedError {
    case notConnected
    case http(Int, code: String?, message: String?)
    case unreachable
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not paired with a relay"
        case .http(let status, let code, let message): return message ?? code ?? "HTTP \(status)"
        case .unreachable: return "Relay is unreachable. Check the URL and your connection."
        case .decoding(let detail): return "Unexpected response: \(detail)"
        }
    }

    var status: Int? {
        if case .http(let s, _, _) = self { return s }
        return nil
    }
}

/// Shared JSON coders with lenient ISO8601 date parsing (relay emits fractional seconds).
enum RelayCoders {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            if let date = parseDate(raw) { return date }
            throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: "bad date \(raw)")
        }
        return decoder
    }

    static func parseDate(_ raw: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: raw) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: raw) { return d }
        return nil
    }
}

/// HTTP client for the self-hosted Hermes Mobile relay (`/v1/*`, `{data,meta}` envelopes).
actor RelayClient {
    private(set) var session: RelaySession?
    private let urlSession: URLSession
    private var refreshTask: Task<Void, Error>?
    private var onSessionUpdate: (@Sendable (RelaySession?) -> Void)?

    init(session: RelaySession?) {
        self.session = session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config)
    }

    func setOnSessionUpdate(_ handler: @escaping @Sendable (RelaySession?) -> Void) {
        onSessionUpdate = handler
    }

    func updateSession(_ session: RelaySession?) {
        self.session = session
        if let session { RelaySessionStore.save(session) } else { RelaySessionStore.clear() }
        onSessionUpdate?(session)
    }

    var baseURL: String? { session?.relayBaseURL }

    struct Empty: Codable {}

    // MARK: - Generic request returning the unwrapped `data`

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(method: "GET", path: path, body: Optional<Empty>.none)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B?) async throws -> T {
        try await request(method: "POST", path: path, body: body)
    }

    func request<T: Decodable, B: Encodable>(
        method: String,
        path: String,
        body: B?,
        retryOnAuth: Bool = true
    ) async throws -> T {
        guard let base = session?.relayBaseURL else { throw RelayAPIError.notConnected }
        guard let url = URL(string: base + path) else { throw RelayAPIError.decoding("bad URL") }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if let token = session?.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: req)
        } catch {
            throw RelayAPIError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw RelayAPIError.unreachable }

        if http.statusCode == 401, retryOnAuth, session?.refreshToken != nil {
            try await refreshTokens()
            return try await request(method: method, path: path, body: body, retryOnAuth: false)
        }

        guard (200..<300).contains(http.statusCode) else {
            let env = try? RelayCoders.makeDecoder().decode(RelayEnvelope<RelayClient.Empty>.self, from: data)
            throw RelayAPIError.http(http.statusCode, code: env?.error?.code, message: env?.error?.message)
        }

        do {
            let env = try RelayCoders.makeDecoder().decode(RelayEnvelope<T>.self, from: data)
            if let value = env.data { return value }
            if let error = env.error { throw RelayAPIError.http(http.statusCode, code: error.code, message: error.message) }
            // Some endpoints (e.g. revoke) return data:{} — try decoding T directly from data wrapper.
            if T.self == Empty.self { return Empty() as! T }
            throw RelayAPIError.decoding("missing data")
        } catch let error as RelayAPIError {
            throw error
        } catch {
            throw RelayAPIError.decoding(String(describing: error))
        }
    }

    // MARK: - Agent bridge (/agent/* lives at the host root, not under /v1)

    private var agentBaseURL: String? {
        guard let base = session?.relayBaseURL else { return nil }
        if base.hasSuffix("/v1") { return String(base.dropLast(3)) }
        if base.hasSuffix("/v1/") { return String(base.dropLast(4)) }
        return base
    }

    func agentGet<T: Decodable>(_ path: String) async throws -> T {
        try await agentRequest(method: "GET", path: path, body: Optional<Empty>.none)
    }

    func agentPost<T: Decodable, B: Encodable>(_ path: String, body: B?) async throws -> T {
        try await agentRequest(method: "POST", path: path, body: body)
    }

    func agentPut<T: Decodable, B: Encodable>(_ path: String, body: B?) async throws -> T {
        try await agentRequest(method: "PUT", path: path, body: body)
    }

    func agentDelete<T: Decodable>(_ path: String) async throws -> T {
        try await agentRequest(method: "DELETE", path: path, body: Optional<Empty>.none)
    }

    private func agentRequest<T: Decodable, B: Encodable>(
        method: String, path: String, body: B?, retryOnAuth: Bool = true
    ) async throws -> T {
        guard let base = agentBaseURL, let url = URL(string: base + path) else { throw RelayAPIError.notConnected }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "accept")
        if let token = session?.accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        if let body { req.setValue("application/json", forHTTPHeaderField: "content-type"); req.httpBody = try JSONEncoder().encode(body) }

        let data: Data, response: URLResponse
        do { (data, response) = try await urlSession.data(for: req) } catch { throw RelayAPIError.unreachable }
        guard let http = response as? HTTPURLResponse else { throw RelayAPIError.unreachable }
        if http.statusCode == 401, retryOnAuth, session?.refreshToken != nil {
            try await refreshTokens()
            return try await agentRequest(method: method, path: path, body: body, retryOnAuth: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            let env = try? RelayCoders.makeDecoder().decode(RelayEnvelope<RelayClient.Empty>.self, from: data)
            throw RelayAPIError.http(http.statusCode, code: env?.error?.code, message: env?.error?.message)
        }
        let env = try RelayCoders.makeDecoder().decode(RelayEnvelope<T>.self, from: data)
        if let value = env.data { return value }
        if T.self == Empty.self { return Empty() as! T }
        throw RelayAPIError.decoding("missing data")
    }

    // MARK: - SSE

    func sseRequest(path: String) throws -> URLRequest {
        guard let base = session?.relayBaseURL, let url = URL(string: base + path) else {
            throw RelayAPIError.notConnected
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3600
        req.setValue("text/event-stream", forHTTPHeaderField: "accept")
        if let token = session?.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        return req
    }

    // MARK: - Token refresh

    private func refreshTokens() async throws {
        if let task = refreshTask { try await task.value; return }
        let task = Task { [weak self] in
            defer { Task { await self?.clearRefreshTask() } }
            try await self?.performRefresh()
        }
        refreshTask = task
        try await task.value
    }

    private func clearRefreshTask() { refreshTask = nil }

    private func performRefresh() async throws {
        guard let session, let url = URL(string: session.relayBaseURL + "/auth/refresh") else {
            throw RelayAPIError.notConnected
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONEncoder().encode(["refreshToken": session.refreshToken])
        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            updateSession(nil)   // refresh token dead → force re-pair
            throw RelayAPIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, code: "refresh_failed", message: "Session expired. Pair again.")
        }
        let env = try RelayCoders.makeDecoder().decode(RelayEnvelope<RelayAuth>.self, from: data)
        guard let auth = env.data else { updateSession(nil); throw RelayAPIError.decoding("refresh") }
        var updated = session
        updated.accessToken = auth.accessToken
        updated.refreshToken = auth.refreshToken
        updated.accessExpiresAt = auth.expiresAt
        updateSession(updated)
    }
}
