import SwiftUI
import UIKit

struct MessageView: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    var streamingPhase: StreamingPhase = .idle

    var body: some View {
        if message.role == "user" {
            userBubble
        } else {
            assistantBody
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text(message.content)
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu {
                    Button { UIPasteboard.general.string = message.content } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
        }
    }

    private var assistantBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reasoning = message.reasoningContent, !reasoning.isEmpty {
                ThinkingView(text: reasoning, isStreaming: isStreaming && message.content.isEmpty)
            }
            if !message.agentEvents.isEmpty {
                ToolActivityView(events: message.agentEvents)
            }
            let blocks = MarkdownBlock.parse(message.content)
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                let isLastBlock = index == blocks.count - 1
                switch block {
                case .text(_, let content):
                    streamingText(content, isLast: isLastBlock)

                case .code(_, let language, let code):
                    CodeBlockView(language: language, code: code)

                case .heading(_, let level, let content):
                    headingView(level: level, content: content)

                case .listBlock(_, let items):
                    listView(items: items)

                case .blockquote(_, let content):
                    blockquoteView(content: content)

                case .divider(_):
                    dividerView
                }
            }
            // Streaming indicator
            if isStreaming {
                StreamingCursor(phase: streamingPhase)
            }

            // Timestamp + copy row (only rendered when there is something to show)
            let hasDate = message.createdAt != nil
            let hasCopy = !message.content.isEmpty && !isStreaming
            if hasDate || hasCopy {
                HStack(spacing: 10) {
                    if let date = message.createdAt {
                        Text(date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    if hasCopy {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Text

    private func streamingText(_ content: String, isLast: Bool) -> some View {
        Text(.hermesMarkdown(content))
            .font(.system(size: 16))
            .foregroundStyle(Theme.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Heading

    private func headingView(level: Int, content: String) -> some View {
        Text(.hermesMarkdown(content))
            .font(.system(size: headingSize(level), weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, level == 1 ? 6 : 2)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 24
        case 2: return 20
        case 3: return 18
        default: return 16
        }
    }

    // MARK: - List

    private func listView(items: [ListItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 8) {
                    if item.ordered {
                        Text("\(item.index).")
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 24, alignment: .trailing)
                    } else {
                        Text("•")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 16, alignment: .center)
                    }
                    Text(.hermesMarkdown(item.content))
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.leading, 4)
    }

    // MARK: - Blockquote

    private func blockquoteView(content: String) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Theme.accent.opacity(0.6))
                .frame(width: 3)
            Text(.hermesMarkdown(content))
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Divider

    private var dividerView: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.vertical, 6)
    }
}

// MARK: - Streaming cursor (blinking)

struct StreamingCursor: View {
    var phase: StreamingPhase = .writing
    @State private var visible = true

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.accent)
                .frame(width: 2, height: 16)
                .opacity(visible ? 1 : 0.15)
            Text(phase == .idle ? "Generating…" : phase.label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                visible = false
            }
        }
    }
}
