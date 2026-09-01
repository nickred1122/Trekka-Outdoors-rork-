import SwiftUI

/// Picks the exact dates every dashboard chart covers: one day, or a span.
///
/// Nothing here reaches further back than the stored history, so a window can
/// only ever be set over days the app can actually read.
struct DateWindowSheet: View {
    @Binding var span: MetricSpan?
    /// As far back as the stored history reaches.
    let earliest: Date

    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case day
        case range

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: "Single day"
            case .range: "Date range"
            }
        }
    }

    @State private var mode: Mode
    @State private var day: Date
    @State private var start: Date
    @State private var end: Date

    init(span: Binding<MetricSpan?>, earliest: Date) {
        _span = span
        self.earliest = earliest

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let existing = span.wrappedValue
        let fallbackStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today

        _mode = State(initialValue: (existing?.isSingleDay ?? true) ? .day : .range)
        _day = State(initialValue: existing?.end ?? today)
        _start = State(initialValue: existing?.start ?? fallbackStart)
        _end = State(initialValue: existing?.end ?? today)
    }

    private var calendar: Calendar { Calendar.current }

    private var today: Date { calendar.startOfDay(for: Date()) }

    /// The window as it stands, which is exactly what applying will save.
    private var resolved: MetricSpan {
        mode == .day ? MetricSpan(start: day, end: day) : MetricSpan(start: start, end: end)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case .day:
                        dayPicker
                    case .range:
                        rangePicker
                        shortcuts
                    }

                    summary
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Theme.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle(mode == .day ? "Pick a day" : "Pick a range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(Theme.textPrimary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        span = resolved
                        dismiss()
                    }
                    .font(.system(.body, weight: .semibold))
                    .tint(Theme.accent)
                }
            }
            .onChange(of: start) { _, newValue in
                // A range cannot end before it starts.
                if end < newValue { end = newValue }
            }
        }
        .presentationDetents([.large])
        .sensoryFeedback(.selection, trigger: mode)
    }

    private var dayPicker: some View {
        DatePicker(
            "Day",
            selection: $day,
            in: earliest...Date(),
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .tint(Theme.accent)
        .padding(6)
        .panel()
    }

    private var rangePicker: some View {
        VStack(spacing: 12) {
            DatePicker("From", selection: $start, in: earliest...Date(), displayedComponents: .date)
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
            DatePicker("To", selection: $end, in: start...Date(), displayedComponents: .date)
        }
        .font(.system(.subheadline, weight: .medium))
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
        .padding(14)
        .panel()
    }

    /// The ranges people actually ask for, one tap each.
    private var shortcuts: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
            shortcut("Last 7 days", days: 7)
            shortcut("Last 14 days", days: 14)
            shortcut("Last 30 days", days: 30)
            shortcut("Last 90 days", days: 90)
            shortcutButton("This month", start: startOfMonth(of: today), end: today)
            shortcutButton("Year to date", start: startOfYear(of: today), end: today)
        }
    }

    private func shortcut(_ title: String, days: Int) -> some View {
        let from = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        return shortcutButton(title, start: from, end: today)
    }

    private func shortcutButton(_ title: String, start newStart: Date, end newEnd: Date) -> some View {
        let clampedStart = max(newStart, calendar.startOfDay(for: earliest))
        let isActive = calendar.isDate(start, inSameDayAs: clampedStart)
            && calendar.isDate(end, inSameDayAs: newEnd)
        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                start = clampedStart
                end = newEnd
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? Theme.accent : Theme.textPrimary.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    isActive ? Theme.accent.opacity(0.14) : Theme.surface,
                    in: .rect(cornerRadius: 11)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(isActive ? Theme.accent.opacity(0.45) : Theme.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var summary: some View {
        let window = MetricWindow.span(resolved)
        return VStack(spacing: 6) {
            Text(resolved.title.uppercased())
                .font(.system(.caption2, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            Text(window.caption)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(bucketNote(for: resolved))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if span != nil {
                Button {
                    span = nil
                    dismiss()
                } label: {
                    Text("Use rolling windows instead")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .panel()
    }

    /// Says plainly how the picked days will be grouped on the chart.
    private func bucketNote(for span: MetricSpan) -> String {
        switch MetricSeries.bucketDays(for: span) {
        case 0: "Plotted hour by hour."
        case 1: "Plotted one bar per day."
        case 7: "Plotted one bar per week, with the last bar cut to the end of your range."
        default: "Plotted one bar per month, with the last bar cut to the end of your range."
        }
    }

    private func startOfMonth(of date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func startOfYear(of date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
    }
}
