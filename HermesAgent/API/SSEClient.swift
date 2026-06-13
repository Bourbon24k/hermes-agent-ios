import Foundation

/// Minimal Server-Sent Events stream parser over URLSession byte streams.
struct SSEEvent {
    var event: String?
    var data: String
    var id: String?
}

enum SSEClient {
    /// Opens the stream and yields parsed events until the connection closes or the task is cancelled.
    ///
    /// NOTE: parses lines manually from the byte stream. `URLSession.AsyncBytes.lines`
    /// drops empty lines — but an empty line is the SSE event delimiter, so using it
    /// means no event is ever emitted until the connection closes.
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
                    var buffer: [UInt8] = []
                    buffer.reserveCapacity(1024)

                    func processLine(_ line: String) {
                        if line.isEmpty {
                            if !dataLines.isEmpty || eventName != nil {
                                continuation.yield(SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"), id: eventId))
                            }
                            eventName = nil
                            dataLines = []
                            return
                        }
                        if line.hasPrefix(":") { return }
                        guard let colon = line.firstIndex(of: ":") else { return }
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

                    for try await byte in bytes {
                        if Task.isCancelled { break }
                        if byte == 0x0A { // \n — end of line
                            var line = String(decoding: buffer, as: UTF8.self)
                            if line.hasSuffix("\r") { line.removeLast() }
                            buffer.removeAll(keepingCapacity: true)
                            processLine(line)
                        } else {
                            buffer.append(byte)
                        }
                    }
                    // Flush a trailing event if the stream closed without a final blank line.
                    if !buffer.isEmpty {
                        var line = String(decoding: buffer, as: UTF8.self)
                        if line.hasSuffix("\r") { line.removeLast() }
                        processLine(line)
                    }
                    if !dataLines.isEmpty || eventName != nil {
                        continuation.yield(SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"), id: eventId))
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
