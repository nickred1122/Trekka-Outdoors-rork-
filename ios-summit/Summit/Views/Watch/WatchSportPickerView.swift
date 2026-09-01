import SwiftUI

/// Chooses which activity's watch screens are being designed.
///
/// This used to be two horizontal scrollers stacked on top of each other on the
/// main screen — a row of families, then a row of tiles inside the chosen
/// family — which meant fifty-odd activities were permanently occupying the top
/// of a screen whose actual job is arranging pages. Choosing a sport is
/// something you do once and then forget, so it moves here, where a plain
/// searchable list handles fifty entries far better than a scroller ever could.
struct WatchSportPickerView: View {
    @Binding var selection: WatchSportProfile

    @Environment(WatchLayoutStore.self) private var layout
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    var body: some View {
        List {
            ForEach(families) { family in
                Section {
                    ForEach(sports(in: family)) { sport in
                        Button {
                            selection = sport
                            dismiss()
                        } label: {
                            row(sport)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(family.title)
                }
            }

            if families.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .searchable(text: $query, prompt: "Search activities")
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func row(_ sport: WatchSportProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sport.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(sport.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(sport.title)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if layout.isCustomized(sport) {
                    Text("Custom screens")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
            }

            Spacer(minLength: 0)

            if sport == selection {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .contentShape(.rect)
    }

    /// Families that still have something in them once the search is applied,
    /// so an empty heading never hangs over an empty section.
    private var families: [WatchSportFamily] {
        WatchSportFamily.allCases.filter { !sports(in: $0).isEmpty }
    }

    private func sports(in family: WatchSportFamily) -> [WatchSportProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return family.sports }
        return family.sports.filter {
            $0.title.localizedStandardContains(trimmed)
        }
    }
}
