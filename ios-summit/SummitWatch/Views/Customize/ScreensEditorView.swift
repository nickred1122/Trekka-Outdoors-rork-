import SwiftUI

/// Page stack editor for one sport: reorder, enable, add and remove screens.
struct ScreensEditorView: View {
    let sport: WatchSport

    @Environment(WatchScreenSettings.self) private var settings
    @State private var showsAddSheet = false
    @State private var showsResetConfirmation = false

    private var screens: [WatchScreen] {
        settings.screens(for: sport)
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(screens.enumerated()), id: \.element.id) { index, screen in
                    NavigationLink {
                        ScreenDetailEditorView(sport: sport, screenID: screen.id)
                    } label: {
                        screenRow(screen, index: index)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(screen.isEnabled ? WatchTheme.surface : WatchTheme.surface.opacity(0.4))
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            settings.removeScreen(id: screen.id, from: sport)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            settings.toggleScreen(id: screen.id, for: sport)
                        } label: {
                            Label(screen.isEnabled ? "Hide" : "Show", systemImage: screen.isEnabled ? "eye.slash" : "eye")
                        }
                        .tint(WatchTheme.highlight)
                    }
                }
            } header: {
                Text("Pages in order")
            } footer: {
                Text("Swipe a page to hide or remove it. Open one to reorder or change its metrics.")
                    .font(.system(size: 10))
            }

            Section {
                Button {
                    showsAddSheet = true
                } label: {
                    Label("Add page", systemImage: "plus.circle.fill")
                        .foregroundStyle(WatchTheme.accent)
                }

                if settings.isCustomized(sport) {
                    Button(role: .destructive) {
                        showsResetConfirmation = true
                    } label: {
                        Label("Reset to default", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
        .navigationTitle(sport.title)
        .containerBackground(sport.tint.gradient, for: .navigation)
        .sheet(isPresented: $showsAddSheet) {
            NavigationStack {
                AddScreenView(sport: sport)
            }
        }
        .confirmationDialog("Reset \(sport.title) screens?", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { settings.resetScreens(for: sport) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func screenRow(_ screen: WatchScreen, index: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: screen.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(screen.isEnabled ? sport.tint : WatchTheme.textSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(screen.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(screen.isEnabled ? WatchTheme.textPrimary : WatchTheme.textSecondary)
                    .lineLimit(1)
                Text(screen.summary)
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if !screen.isEnabled {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Picker for adding a new page to a sport's stack.
struct AddScreenView: View {
    let sport: WatchSport

    @Environment(WatchScreenSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Data screens") {
                ForEach(dataPresets, id: \.name) { preset in
                    Button {
                        settings.addScreen(.data(preset.fields, layout: preset.layout), to: sport)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            WatchLayoutDiagram(layout: preset.layout, tint: sport.tint, isSelected: true)
                                .frame(width: 22, height: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WatchTheme.textPrimary)
                                Text(preset.fields.isEmpty
                                     ? "Start from nothing"
                                     : preset.fields.map(\.label.capitalized).joined(separator: " · "))
                                    .font(.system(size: 9))
                                    .foregroundStyle(WatchTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            Section("Special pages") {
                ForEach(WatchScreenKind.allCases.filter { $0 != .data }) { kind in
                    Button {
                        settings.addScreen(.page(kind), to: sport)
                        dismiss()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WatchTheme.textPrimary)
                                Text(kind.detail)
                                    .font(.system(size: 9))
                                    .foregroundStyle(WatchTheme.textSecondary)
                                    .lineLimit(2)
                            }
                        } icon: {
                            Image(systemName: kind.symbol)
                                .foregroundStyle(sport.tint)
                        }
                    }
                }
            }
        }
        .navigationTitle("Add Page")
    }

    /// Starting points, each with the shape it is meant to be read in. Every one
    /// can be rearranged afterwards.
    private var dataPresets: [(name: String, fields: [WatchDataField], layout: WatchScreenLayout?)] {
        let tempo: WatchDataField = sport.usesPace ? .pace : .speed
        return [
            ("Single big number", [tempo], WatchScreenLayout(rows: [1])),
            ("Classic three", [.duration, .distance, tempo], WatchScreenLayout(rows: [1, 2])),
            ("Four up", [.duration, .distance, tempo, .heartRate], WatchScreenLayout(rows: [2, 2])),
            ("One, pair, one", [tempo, .distance, .heartRate, .duration], WatchScreenLayout(rows: [1, 2, 1])),
            ("Climbing", [.grade, .ascent, .altitude, .verticalSpeed], WatchScreenLayout(rows: [1, 3])),
            ("Lap focus", [.lapTime, .lapDistance, .lapPace, .averageHeartRate], WatchScreenLayout(rows: [2, 2])),
            ("Navigation", [.eta, .remainingDistance, .distanceToWaypoint, .nextWaypoint], WatchScreenLayout(rows: [1, 2, 1])),
            ("Everything", [.duration, .distance, tempo, .heartRate, .ascent, .calories], WatchScreenLayout(rows: [2, 2, 2])),
            ("Blank screen", [], nil),
        ]
    }
}
