import SwiftUI

/// The forecast for a planned route, and what it means for going out.
struct RouteWeatherCard: View {
    let route: PlannedRoute

    @Environment(\.unitSystem) private var units

    @State private var weather: RouteWeather?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let weather {
                current(weather)
                hourStrip(weather.hours)

                if let window = weather.bestWindow {
                    bestWindowRow(window)
                }

                if weather.hasSeparateSummit, let summit = weather.summitHours.first {
                    summitRow(weather: weather, summit: summit)
                }
            } else if isLoading {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else if let errorMessage {
                failure(errorMessage)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .task(id: route.id) { await load() }
    }

    private var header: some View {
        HStack {
            Text("Weather")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if weather != nil {
                Button {
                    Task { await load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh the forecast")
            }
        }
    }

    // MARK: - Now

    private func current(_ weather: RouteWeather) -> some View {
        Group {
            if let now = weather.now {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: now.symbolName)
                        .font(.system(size: 26, weight: .medium))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(temperature(now.temperature))
                            .font(.metric(24))
                            .foregroundStyle(Theme.textPrimary)
                        Text(now.conditionText)
                            .font(.system(.footnote, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.65))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 4) {
                        detail(
                            symbol: "wind",
                            text: "\(speed(now.windSpeed)) \(units == .metric ? "km/h" : "mph")"
                        )
                        detail(
                            symbol: "drop.fill",
                            text: "\(Int((now.precipitationChance * 100).rounded()))%"
                        )
                    }
                }
            }
        }
    }

    private func detail(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
            Text(text)
                .font(.metric(12))
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
        }
    }

    // MARK: - Hours

    private func hourStrip(_ hours: [RouteHourForecast]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(hours.prefix(14)) { hour in
                    VStack(spacing: 5) {
                        Text(hour.date.formatted(.dateTime.hour()))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        Image(systemName: hour.symbolName)
                            .font(.system(size: 14))
                            .symbolRenderingMode(.multicolor)
                            .frame(height: 18)
                        Text(temperature(hour.temperature))
                            .font(.metric(12))
                            .foregroundStyle(Theme.textPrimary)
                        // Only shown when rain is a real possibility, so the
                        // strip does not carry a column of zeroes on a clear day.
                        Text(hour.precipitationChance >= 0.15
                            ? "\(Int((hour.precipitationChance * 100).rounded()))%"
                            : " ")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color(red: 0.24, green: 0.55, blue: 0.98))
                    }
                    .opacity(hour.isDaylight ? 1 : 0.55)
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0)
    }

    // MARK: - Recommendations

    private func bestWindowRow(_ window: RouteWeatherWindow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.positive)
            VStack(alignment: .leading, spacing: 1) {
                Text("Best window")
                    .metricLabelStyle()
                Text(windowText(window))
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.positive.opacity(0.1), in: .rect(cornerRadius: 10))
    }

    private func windowText(_ window: RouteWeatherWindow) -> String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(window.start)
            ? "today"
            : calendar.isDateInTomorrow(window.start) ? "tomorrow" : window.start.formatted(.dateTime.weekday(.wide))
        let from = window.start.formatted(.dateTime.hour())
        let to = window.end.formatted(.dateTime.hour())
        let rain = Int((window.precipitationChance * 100).rounded())
        return "\(from)–\(to) \(day) · \(rain)% rain, \(speed(window.windSpeed)) \(units == .metric ? "km/h" : "mph") wind"
    }

    /// Says when the far end of the route is meaningfully worse than the start.
    ///
    /// Only shown when the difference is real. A car park in sun and a summit in
    /// cloud is the thing worth knowing; two forecasts that agree are noise.
    @ViewBuilder
    private func summitRow(weather: RouteWeather, summit: RouteHourForecast) -> some View {
        if let now = weather.now {
            let temperatureDrop = now.temperature - summit.temperature
            let windRise = summit.windSpeed - now.windSpeed
            if temperatureDrop > 2 || windRise > 8 {
                HStack(spacing: 8) {
                    Image(systemName: "mountain.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.highlight)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(weather.summitPlaceLabel)
                            .metricLabelStyle()
                        Text(summitText(temperatureDrop: temperatureDrop, windRise: windRise, summit: summit))
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Theme.highlight.opacity(0.1), in: .rect(cornerRadius: 10))
            }
        }
    }

    private func summitText(temperatureDrop: Double, windRise: Double, summit: RouteHourForecast) -> String {
        var parts: [String] = ["\(temperature(summit.temperature)) up there"]
        if temperatureDrop > 2 {
            let degrees = units == .metric ? temperatureDrop : temperatureDrop * 9 / 5
            parts.append("\(Int(degrees.rounded()))° colder")
        }
        if windRise > 8 {
            parts.append("\(speed(summit.windSpeed)) \(units == .metric ? "km/h" : "mph") wind")
        }
        return parts.joined(separator: " · ")
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(.footnote))
                .foregroundStyle(Theme.textPrimary.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") {
                Task { await load(force: true) }
            }
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Loading

    private func load(force: Bool = false) async {
        if !force, let cached = RouteWeatherService.shared.cached(for: route) {
            weather = cached
            return
        }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            weather = try await RouteWeatherService.shared.weather(for: route)
        } catch {
            weather = nil
            errorMessage = (error as? RouteWeatherError)?.errorDescription
                ?? "The forecast could not be loaded."
        }
    }

    // MARK: - Units

    /// WeatherKit is asked for Celsius and converted here, so the reading follows
    /// the same unit setting as every other number in the app.
    private func temperature(_ celsius: Double) -> String {
        let value = units == .metric ? celsius : celsius * 9 / 5 + 32
        return "\(Int(value.rounded()))°"
    }

    private func speed(_ kilometresPerHour: Double) -> String {
        let value = units == .metric ? kilometresPerHour : kilometresPerHour * 0.621371
        return "\(Int(value.rounded()))"
    }
}
