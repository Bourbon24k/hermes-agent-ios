import SwiftUI

// MARK: - Terminal-style Tool Activity Card

struct ToolActivityView: View {
    let events: [AgentEvent]
    @State private var expanded = true
    @State private var expandedEventIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if expanded {
                Divider().overlay(Color.white.opacity(0.08))
                VStack(spacing: 0) {
                    ForEach(events) { event in
                        terminalRow(event)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Header

    private var headerRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                statusDot
                Text("Tool Activity")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("·  \(events.count) call\(events.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var statusDot: some View {
        Group {
            if events.contains(where: \.isRunning) {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.accent)
                    .scaleEffect(0.75)
                    .frame(width: 10, height: 10)
            } else if events.contains(where: \.isFailed) {
                Circle().fill(Theme.failure).frame(width: 8, height: 8)
            } else {
                Circle().fill(Theme.success).frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Terminal row

    private func terminalRow(_ event: AgentEvent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    if expandedEventIds.contains(event.id) { expandedEventIds.remove(event.id) }
                    else { expandedEventIds.insert(event.id) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Prompt symbol
                    Text("$")
                        .font(Theme.monoFont(12))
                        .foregroundStyle(Theme.accent.opacity(0.7))
                        .frame(width: 14, alignment: .leading)

                    // Command label
                    Text(commandText(event.title))
                        .font(Theme.monoFont(13))
                        .foregroundStyle(commandColor(event))
                        .lineLimit(1)

                    // Args in secondary
                    let args = argsText(event.title)
                    if !args.isEmpty {
                        Text(args)
                            .font(Theme.monoFont(12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Status indicator
                    if event.isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.accent)
                            .scaleEffect(0.7)
                    } else if event.isFailed {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.failure)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.success.opacity(0.7))
                    }

                    // Expand arrow if has detail
                    if event.detail != nil {
                        Image(systemName: expandedEventIds.contains(event.id) ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .disabled(event.detail == nil)

            // Detail / output block
            if expandedEventIds.contains(event.id), let detail = event.detail, !detail.isEmpty {
                outputBlock(detail)
            }
        }
    }

    private func outputBlock(_ text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(Theme.monoFont(11))
                .foregroundStyle(Color(white: 0.75))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .background(Color.black.opacity(0.4))
    }

    // MARK: - Label parsing

    /// Extract "command" (first word) from the label.
    private func commandText(_ label: String) -> String {
        label.split(separator: " ").first.map(String.init) ?? label
    }

    /// Extract remainder (args / path) after the first word.
    private func argsText(_ label: String) -> String {
        let parts = label.split(separator: " ", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : ""
    }

    private func commandColor(_ event: AgentEvent) -> Color {
        if event.isRunning { return Theme.accent }
        if event.isFailed { return Theme.failure }
        return Color(white: 0.85)
    }
}

// MARK: - Thinking / Reasoning View

struct ThinkingView: View {
    let text: String
    var isStreaming: Bool = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Thinking")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    if !expanded && !text.isEmpty {
                        Text(text.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isStreaming {
                        ProgressView().controlSize(.mini).tint(Theme.accent)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if expanded {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.separator, lineWidth: 1))
        .onChange(of: isStreaming) { _, streaming in
            if streaming && !expanded { withAnimation(.snappy) { expanded = true } }
            if !streaming && expanded { withAnimation(.snappy.delay(0.5)) { expanded = false } }
        }
    }
}
