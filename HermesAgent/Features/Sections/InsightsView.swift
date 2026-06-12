import SwiftUI

struct InsightsView: View {
    @Environment(AppState.self) private var appState
    @State private var insights: AgentInsights?
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let insights {
                    Text("Last \(insights.periodDays ?? 30) days")
                        .font(.subheadline).foregroundStyle(Theme.textTertiary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        metric("Sessions", insights.sessions.map(format))
                        metric("Messages", insights.messages.map(format))
                        metric("Tool calls", insights.toolCalls.map(format))
                        metric("Total tokens", insights.totalTokens.map(format))
                        metric("Input tokens", insights.inputTokens.map(format))
                        metric("Output tokens", insights.outputTokens.map(format))
                        if let cost = insights.costUsd, cost > 0 {
                            metric("Cost", String(format: "$%.2f", cost))
                        }
                    }
                }
                if let errorText { Text(errorText).font(.footnote).foregroundStyle(Theme.failure) }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Insights")
        .overlay { if isLoading { ProgressView().tint(Theme.accent) } }
        .refreshable { await load() }
        .task { await load() }
    }

    private func metric(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textTertiary).lineLimit(1)
            Text(value ?? "—")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent).lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).cardStyle()
    }

    private func format(_ n: Int) -> String { n.formatted() }

    private func load() async {
        isLoading = true; errorText = nil
        do { insights = try await appState.agent.insights() } catch { errorText = error.localizedDescription }
        isLoading = false
    }
}
