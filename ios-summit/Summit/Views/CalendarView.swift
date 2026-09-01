import SwiftUI

/// Training calendar: a month of load at a glance, with the day's sessions below.
struct CalendarView: View {
    @Environment(RouteStore.self) private var store
    @Environment(HealthService.self) private var health
    @Binding var path: NavigationPath

    @State private var monthAnchor: Date = Date()
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var feedback = 0

    private let calendar = Calendar.current

    private var activities: [ActivityRecord] {
        ActivityFeed.merged(store: store, health: health)
    }

    /// Sessions grouped by the day they started.
    private var byDay: [Date: [ActivityRecord]] {
        Dictionary(grouping: activities) { calendar.startOfDay(for: $0.startDate) }
    }

    private var monthActivities: [ActivityRecord] {
        guard let interval = calendar.dateInterval(of: .month, for: monthAnchor) else { return [] }
        return activities.filter { interval.contains($0.startDate) }
    }

    private var selectedActivities: [ActivityRecord] {
        (byDay[selectedDay] ?? []).sorted { $0.startDate < $1.startDate }
    }

    /// Longest run of consecutive days ending today (or yesterday) with a session.
    private var streak: Int {
        var count = 0
        var cursor = calendar.startOfDay(for: Date())
        if byDay[cursor] == nil {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        while byDay[cursor] != nil {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// Busiest day of the month, used to scale the heat of every cell.
    private var peakLoad: Double {
        monthActivities
            .reduce(into: [Date: Double]()) { totals, activity in
                totals[calendar.startOfDay(for: activity.startDate), default: 0] += activity.duration
            }
            .values
            .max() ?? 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthHeader
                monthStats
                weekdayHeader
                monthGrid
                streakRow
                dayPanel
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, TabBarMetrics.scrollInset)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .sensoryFeedback(.selection, trigger: feedback)
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack(spacing: 12) {
            stepButton(symbol: "chevron.left", label: "Previous month") { step(-1) }

            VStack(spacing: 1) {
                Text(monthAnchor, format: .dateTime.month(.wide))
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(monthAnchor, format: .dateTime.year())
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .contentTransition(.numericText())

            stepButton(symbol: "chevron.right", label: "Next month") { step(1) }
        }
        .overlay(alignment: .trailing) {
            if !calendar.isDate(monthAnchor, equalTo: Date(), toGranularity: .month) {
                Button("Today") {
                    withAnimation(.snappy(duration: 0.25)) {
                        monthAnchor = Date()
                        selectedDay = calendar.startOfDay(for: Date())
                    }
                    feedback += 1
                }
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(Theme.accent)
                .offset(y: 34)
            }
        }
    }

    private func stepButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: .circle)
                .overlay { Circle().strokeBorder(Theme.border, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var monthStats: some View {
        StatStrip(items: [
            StatItem(
                symbol: "figure.run",
                label: "Sessions",
                value: "\(monthActivities.count)",
                unit: ""
            ),
            StatItem(
                symbol: "arrow.left.and.right",
                label: "Distance",
                value: Formatters.distance(monthActivities.reduce(0) { $0 + $1.distance }),
                unit: Formatters.units.distanceUnit
            ),
            StatItem(
                symbol: "arrow.up.forward",
                label: "Climbed",
                value: Formatters.elevation(monthActivities.reduce(0) { $0 + $1.elevationGain }),
                unit: Formatters.units.elevationUnit
            ),
        ])
    }

    // MARK: - Grid

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(monthDays) { day in
                if let date = day.date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
        .id(calendar.dateInterval(of: .month, for: monthAnchor)?.start ?? monthAnchor)
        .transition(.opacity)
    }

    private func dayCell(_ date: Date) -> some View {
        let sessions = byDay[date] ?? []
        let load = sessions.reduce(0) { $0 + $1.duration }
        let heat = peakLoad > 0 ? min(1, load / peakLoad) : 0
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)

        return Button {
            withAnimation(.snappy(duration: 0.25)) { selectedDay = date }
            feedback += 1
        } label: {
            VStack(spacing: 3) {
                Text(date, format: .dateTime.day())
                    .font(.system(size: 13, weight: isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(dayNumberColor(hasSessions: !sessions.isEmpty, isToday: isToday))

                HStack(spacing: 2) {
                    ForEach(Array(sessions.prefix(3).enumerated()), id: \.offset) { _, session in
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.accent.opacity(0.06 + heat * 0.4))
                    .opacity(sessions.isEmpty ? 0 : 1)
            }
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.surface.opacity(sessions.isEmpty ? 0.55 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Theme.textPrimary.opacity(0.85) : (isToday ? Theme.accent : .clear),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: date, sessions: sessions))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func dayNumberColor(hasSessions: Bool, isToday: Bool) -> Color {
        if isToday { return Theme.accent }
        return Theme.textPrimary.opacity(hasSessions ? 0.95 : 0.4)
    }

    private var streakRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(streak > 0 ? Theme.accent : Theme.textPrimary.opacity(0.3))
            Text(streak > 0 ? "\(streak)-day streak" : "No active streak")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(streak > 0 ? "Keep it alive" : "Log a session to start one")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
        .padding(14)
        .panel()
    }

    // MARK: - Day detail

    private var dayPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedDay, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !selectedActivities.isEmpty {
                    Text("\(selectedActivities.count) session\(selectedActivities.count == 1 ? "" : "s")")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }

            if selectedActivities.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textPrimary.opacity(0.35))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest day")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Recovery is training too.")
                            .font(.caption)
                            .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel()
                .transition(.opacity)
            } else {
                ForEach(selectedActivities) { activity in
                    Button {
                        path.append(activity)
                    } label: {
                        ActivityRow(activity: activity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Helpers

    private struct MonthDay: Identifiable {
        let id: Int
        let date: Date?
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var monthDays: [MonthDay] {
        guard let interval = calendar.dateInterval(of: .month, for: monthAnchor),
              let range = calendar.range(of: .day, in: .month, for: monthAnchor) else { return [] }
        let first = interval.start
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var days: [MonthDay] = (0..<leading).map { MonthDay(id: -($0 + 1), date: nil) }
        for offset in 0..<range.count {
            days.append(MonthDay(id: offset, date: calendar.date(byAdding: .day, value: offset, to: first)))
        }
        return days
    }

    private func step(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: monthAnchor) else { return }
        withAnimation(.snappy(duration: 0.25)) { monthAnchor = next }
        feedback += 1
    }

    private func accessibilityLabel(for date: Date, sessions: [ActivityRecord]) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if sessions.isEmpty { return "\(day), rest day" }
        return "\(day), \(sessions.count) session\(sessions.count == 1 ? "" : "s")"
    }
}
