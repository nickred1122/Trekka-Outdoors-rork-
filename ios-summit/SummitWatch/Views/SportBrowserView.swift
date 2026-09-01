import SwiftUI

/// A family row in the Start list: what the group is, and how much is in it.
struct SportFamilyRow: View {
    let family: SportFamily

    var body: some View {
        HStack(spacing: 8) {
            // A tinted rule keeps each family recognisable without an icon.
            Capsule()
                .fill(family.tint)
                .frame(width: 3, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(family.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                Text(family.summary)
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
            Text("\(family.sports.count)")
                .font(.metric(11, weight: .semibold))
                .foregroundStyle(WatchTheme.textSecondary)
        }
        .padding(.vertical, 1)
    }
}

/// A single sport row, reused by every browser in the watch app.
struct SportPickerRow: View {
    @Environment(WatchScreenSettings.self) private var settings

    let sport: WatchSport
    /// Shown in the A–Z list, where the family is not obvious from context.
    var showsFamily: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(sport.tint)
                .frame(width: 3, height: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(sport.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WatchTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if showsFamily {
                    Text(sport.family.title)
                        .font(.system(size: 9))
                        .foregroundStyle(WatchTheme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if settings.isCustomized(sport) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 8))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        }
        .padding(.vertical, 1)
    }
}

/// Every sport inside one family, ready to start.
struct SportFamilyListView: View {
    let family: SportFamily

    var body: some View {
        List {
            Section {
                ForEach(family.sports) { sport in
                    NavigationLink(value: WatchStartRoute.sport(sport)) {
                        SportPickerRow(sport: sport)
                    }
                }
            } footer: {
                Text(family.summary)
                    .font(.system(size: 9))
                    .foregroundStyle(WatchTheme.textSecondary)
            }
        }
        .navigationTitle(family.title)
        .containerBackground(family.tint.gradient, for: .navigation)
    }
}

/// The whole roster in one alphabetical list, for when you know the name.
struct AllSportsListView: View {
    var body: some View {
        List {
            ForEach(WatchSport.alphabetical) { sport in
                NavigationLink(value: WatchStartRoute.sport(sport)) {
                    SportPickerRow(sport: sport, showsFamily: true)
                }
            }
        }
        .navigationTitle("All")
    }
}

/// Screen editors for one family, so Settings stays a short list.
struct SportFamilyScreensView: View {
    @Environment(WatchScreenSettings.self) private var settings

    let family: SportFamily

    var body: some View {
        List {
            ForEach(family.sports) { sport in
                NavigationLink {
                    ScreensEditorView(sport: sport)
                } label: {
                    HStack {
                        Text(sport.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if settings.isCustomized(sport) {
                            Text("Custom")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(WatchTheme.accent)
                        }
                    }
                }
            }
        }
        .navigationTitle(family.title)
    }
}
