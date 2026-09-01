import SwiftUI

nonisolated struct StatItem: Identifiable, Sendable {
    let id = UUID()
    var symbol: String
    var label: String
    var value: String
    var unit: String
}

/// Three-up divided stat row used on route and activity detail screens.
struct StatStrip: View {
    let items: [StatItem]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.accent)
                        Text(item.label)
                            .metricLabelStyle()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(item.value)
                            .font(.metric(22))
                            .foregroundStyle(Theme.textPrimary)
                        Text(item.unit)
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .accessibilityElement(children: .combine)

                if index < items.count - 1 {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 1, height: 38)
                }
            }
        }
        .padding(.vertical, 14)
        .panel()
    }
}
