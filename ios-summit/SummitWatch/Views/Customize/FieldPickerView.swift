import SwiftUI

/// Browsable catalogue of every metric, grouped and showing a sample value so
/// it is obvious what each one looks like on a page.
struct FieldPickerView: View {
    let sport: WatchSport
    var title: String = "Metric"
    var onSelect: (WatchDataField) -> Void

    var body: some View {
        List {
            ForEach(WatchFieldGroup.allCases) { group in
                let fields = available(in: group)
                if !fields.isEmpty {
                    Section {
                        ForEach(fields) { field in
                            Button {
                                onSelect(field)
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(field.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(WatchTheme.textPrimary)
                                            .lineLimit(1)
                                        Text(field.label)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(WatchTheme.textSecondary)
                                    }
                                    Spacer(minLength: 4)
                                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                                        Text(field.previewValue)
                                            .font(.metric(13, weight: .semibold))
                                            .foregroundStyle(sport.tint)
                                        if !field.unit.isEmpty {
                                            Text(field.unit)
                                                .font(.system(size: 8))
                                                .foregroundStyle(WatchTheme.textSecondary)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        Label(group.title, systemImage: group.symbol)
                    }
                }
            }
        }
        .navigationTitle(title)
    }

    /// Hides metrics the sport can never produce, so the list stays honest.
    private func available(in group: WatchFieldGroup) -> [WatchDataField] {
        WatchDataField.fields(in: group).filter { field in
            if field.requiresRoute && !sport.supportsRoutes { return false }
            if group == .elevation && !sport.usesElevation { return false }
            switch field {
            case .power: return sport.family == .ride || sport.family == .water
            case .strideLength, .cadence, .averageCadence: return sport.family != .gym
            case .pace, .averagePace, .lapPace, .gradeAdjustedPace, .bestPace: return sport.estimatedSpeed > 0
            case .speed, .averageSpeed, .maxSpeed: return sport.estimatedSpeed > 0
            default: return true
            }
        }
    }
}
