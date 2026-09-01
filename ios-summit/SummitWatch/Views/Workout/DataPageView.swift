import SwiftUI

/// A customizable data screen: the athlete's metrics drawn in the arrangement
/// they chose — one to eight readouts across up to four rows.
struct DataPageView: View {
    let screen: WatchScreen
    let metrics: LiveMetrics
    let sport: WatchSport
    var onCustomize: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: layoutSpacing) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(.rect)
        // A long press now opens the workout controls, so editing the screen
        // lives on the controls themselves rather than competing with it here.
        .accessibilityAction(named: "Customize screen", onCustomize)
    }

    /// Every band claims an equal share of whatever height this watch has, so an
    /// eight-field screen fills a 49 mm Ultra and still fits a 40 mm without
    /// scrolling. The readouts inside shrink to their slot rather than the page
    /// growing past the bezel.
    @ViewBuilder
    private var content: some View {
        if screen.fields.isEmpty {
            emptyState
        } else {
            let layout = screen.resolvedLayout
            let bands = layout.slice(screen.fields)
            ForEach(Array(bands.enumerated()), id: \.offset) { index, fields in
                if index > 0 {
                    divider
                }
                band { row(fields, size: MetricCell.Size(layout.emphasis(forRow: index))) }
            }
        }
    }

    private func band<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var layoutSpacing: CGFloat {
        WatchDisplay.spacing(screen.resolvedLayout.rows.count >= 3 ? 4 : 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(WatchTheme.border)
            .frame(height: 0.5)
    }

    private var emptyState: some View {
        VStack(spacing: WatchDisplay.spacing(6)) {
            Image(systemName: "square.grid.2x2")
                .font(.title3)
                .foregroundStyle(WatchTheme.textSecondary)
            Text("No metrics on this screen")
                .font(.watch(12))
                .foregroundStyle(WatchTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Add metrics", action: onCustomize)
                .font(.watch(12, weight: .semibold))
                .tint(WatchTheme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ fields: [WatchDataField], size: MetricCell.Size) -> some View {
        HStack(alignment: .top, spacing: WatchDisplay.spacing(8)) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                cell(field, size: size)
            }
        }
    }

    private func cell(_ field: WatchDataField, size: MetricCell.Size) -> some View {
        MetricCell(
            field: field,
            value: field.value(from: metrics),
            size: size,
            tint: tint(for: field)
        )
    }

    /// Heart-rate readouts take the colour of the zone they are sitting in.
    private func tint(for field: WatchDataField) -> Color {
        switch field {
        case .heartRate, .heartRateZone, .percentMaxHeartRate:
            metrics.heartRate > 0 ? WatchTheme.zoneColor(metrics.heartRateZone) : WatchTheme.textPrimary
        case .pace, .speed, .gradeAdjustedPace:
            WatchTheme.textPrimary
        case .ascent, .grade, .verticalSpeed, .altitude:
            WatchTheme.highlight
        case .remainingDistance, .eta, .distanceToWaypoint, .nextWaypoint, .offCourse:
            WatchTheme.accent
        default:
            WatchTheme.textPrimary
        }
    }
}
