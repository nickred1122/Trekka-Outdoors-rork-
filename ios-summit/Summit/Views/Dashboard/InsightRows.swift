import SwiftUI

/// Renders a list of observations the same way everywhere they appear.
///
/// Insights now show up in three places — the dashboard, a recorded session, and
/// the Insights screen — and they have to read identically in all of them. A
/// caution on a session and a caution on the dashboard mean the same thing, so
/// they cannot be two different shades of orange.
struct InsightRows: View {
    let insights: [TrainingInsight]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(height: 1)
                        .padding(.leading, 38)
                }
                InsightRow(insight: insight)
            }
        }
    }
}

struct InsightRow: View {
    let insight: TrainingInsight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: insight.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(InsightTint.color(insight.tone))
                .frame(width: 28, height: 28)
                .background(InsightTint.color(insight.tone).opacity(0.12), in: .rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.system(.caption, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(insight.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

nonisolated enum InsightTint {
    static func color(_ tone: InsightTone) -> Color {
        switch tone {
        case .positive: Theme.positive
        case .neutral: Theme.accent
        case .caution: Theme.highlight
        }
    }
}
