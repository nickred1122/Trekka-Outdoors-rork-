import SwiftUI

/// How the watch's maps and metric screens look.
///
/// Set on the phone because choosing a colour or a typeface is a looking-at-it
/// decision, and a phone is a far easier place to make one than a wrist. The
/// choices travel to the watch in the same document as the pages.
struct WatchAppearanceView: View {
    @Environment(WatchLayoutStore.self) private var layout

    var body: some View {
        @Bindable var layout = layout

        List {
            Section {
                trailColorRow(
                    title: "Course line",
                    caption: "The route you planned",
                    selection: $layout.routeTrailColor
                )
                trailColorRow(
                    title: "Your trail",
                    caption: "The breadcrumb behind you",
                    selection: $layout.breadcrumbTrailColor
                )
            } header: {
                Text("Map lines")
            } footer: {
                Text("These apply to maps on both the phone and the watch.")
            }

            Section {
                Picker("Typeface", selection: $layout.metricTypeface) {
                    ForEach(MetricTypefaceOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                Picker("Weight", selection: $layout.metricWeight) {
                    ForEach(MetricWeightOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                Picker("Readout colour", selection: $layout.fieldTint) {
                    ForEach(MetricTintOption.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
            } header: {
                Text("Numbers")
            } footer: {
                Text("Applies to every metric on the watch's workout screens. Automatic tints each number by what it measures — heart rate red, pace orange — so a glance mid-effort lands on the right one.")
            }

            Section {
                Toggle("Satellite map", isOn: $layout.prefersHybridMap)
            } footer: {
                Text("Aerial imagery needs a signal. Trekka's own topographic map is the one stored for offline use, so switch this off for anywhere without coverage.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A colour choice shown as colour, not as a list of names.
    private func trailColorRow(
        title: String,
        caption: String,
        selection: Binding<TrailColor>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .foregroundStyle(Theme.textPrimary)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
                Spacer()
                Text(selection.wrappedValue.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selection.wrappedValue.color)
            }

            HStack(spacing: 10) {
                ForEach(TrailColor.allCases) { option in
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 26, height: 26)
                            .overlay {
                                Circle()
                                    .strokeBorder(
                                        Theme.textPrimary,
                                        lineWidth: selection.wrappedValue == option ? 2.5 : 0
                                    )
                                    .padding(-3)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(
                        selection.wrappedValue == option ? [.isSelected, .isButton] : .isButton
                    )
                }
            }
            .animation(.snappy(duration: 0.2), value: selection.wrappedValue)
        }
        .padding(.vertical, 4)
    }
}
