import SwiftUI

/// Typeface, weight and colour for every metric readout on the watch.
///
/// The preview at the top is the point of the screen: these are choices about
/// legibility at arm's length, and nobody can judge them from a list of names.
struct MetricStyleWatchView: View {
    @Environment(WatchScreenSettings.self) private var settings

    var body: some View {
        List {
            Section {
                preview
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2))
            }

            Section("Typeface") {
                ForEach(MetricTypeface.allCases) { face in
                    Button {
                        settings.metricTypeface = face
                    } label: {
                        row(
                            title: face.title,
                            detail: face.detail,
                            isSelected: settings.metricTypeface == face
                        ) {
                            Text("8:24")
                                .font(
                                    .system(
                                        size: WatchDisplay.fontSize(13),
                                        weight: .semibold,
                                        design: face.design
                                    )
                                    .monospacedDigit()
                                )
                                .foregroundStyle(WatchTheme.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Weight") {
                ForEach(MetricWeightChoice.allCases) { choice in
                    Button {
                        settings.metricWeight = choice
                    } label: {
                        row(
                            title: choice.title,
                            detail: nil,
                            isSelected: settings.metricWeight == choice
                        ) {
                            Text("124")
                                .font(
                                    .system(
                                        size: WatchDisplay.fontSize(13),
                                        weight: choice.apply(.semibold),
                                        design: settings.metricTypeface.design
                                    )
                                    .monospacedDigit()
                                )
                                .foregroundStyle(WatchTheme.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                ForEach(FieldTint.allCases) { tint in
                    Button {
                        settings.fieldTint = tint
                    } label: {
                        row(
                            title: tint.title,
                            detail: tint == .auto ? "Each page picks its own" : nil,
                            isSelected: settings.fieldTint == tint
                        ) {
                            Circle()
                                .fill(tint.swatch)
                                .frame(width: 11, height: 11)
                                .overlay {
                                    // Automatic is not one colour, so it is drawn
                                    // as a ring rather than pretending to be.
                                    if tint == .auto {
                                        Circle()
                                            .fill(WatchTheme.canvas)
                                            .frame(width: 5, height: 5)
                                    }
                                }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Value colour")
            } footer: {
                Text("Automatic keeps heart rate in its zone colour and warnings in amber. Any other choice paints every readout the same.")
                    .font(.system(size: 9))
            }
        }
        .navigationTitle("Metric style")
    }

    /// A real data page in miniature, drawn with the live settings.
    private var preview: some View {
        VStack(alignment: .leading, spacing: WatchDisplay.spacing(6)) {
            MetricCell(field: .duration, value: WatchFormat.duration(2_784), size: .large)
            HStack(spacing: WatchDisplay.spacing(8)) {
                MetricCell(field: .distance, value: WatchFormat.distance(8_420), size: .compact)
                MetricCell(
                    field: .heartRate,
                    value: "148",
                    size: .compact,
                    tint: WatchTheme.zoneColor(3)
                )
            }
        }
        .padding(WatchDisplay.spacing(9))
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchPanel()
    }

    private func row(
        title: String,
        detail: String?,
        isSelected: Bool,
        @ViewBuilder sample: () -> some View
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? WatchTheme.accent : WatchTheme.textSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(WatchTheme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 4)
            sample()
        }
        .contentShape(.rect)
    }
}
