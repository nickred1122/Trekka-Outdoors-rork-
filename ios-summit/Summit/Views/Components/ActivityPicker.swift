import SwiftUI

/// A full-screen browser for choosing an activity.
///
/// The catalogue is too long to scan as a flat list, so it opens on the
/// families and drills into one, exactly as the watch does. Typing searches
/// every activity at once and skips the families entirely.
struct ActivityPicker: View {
    @Environment(\.dismiss) private var dismiss

    /// Limits the list to activities a route can be planned for.
    var routableOnly: Bool = false
    @Binding var selection: RouteActivityType

    @State private var query = ""
    @State private var openFamily: WatchSportFamily?

    private var catalogue: [RouteActivityType] {
        routableOnly ? RouteActivityType.routable : RouteActivityType.allCases
    }

    private var matches: [RouteActivityType] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return catalogue
            .filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var families: [RouteActivityType.Group] {
        RouteActivityType.groups(of: catalogue)
    }

    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if matches.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .listRowBackground(Color.clear)
                    } else {
                        Section {
                            ForEach(matches) { activity in
                                row(activity)
                            }
                        }
                    }
                } else {
                    ForEach(families) { group in
                        Section {
                            ForEach(group.activities) { activity in
                                row(activity)
                            }
                        } header: {
                            Label(group.family.title, systemImage: group.family.symbol)
                                .foregroundStyle(group.family.tint)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search activities")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ activity: RouteActivityType) -> some View {
        Button {
            selection = activity
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: activity.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(activity.tint)
                    .frame(width: 26)
                Text(activity.title)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if selection == activity {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == activity ? [.isButton, .isSelected] : .isButton)
    }
}

/// A compact control that shows the chosen activity and opens the browser.
struct ActivityPickerButton: View {
    var routableOnly: Bool = false
    @Binding var selection: RouteActivityType

    @State private var showsPicker = false

    var body: some View {
        Button {
            showsPicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selection.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(selection.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(selection.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(selection.family.title)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.surface, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showsPicker) {
            ActivityPicker(routableOnly: routableOnly, selection: $selection)
        }
    }
}
