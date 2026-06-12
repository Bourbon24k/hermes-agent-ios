import Foundation

/// Minimal Server-Sent Events stream parser over URLSession byte streams.
struct SSEEvent {
    var event: String?
    var data: String
    var id: String?
}

enum SSEClient {
    /// Opens the stream and yields parsed events until the connection closes or the task is cancelled.
    static func stream(request: URLRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw RelayAPIError.http((response as? HTTPURLResponse)?.statusCode ?? 0, code: "sse_failed", message: nil)
                    }
                    var eventName: String?
                    var dataLines: [String] = []
                    var eventId: String?

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.isEmpty {
                            if !dataLines.isEmpty || eventName != nil {
                                continuation.yield(SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"), id: eventId))
                            }
                            eventName = nil
                            dataLines = []
                            continue
                        }
                        if line.hasPrefix(":") { continue }
                        guard let colon = line.firstIndex(of: ":") else { continue }
                        let field = String(line[line.startIndex..<colon])
                        var value = String(line[line.index(after: colon)...])
                        if value.hasPrefix(" ") { value.removeFirst() }
                        switch field {
                        case "event": eventName = value
                        case "data": dataLines.append(value)
                        case "id": eventId = value
                        default: break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
