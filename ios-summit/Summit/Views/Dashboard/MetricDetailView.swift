import Charts
import SwiftUI

/// Full breakdown of one dashboard metric: history at any range, statistics,
/// meaning and the workouts that produced it.
struct MetricDetailView: View {
    let metric: DashboardMetric

    @Environment(HealthService.self) private var health
    @Environment(RouteStore.self) private var store
    @Environment(DashboardSettings.self) private var settings

    @State private var selectedIndex: Int?
    /// The day the whole screen is scoped to. Ranges longer than a day end here.
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showsCalendar = false

    private var calendar: Calendar { Calendar.current }

    private var isToday: Bool { calendar.isDateInToday(selectedDate) }

    /// The last day the screen covers, resolved straight from the picked dates.
    ///
    /// This deliberately does not read `window`: the window is clamped against
    /// the ranges the data supports, those ranges are measured from `activities`,
    /// and `activities` are cut off at this date — asking `window` here would
    /// close that loop and recurse until the stack ran out.
    private var referenceDay: Date {
        settings.chartSpan?.end ?? calendar.startOfDay(for: selectedDate)
    }

    /// Today runs up to this minute; a past day is read in full.
    private var referenceDate: Date {
        guard !calendar.isDateInToday(referenceDay) else { return Date() }
        return calendar.date(byAdding: .hour, value: 23, to: referenceDay) ?? referenceDay
    }

    /// A year back is as far as the Health history reaches.
    private var earliestDate: Date {
        calendar.date(byAdding: .day, value: -(MetricSeries.historyDayCount - 1), to: calendar.startOfDay(for: Date()))
            ?? selectedDate
    }

    private var activities: [ActivityRecord] {
        let combined = store.recentActivities + health.healthActivities
        return combined
            .filter { $0.startDate <= referenceDate }
            .sorted { $0.startDate > $1.startDate }
    }

    private var reading: MetricReading? {
        guard isToday, window.span == nil else { return nil }
        return MetricReadings.build(snapshot: health.snapshot, activities: activities)[metric]
    }

    /// Ranges this metric has enough recorded history to justify.
    private var availableRanges: [MetricRange] {
        MetricRange.available(
            forDays: MetricSeries.coverageDays(
                metric: metric,
                history: health.history,
                activities: activities,
                reference: Date()
            )
        )
    }

    /// What the screen is scoped to: the hand-picked dates if there are any,
    /// else the preset ending on the day being scrubbed to.
    private var window: MetricWindow {
        settings.window(endingOn: selectedDate, allowing: availableRanges)
    }

    private var range: MetricRange { window.range }

    private var samples: [MetricSample] {
        MetricSeries.samples(
            metric: metric,
            window: window,
            history: health.history(for: window.hourlyDay ?? selectedDate),
            activities: activities
        )
    }

    private var dayLabel: String {
        if isToday { return "Today" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var shortDate: String {
        selectedDate.formatted(.dateTime.day().month(.abbreviated))
    }

    private var headlineCaption: String {
        guard window.span == nil else { return metric.headlineCaption(for: window) }
        guard !isToday else { return metric.headlineCaption(for: range) }
        if range == .day { return dayLabel }
        return "\(metric.headlineCaption(for: range)) to \(shortDate)"
    }

    private var rangeCaption: String { window.caption }

    var body: some View {
        ScrollView {
            let samples = samples
            VStack(spacing: 14) {
                hero(samples)
                // Hand-picked dates already say which days are covered, so the
                // day stepper would be a second, competing answer.
                if window.span == nil {
                    dayStepper
                }
                rangePicker
                chartCard(samples)
                statsCard(samples)
                if metric.isActivityDerived {
                    contributionsCard
                }
                explainerCard
                sourceFooter
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .scrollIndicators(.hidden)
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    settings.toggle(metric)
                } label: {
                    Image(systemName: settings.isVisible(metric) ? "pin.fill" : "pin.slash")
                        .foregroundStyle(settings.isVisible(metric) ? Theme.accent : Theme.textPrimary.opacity(0.6))
                }
                .accessibilityLabel(settings.isVisible(metric) ? "Remove from dashboard" : "Add to dashboard")
            }
        }
        .refreshable { await health.refresh() }
        .onAppear { settings.markExplored() }
        .onChange(of: window) { _, _ in selectedIndex = nil }
        // Past days are pulled from Health on demand, then cached.
        .task(id: window) {
            guard let day = window.hourlyDay else { return }
            await health.loadDay(day)
        }
        .sheet(isPresented: $showsCalendar) {
            calendarSheet
        }
    }

    // MARK: - Day scrubbing

    /// Steps the whole screen back and forward a day at a time. Tapping the
    /// date opens a calendar for longer jumps.
    private var dayStepper: some View {
        HStack(spacing: 6) {
            dayStepButton(systemImage: "chevron.left", label: "Previous day", isEnabled: selectedDate > earliestDate) {
                shiftDay(by: -1)
            }

            Button {
                showsCalendar = true
            } label: {
                VStack(spacing: 1) {
                    Text(dayLabel)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                    Text(isToday ? "Tap to pick a day" : selectedDate.formatted(.dateTime.year()))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            dayStepButton(systemImage: "chevron.right", label: "Next day", isEnabled: !isToday) {
                shiftDay(by: 1)
            }

            if !isToday {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selectedDate = calendar.startOfDay(for: Date())
                    }
                } label: {
                    Text("Today")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.canvas)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Theme.accent, in: .capsule)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 6)
        .panel(radius: 14)
        .animation(.snappy(duration: 0.25), value: isToday)
        .sensoryFeedback(.selection, trigger: selectedDate)
    }

    private func dayStepButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isEnabled ? Theme.accent : Theme.textPrimary.opacity(0.2))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    private func shiftDay(by days: Int) {
        guard let moved = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        let clamped = min(max(moved, earliestDate), calendar.startOfDay(for: Date()))
        withAnimation(.snappy(duration: 0.25)) { selectedDate = clamped }
    }

    private var calendarSheet: some View {
        NavigationStack {
            DatePicker(
                "Day",
                selection: $selectedDate,
                in: earliestDate...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .tint(Theme.accent)
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.canvas)
            .navigationTitle("Pick a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsCalendar = false }
                        .tint(Theme.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Hero

    private func hero(_ samples: [MetricSample]) -> some View {
        let headline = MetricSeries.headline(metric: metric, window: window, samples: samples)
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                TrekkaIcon(metric.glyph, size: 14, tint: metric.tint)
                Text(headlineCaption.uppercased())
                    .font(.system(.caption2, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(metric.valueText(headline))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                if headline > 0, let unit = metric.unitText {
                    Text(unit)
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .animation(.snappy(duration: 0.3), value: headline)

            if let insight = reading?.insight {
                Text(insight)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(metric.tint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(
                    LinearGradient(
                        colors: [metric.tint.opacity(0.18), Theme.surface],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(metric.tint.opacity(0.25), lineWidth: 1)
        }
    }

    private var rangePicker: some View {
        @Bindable var settings = settings
        return MetricWindowBar(
            range: $settings.chartRange,
            span: $settings.chartSpan,
            ranges: availableRanges,
            usesFullTitles: true,
            caption: coverageHint ?? window.caption,
            earliest: earliestDate
        )
    }

    /// Says what is still missing before a longer preset can tell the truth.
    private var coverageHint: String? {
        guard window.span == nil,
              let next = MetricRange.allCases.first(where: { !availableRanges.contains($0) })
        else { return nil }
        let days = MetricSeries.coverageDays(
            metric: metric,
            history: health.history,
            activities: activities
        )
        let missing = max(1, next.minimumDaysOfData - days)
        return "\(next.title) needs \(missing) more day\(missing == 1 ? "" : "s") of \(metric.title.lowercased()) data."
    }

    // MARK: - Chart

    @ViewBuilder
    private func chartCard(_ samples: [MetricSample]) -> some View {
        let average = MetricSeries.average(metric: metric, samples: samples)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(rangeCaption)
                    .metricLabelStyle()
                Spacer(minLength: 8)
            }

            HStack {
                if let selectedIndex, let sample = samples.first(where: { $0.index == selectedIndex }) {
                    Text("\(sample.title) · \(metric.seriesLabel(sample.value))")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(metric.tint)
                } else if average > 0 {
                    Text("\(window.bucketNoun.capitalized) average \(metric.seriesLabel(average))")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 16)

            if samples.contains(where: { $0.value > 0 }) {
                chart(samples, average: average)
            } else {
                Text("No \(metric.title.lowercased()) samples in this window.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 140)
            }
        }
        .padding(14)
        .panel()
    }

    private func chart(_ samples: [MetricSample], average: Double) -> some View {
        Chart {
            ForEach(samples) { sample in
                LineMark(
                    x: .value("Bucket", sample.index),
                    y: .value(metric.title, sample.value)
                )
                // Monotone, not catmullRom: a Catmull-Rom spline overshoots
                // the points it joins, so between two close values the curve
                // bulges below the y domain and draws past the x axis.
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .foregroundStyle(metric.tint)

                AreaMark(
                    x: .value("Bucket", sample.index),
                    y: .value(metric.title, sample.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [metric.tint.opacity(0.28), metric.tint.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                if samples.count <= 14 || sample.index == selectedIndex {
                    PointMark(
                        x: .value("Bucket", sample.index),
                        y: .value(metric.title, sample.value)
                    )
                    .symbolSize(selectedIndex == sample.index ? 90 : 26)
                    .foregroundStyle(metric.tint)
                }
            }

            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.textPrimary.opacity(0.28))
            }
        }
        .chartXScale(domain: -0.6...(Double(samples.count) - 0.4))
        .chartYScale(domain: yDomain(samples.map(\.value)))
        .chartPlotStyle { plot in
            // Keeps every mark inside the axes even when the renderer rounds a
            // stroke width or a symbol past the edge of the domain.
            plot.clipped()
        }
        .chartXAxis {
            AxisMarks(values: axisTicks(samples)) { value in
                AxisValueLabel {
                    if let index = value.as(Int.self),
                       let sample = samples.first(where: { $0.index == index }) {
                        Text(sample.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.border)
                AxisValueLabel()
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
            }
        }
        .frame(height: 180)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                selectedIndex = index(at: drag.location, proxy: proxy, geometry: geometry, samples: samples)
                            }
                            .onEnded { _ in selectedIndex = nil }
                    )
            }
        }
        .sensoryFeedback(.selection, trigger: selectedIndex)
        .animation(.easeInOut(duration: 0.28), value: window)
    }

    /// One label every `axisStride` buckets so dense ranges stay readable.
    private func axisTicks(_ samples: [MetricSample]) -> [Int] {
        let stride = window.axisStride(bucketCount: samples.count)
        return samples.map(\.index).filter { $0 % stride == 0 }
    }

    private func index(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        samples: [MetricSample]
    ) -> Int? {
        guard !samples.isEmpty, let plotFrame = proxy.plotFrame else { return nil }
        let frame = geometry[plotFrame]
        let relative = location.x - frame.minX
        guard relative >= 0, relative <= frame.width else { return nil }
        let step = frame.width / CGFloat(samples.count)
        let bucket = min(samples.count - 1, max(0, Int(relative / step)))
        return samples[bucket].index
    }

    private func yDomain(_ values: [Double]) -> ClosedRange<Double> {
        let populated = values.filter { $0 > 0 }
        guard let minimum = populated.min(), let maximum = populated.max() else { return 0...1 }
        let padding = max((maximum - minimum) * 0.35, maximum * 0.05, 0.5)
        return max(0, minimum - padding)...(maximum + padding)
    }

    // MARK: - Stats

    private func statsCard(_ samples: [MetricSample]) -> some View {
        let average = MetricSeries.average(metric: metric, samples: samples)
        let best = MetricSeries.best(metric: metric, samples: samples)
        let low = MetricSeries.low(metric: metric, samples: samples)
        return HStack(spacing: 0) {
            statColumn("\(window.summaryLabel) avg", value: average > 0 ? metric.seriesLabel(average) : "--")
            divider
            statColumn("Best \(window.bucketNoun)", value: best > 0 ? metric.seriesLabel(best) : "--")
            divider
            statColumn("Low \(window.bucketNoun)", value: low > 0 ? metric.seriesLabel(low) : "--")
        }
        .padding(.vertical, 14)
        .panel()
    }

    private func statColumn(_ label: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .metricLabelStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.metric(17))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1, height: 30)
    }

    // MARK: - Contributions

    private var contributionsCard: some View {
        let interval = window.dateInterval
        let contributors = activities.filter { interval.contains($0.startDate) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("What built this")
                    .metricLabelStyle()
                Spacer()
                if contributors.count > 6 {
                    Text("\(contributors.count) workouts")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                }
            }

            if contributors.isEmpty {
                Text("No workouts recorded in this window.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            } else {
                ForEach(contributors.prefix(6)) { activity in
                    NavigationLink(value: activity) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.name)
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text(activity.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                            }
                            Spacer(minLength: 0)
                            Text(contribution(of: activity))
                                .font(.metric(14))
                                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.textPrimary.opacity(0.28))
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func contribution(of activity: ActivityRecord) -> String {
        switch metric {
        case .distance: String(format: "%.1f km", activity.distance / 1000)
        case .elevation: "\(Formatters.elevation(activity.elevationGain)) m"
        case .calories: "\(Formatters.integer(activity.calories))"
        case .pace: Formatters.pace(activity.averagePace)
        case .load: "\(Int(((activity.duration / 60) * max(1, activity.averageHeartRate / 100)).rounded()))"
        default: Formatters.compactDuration(activity.duration)
        }
    }

    // MARK: - Explainer

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What this means", systemImage: "info.circle.fill")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(metric.explainer)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var sourceFooter: some View {
        Label(
            health.hasHealthData
                ? "Read from Apple Health on this device"
                : "Connect Apple Health to see your own numbers",
            systemImage: health.hasHealthData ? "heart.text.square" : "exclamationmark.circle"
        )
        .font(.caption2)
        .foregroundStyle(Theme.textPrimary.opacity(0.45))
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }
}
