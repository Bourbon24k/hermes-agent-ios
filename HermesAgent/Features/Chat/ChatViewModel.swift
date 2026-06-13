import Foundation
import Observation
import UIKit

enum StreamingPhase: Equatable {
    case idle, connecting, thinking, running, writing
    var label: String {
        switch self {
        case .idle: return ""
        case .connecting: return "Connecting…"
        case .thinking: return "Thinking…"
        case .running: return "Working…"
        case .writing: return "Generating…"
        }
    }
}

@Observable
@MainActor
final class ChatViewModel {
    let api: RelayAPI
    var messages: [ChatMessage] = []
    var isLoading = false
    var isStreaming = false
    var streamingPhase: StreamingPhase = .idle
    var errorText: String?
    var conversationTitle: String = "Hermes"

    private var streamTask: Task<Void, Never>?

    init(api: RelayAPI) {
        self.api = api
    }

    /// True once the conversation has been fetched at least once this app run.
    private var didInitialLoad = false

    func load() async {
        // The view model lives in AppState and survives leaving the chat screen,
        // so only the FIRST appearance fetches from the server. Re-entering must
        // never clobber locally-held messages or an in-flight streaming reply.
        guard !isStreaming else { return }
        guard !didInitialLoad else { return }
        isLoading = true
        do {
            let conversation = try await api.currentConversation()
            apply(conversation)
            didInitialLoad = true
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }

    /// Force a fresh fetch (pull-to-refresh / explicit reload).
    func reload() async {
        guard !isStreaming else { return }
        didInitialLoad = false
        await load()
    }

    func clear() async {
        do {
            let conversation = try await api.clearConversation()
            apply(conversation)
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Resumes a past agent session: the bridge links the current conversation
    /// to it and copies its transcript, then we reload to show that history.
    func resume(sessionId: String, agent: AgentAPI) async {
        isLoading = true
        do {
            try await agent.resumeSession(id: sessionId)
            let conversation = try await api.currentConversation()
            apply(conversation)
            Haptics.success()
        } catch {
            errorText = error.localizedDescription
            Haptics.error()
        }
        isLoading = false
    }

    private func apply(_ conversation: RelayConversation) {
        conversationTitle = conversation.title ?? "Hermes"
        messages = conversation.messages.map(ChatMessage.init(relay:))
        didInitialLoad = true
    }

    func send(text: String, model: String? = nil, thinking: ThinkingBudget? = nil, image: UIImage? = nil) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty || image != nil else { return }
        errorText = nil
        let clientMessageId = UUID().uuidString

        Haptics.send()
        messages.append(ChatMessage(id: "local-\(clientMessageId)", role: "user", content: content, createdAt: Date()))
        isStreaming = true
        streamingPhase = .connecting
        let assistantId = "stream-\(clientMessageId)"
        messages.append(ChatMessage(id: assistantId, role: "hermes", content: "", createdAt: Date(), status: "streaming"))

        // Build attachments if image present
        var attachments: [RelayAPI.AttachmentBody]?
        if let img = image, let jpeg = img.jpegData(compressionQuality: 0.85) {
            let b64 = jpeg.base64EncodedString()
            // Small thumbnail so chat history can render the photo (relay strips full data).
            var thumbB64: String?
            let maxSide: CGFloat = 280
            let scale = min(1, maxSide / max(img.size.width, img.size.height))
            let thumbSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: thumbSize)
            let thumb = renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: thumbSize)) }
            if let thumbJpeg = thumb.jpegData(compressionQuality: 0.6) {
                thumbB64 = thumbJpeg.base64EncodedString()
            }
            attachments = [RelayAPI.AttachmentBody(type: "image", mimeType: "image/jpeg", data: b64, filename: "photo.jpg", thumbnailData: thumbB64)]
            // Show the photo immediately on the local user message echo.
            if let idx = messages.lastIndex(where: { $0.id == "local-\(clientMessageId)" }) {
                messages[idx].attachments = [RelayAttachmentMeta(type: "image", filename: "photo.jpg", mimeType: "image/jpeg", thumbnailData: thumbB64)]
            }
        }

        do {
            let response = try await api.sendMessage(
                text: content,
                clientMessageId: clientMessageId,
                model: model,
                thinkingBudget: thinking,
                attachments: attachments
            )
            // Replace echo with the server's user message if present.
            if let userMessage = response.userMessage,
               let index = messages.firstIndex(where: { $0.id == "local-\(clientMessageId)" }) {
                messages[index] = ChatMessage(relay: userMessage)
            }
            guard let jobId = response.jobId else {
                // Synchronous (non-connector) reply already final.
                if let message = response.message {
                    finalizeAssistant(assistantId, with: message)
                }
                isStreaming = false
                return
            }
            streamJob(jobId: jobId, assistantId: assistantId)
        } catch {
            isStreaming = false
            errorText = error.localizedDescription
            messages.removeAll { $0.id == assistantId }
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        streamingPhase = .idle
        for i in messages.indices where messages[i].status == "streaming" {
            messages[i].status = "completed"
            closeRunningTools(at: i)
        }
    }

    private func streamJob(jobId: String, assistantId: String) {
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let request = try await self.api.client.sseRequest(path: "/jobs/\(jobId)/events")
                for try await event in SSEClient.stream(request: request) {
                    if Task.isCancelled { return }
                    self.handleSSE(event, assistantId: assistantId)
                    if event.event == "done" { break }
                }
            } catch {
                // SSE may fail or the reply may have completed before we connected;
                // the reconcile below pulls the authoritative final state regardless.
            }
            self.isStreaming = false
            self.streamingPhase = .idle
            if !Task.isCancelled {
                await self.reconcile()
            }
        }
    }

    /// Pulls the server's authoritative conversation and replaces local state.
    /// This guarantees the assistant reply is visible even if the SSE stream
    /// missed events (e.g. the job finished during the synchronous send wait).
    private func reconcile() async {
        guard !isStreaming, let conversation = try? await api.currentConversation() else { return }
        // Keep any tool/reasoning context we accumulated for the last assistant turn.
        let priorEvents = messages.last(where: { $0.role != "user" })?.agentEvents ?? []
        var merged = conversation.messages.map(ChatMessage.init(relay:))
        if let lastIndex = merged.lastIndex(where: { $0.role != "user" }), !priorEvents.isEmpty,
           merged[lastIndex].agentEvents.isEmpty {
            merged[lastIndex].agentEvents = priorEvents
        }
        messages = merged
        conversationTitle = conversation.title ?? conversationTitle
    }

    private func handleSSE(_ event: SSEEvent, assistantId: String) {
        guard let data = event.data.data(using: .utf8) else { return }
        switch event.event {
        case "text_delta":
            if let payload = try? RelayCoders.makeDecoder().decode(StreamProgressPayload.self, from: data),
               let delta = payload.delta {
                appendDelta(delta, to: assistantId)
                streamingPhase = .writing
            }
        case "tool_activity":
            if let payload = try? RelayCoders.makeDecoder().decode(StreamProgressPayload.self, from: data) {
                if payload.status == "completed", let callId = payload.toolCallId, !callId.isEmpty {
                    completeTool(callId: callId, detail: payload.detail, in: assistantId)
                } else {
                    appendTool(
                        label: payload.label ?? "Tool activity",
                        detail: payload.detail,
                        callId: payload.toolCallId,
                        to: assistantId
                    )
                }
                streamingPhase = .running
            }
        case "tool_output":
            if let payload = try? RelayCoders.makeDecoder().decode(StreamProgressPayload.self, from: data) {
                appendToolOutput(output: payload.delta ?? payload.label ?? "", to: assistantId)
            }
        case "reasoning":
            if let payload = try? RelayCoders.makeDecoder().decode(StreamProgressPayload.self, from: data),
               let delta = payload.delta {
                appendReasoning(delta, to: assistantId)
                streamingPhase = .thinking
            }
        case "done":
            if let payload = try? RelayCoders.makeDecoder().decode(MessageCreateResponse.self, from: data) {
                if payload.status == "failed" {
                    errorText = payload.error ?? "Run failed"
                    markFailed(assistantId)
                    Haptics.error()
                } else if let message = payload.message {
                    finalizeAssistant(assistantId, with: message)
                    Haptics.success()
                } else {
                    finalizeStreamingText(assistantId)
                    Haptics.success()
                }
            } else {
                finalizeStreamingText(assistantId)
                Haptics.success()
            }
            isStreaming = false
        default:
            break
        }
    }

    // MARK: - Streaming mutations

    private func appendDelta(_ delta: String, to id: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].content += delta
    }

    private func appendReasoning(_ delta: String, to id: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[i].reasoningContent = (messages[i].reasoningContent ?? "") + delta
    }

    private func appendTool(label: String, detail: String? = nil, callId: String? = nil, to id: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        Haptics.tap()
        messages[i].agentEvents.append(AgentEvent(
            id: (callId?.isEmpty == false ? callId! : UUID().uuidString),
            title: label, subtitle: nil, detail: detail,
            status: "running", startedAt: Date()
        ))
    }

    private func completeTool(callId: String, detail: String?, in id: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        if let j = messages[i].agentEvents.firstIndex(where: { $0.id == callId }) {
            messages[i].agentEvents[j].status = "completed"
            messages[i].agentEvents[j].finishedAt = Date()
            if let detail, !detail.isEmpty {
                messages[i].agentEvents[j].detail = detail
            }
        }
    }

    private func appendToolOutput(output: String, to id: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }),
              let last = messages[i].agentEvents.indices.last else { return }
        let existing = messages[i].agentEvents[last].detail ?? ""
        messages[i].agentEvents[last].detail = existing.isEmpty ? output : existing + "\n" + output
    }

    private func closeRunningTools(at i: Int) {
        for j in messages[i].agentEvents.indices where messages[i].agentEvents[j].isRunning {
            messages[i].agentEvents[j].status = "completed"
        }
    }

    private func finalizeStreamingText(_ id: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        closeRunningTools(at: i)
        messages[i].status = "completed"
    }

    private func finalizeAssistant(_ id: String, with message: RelayMessage) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else {
            messages.append(ChatMessage(relay: message))
            return
        }
        var final = ChatMessage(relay: message)
        // Preserve accumulated tool/reasoning context for display.
        final.agentEvents = messages[i].agentEvents.map { var e = $0; if e.isRunning { e.status = "completed" }; return e }
        if final.reasoningContent == nil { final.reasoningContent = messages[i].reasoningContent }
        if final.content.isEmpty { final.content = messages[i].content }
        final.status = "completed"
        messages[i] = final
    }

    private func markFailed(_ id: String) {
        guard let i = messages.firstIndex(where: { $0.id == id }) else { return }
        closeRunningTools(at: i)
        messages[i].status = "failed"
        if messages[i].content.isEmpty { messages[i].content = "_Run failed._" }
    }
}
