import SwiftUI
import UIKit

// MARK: - Tool Type Detection

enum ToolType {
    case terminal
    case fileEdit
    case fileRead
    case search
    case generic

    static func detect(from title: String) -> ToolType {
        let lower = title.lowercased()
        // Terminal / command execution
        if lower.hasPrefix("running command") || lower.hasPrefix("executing") ||
           lower.hasPrefix("command:") || lower.hasPrefix("shell:") ||
           lower.hasPrefix("terminal:") || lower.hasPrefix("bash:") ||
           lower.hasPrefix("npm ") || lower.hasPrefix("git ") ||
           lower.hasPrefix("pip ") || lower.hasPrefix("brew ") ||
           lower.hasPrefix("run_command") || lower.hasPrefix("running:") ||
           lower.contains("$ ") { return .terminal }
        // File write / edit
        if lower.hasPrefix("editing file") || lower.hasPrefix("editing:") ||
           lower.hasPrefix("writing to") || lower.hasPrefix("creating file") ||
           lower.hasPrefix("modifying") || lower.hasPrefix("updating file") ||
           lower.hasPrefix("saving") || lower.hasPrefix("write_to_file") ||
           lower.hasPrefix("replace_file") || lower.hasPrefix("multi_replace") ||
           lower.contains("edit") && lower.contains("file") { return .fileEdit }
        // File read / view
        if lower.hasPrefix("reading file") || lower.hasPrefix("viewing file") ||
           lower.hasPrefix("reading:") || lower.hasPrefix("viewing:") ||
           lower.hasPrefix("view_file") || lower.hasPrefix("list_dir") ||
           lower.hasPrefix("listing") { return .fileRead }
        // Search
        if lower.hasPrefix("searching") || lower.hasPrefix("web search") ||
           lower.hasPrefix("search:") || lower.hasPrefix("grep") ||
           lower.hasPrefix("finding") || lower.hasPrefix("search_web") ||
           lower.hasPrefix("grep_search") { return .search }
        return .generic
    }

    var icon: String {
        switch self {
        case .terminal: return "apple.terminal"
        case .fileEdit:  return "doc.text"
        case .fileRead:  return "eye"
        case .search:    return "magnifyingglass"
        case .generic:   return "wrench"
        }
    }

    var color: Color {
        switch self {
        case .terminal: return Color(red: 0.3, green: 0.85, blue: 0.4)
        case .fileEdit:  return Color(red: 0.4, green: 0.6, blue: 1.0)
        case .fileRead:  return Color(red: 0.45, green: 0.8, blue: 0.9)
        case .search:    return Color(red: 0.7, green: 0.5, blue: 1.0)
        case .generic:   return Color(white: 0.85)
        }
    }

    var promptSymbol: String {
        switch self {
        case .terminal: return "$"
        case .fileEdit:  return "✎"
        case .fileRead:  return "◉"
        case .search:    return "⌕"
        case .generic:   return "›"
        }
    }

    var outputBackground: Color {
        switch self {
        case .terminal: return Color(red: 0.02, green: 0.06, blue: 0.03)
        default:        return Color.black.opacity(0.4)
        }
    }

    var outputTextColor: Color {
        switch self {
        case .terminal: return Color(red: 0.55, green: 0.9, blue: 0.55)
        case .fileEdit:  return Color(red: 0.6, green: 0.75, blue: 1.0)
        default:        return Color(white: 0.75)
        }
    }
}

// MARK: - Terminal-style Tool Activity Card

struct ToolActivityView: View {
    let events: [AgentEvent]
    @State private var expanded = true
    @State private var expandedEventIds: Set<String> = []
    @State private var expandedOutputIds: Set<String> = []
    @State private var detailEvent: AgentEvent?

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
        .sheet(item: $detailEvent) { event in
            ToolDetailSheet(event: event)
        }
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
        let toolType = ToolType.detect(from: event.title)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    if expandedEventIds.contains(event.id) { expandedEventIds.remove(event.id) }
                    else { expandedEventIds.insert(event.id) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // Type-specific icon
                    Image(systemName: toolType.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(toolType.color.opacity(event.isRunning ? 1.0 : 0.7))
                        .frame(width: 16, alignment: .center)

                    // Command label
                    Text(commandText(event.title))
                        .font(Theme.monoFont(13))
                        .foregroundStyle(eventCommandColor(event, toolType: toolType))
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
                            .tint(toolType.color)
                            .scaleEffect(0.7)
                    } else if event.isFailed {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.failure)
                    } else {
                        if let dur = event.durationText {
                            Text(dur)
                                .font(Theme.monoFont(10))
                                .foregroundStyle(Theme.textTertiary)
                        }
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(event.detail == nil)
            .contextMenu {
                Button { detailEvent = event } label: { Label("View details", systemImage: "doc.text.magnifyingglass") }
                if let detail = event.detail {
                    Button { UIPasteboard.general.string = detail } label: { Label("Copy output", systemImage: "doc.on.doc") }
                }
                Button { UIPasteboard.general.string = event.title } label: { Label("Copy command", systemImage: "terminal") }
            }

            // Detail / output block
            if expandedEventIds.contains(event.id), let detail = event.detail, !detail.isEmpty {
                outputBlock(detail, eventId: event.id, toolType: toolType)
            }
        }
    }

    private func outputBlock(_ text: String, eventId: String, toolType: ToolType) -> some View {
        let isFullyExpanded = expandedOutputIds.contains(eventId)
        let lineCount = text.components(separatedBy: "\n").count
        let needsExpand = lineCount > 15

        return VStack(spacing: 0) {
            // Terminal-style top accent bar for terminal type
            if toolType == .terminal {
                Rectangle()
                    .fill(toolType.color.opacity(0.3))
                    .frame(height: 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(Theme.monoFont(11))
                    .foregroundStyle(toolType.outputTextColor)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: isFullyExpanded ? .infinity : 300)
            .clipped()

            if needsExpand {
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            if isFullyExpanded { expandedOutputIds.remove(eventId) }
                            else { expandedOutputIds.insert(eventId) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isFullyExpanded ? "Show less" : "Show all (\(lineCount) lines)")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: isFullyExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    Button {
                        if let event = events.first(where: { $0.id == eventId }) {
                            detailEvent = event
                        }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                .background(toolType.outputBackground.opacity(0.6))
            }
        }
        .background(toolType.outputBackground)
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

    private func eventCommandColor(_ event: AgentEvent, toolType: ToolType) -> Color {
        if event.isRunning { return toolType.color }
        if event.isFailed { return Theme.failure }
        return toolType.color.opacity(0.8)
    }
}

// MARK: - Thinking / Reasoning View

struct ThinkingView: View {
    @Environment(AppState.self) private var appState
    let text: String
    var isStreaming: Bool = false
    @State private var expanded = false

    /// Last few lines of reasoning for the GPT-style peek when collapsed.
    private var peekText: String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return lines.suffix(3).joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if expanded {
                fullText
            } else if isStreaming && !peekText.isEmpty {
                peek
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.separator, lineWidth: 1))
        .animation(.snappy(duration: 0.25), value: expanded)
        .animation(.snappy(duration: 0.2), value: peekText)
        .onChange(of: isStreaming) { _, streaming in
            // GPT behaviour: stays collapsed-with-peek while thinking, fully
            // collapses once done. Never auto-expands to full.
            if !streaming && expanded {
                withAnimation(.snappy.delay(0.4)) { expanded = false }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) { expanded.toggle() }
            Haptics.selection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                if isStreaming {
                    ShimmerText(text: "Thinking…")
                } else {
                    Text("Thoughts")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Collapsed peek (GPT-style: last lines fading at the top)

    private var peek: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Text(peekText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .id("peekEnd")
            }
            .frame(height: 54)
            .mask(
                LinearGradient(
                    colors: [.clear, .black, .black],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .onChange(of: peekText) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("peekEnd", anchor: .bottom) }
            }
        }
    }

    // MARK: - Expanded full reasoning

    private var fullText: some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 320)
    }
}

// MARK: - Shimmer animated text (ChatGPT-style "Thinking…")

struct ShimmerText: View {
    let text: String
    @State private var phase: CGFloat = -1

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .overlay(
                LinearGradient(
                    colors: [.clear, Theme.accent.opacity(0.9), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 80)
                .offset(x: phase * 120)
                .blendMode(.screen)
                .mask(
                    Text(text).font(.system(size: 13, weight: .semibold))
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.5
                }
            }
    }
}


// MARK: - Tool Detail Sheet (fullscreen event inspector)

struct ToolDetailSheet: View {
    let event: AgentEvent
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var toolType: ToolType { ToolType.detect(from: event.title) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Status header
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(toolType.color.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: toolType.icon)
                                .font(.system(size: 17))
                                .foregroundStyle(toolType.color)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(event.isRunning ? "Running" : (event.isFailed ? "Failed" : "Completed"))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(event.isRunning ? Theme.accent : (event.isFailed ? Theme.failure : Theme.success))
                                if let dur = event.durationText {
                                    Text(dur)
                                        .font(Theme.monoFont(12))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            if let started = event.startedAt {
                                Text(started.formatted(date: .omitted, time: .standard))
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Spacer()
                        if event.isRunning {
                            ProgressView().tint(Theme.accent)
                        }
                    }

                    // Command / invocation
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMMAND")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                        Text(event.title)
                            .font(Theme.monoFont(13))
                            .foregroundStyle(Theme.textPrimary)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Output
                    if let detail = event.detail, !detail.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("OUTPUT")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)
                                Spacer()
                                Button {
                                    UIPasteboard.general.string = detail
                                    copied = true
                                    Task { try? await Task.sleep(for: .seconds(1.2)); copied = false }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 11))
                                        Text(copied ? "Copied" : "Copy")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundStyle(copied ? Theme.success : Theme.textSecondary)
                                }
                            }
                            Text(detail)
                                .font(Theme.monoFont(12))
                                .foregroundStyle(toolType.outputTextColor)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                    } else {
                        Text("No output captured.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Tool Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationBackground(Theme.background)
        .presentationDetents([.large, .medium])
    }
}
