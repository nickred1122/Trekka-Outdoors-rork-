import SwiftUI

/// Renders a watch page exactly as it will be laid out on the wrist, inside a
/// watch-shaped frame, using representative mid-workout values.
struct WatchPagePreview: View {
    let page: WatchPage
    let sport: WatchSportProfile
    var showsChrome: Bool = true
    /// Set to make each readout tappable, so the athlete edits the page by
    /// touching the block they want rather than hunting a list row.
    var selectedSlot: Int?
    var onSelectSlot: ((Int) -> Void)?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(Color.black)
                .overlay {
                    RoundedRectangle(cornerRadius: 42, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }

            VStack(spacing: 5) {
                if showsChrome { statusBar }
                content
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(width: 168, height: 204)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview of \(page.title)")
    }

    private var statusBar: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(sport.tint)
                .frame(width: 4, height: 4)
            Text("48:12")
                .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
            Spacer(minLength: 0)
            HStack(spacing: 1.5) {
                ForEach(1...3, id: \.self) { index in
                    Capsule()
                        .fill(Color(red: 0.32, green: 0.85, blue: 0.55))
                        .frame(width: 2, height: 2 + CGFloat(index) * 1.6)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page.kind {
        case .data: dataLayout
        case .map: mapPreview
        case .elevation: elevationPreview
        case .climb: climbPreview
        case .upAhead: upAheadPreview
        case .zones: zonesPreview
        case .laps: lapsPreview
        case .compass: compassPreview
        }
    }

    // MARK: - Data layout

    private var dataLayout: some View {
        let layout = page.resolvedLayout
        let bands = layout.slice(Array(page.fields.enumerated()))
        return VStack(alignment: .leading, spacing: layout.rows.count >= 3 ? 3 : 6) {
            if page.fields.isEmpty {
                emptyState
            } else {
                ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                    if index > 0 {
                        separator
                    }
                    row(band, size: fontSize(for: layout.emphasis(forRow: index)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Emphasis translated into the smaller type this wrist-sized preview needs.
    private func fontSize(for emphasis: WatchPageEmphasis) -> CGFloat {
        switch emphasis {
        case .hero: 32
        case .large: 24
        case .standard: 17
        case .compact: 14
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 0.5)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
            Text("No metrics")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private func row(_ band: [(offset: Int, element: WatchMetric)], size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(band, id: \.offset) { slot, metric in
                if let onSelectSlot {
                    Button {
                        onSelectSlot(slot)
                    } label: {
                        cell(metric, size: size)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(selectedSlot == slot ? sport.tint.opacity(0.18) : .clear)
                                    .strokeBorder(
                                        selectedSlot == slot ? sport.tint : .clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(metric.title), block \(slot + 1)")
                    .accessibilityHint("Changes the metric in this block")
                } else {
                    cell(metric, size: size)
                }
            }
        }
    }

    private func cell(_ metric: WatchMetric, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: -1) {
            Text(metric.label)
                .font(.system(size: 7, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 1.5) {
                Text(metric.preview)
                    .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint(for: metric))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(.system(size: max(7, size * 0.32)))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tint(for metric: WatchMetric) -> Color {
        switch metric {
        case .heartRate, .heartRateZone, .percentMaxHeartRate: Theme.zoneColor(3)
        case .ascent, .grade, .altitude, .verticalSpeed, .descent: Theme.highlight
        case .remainingDistance, .eta, .distanceToWaypoint, .nextWaypoint, .offCourse: Theme.accent
        default: Theme.textPrimary
        }
    }

    // MARK: - Special pages

    private var mapPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.terrain)
            Canvas { context, size in
                var contour = Path()
                for step in 0..<4 {
                    let y = size.height * (0.25 + Double(step) * 0.17)
                    contour.move(to: CGPoint(x: 0, y: y))
                    contour.addQuadCurve(
                        to: CGPoint(x: size.width, y: y - 8),
                        control: CGPoint(x: size.width / 2, y: y + 12)
                    )
                }
                context.stroke(contour, with: .color(Theme.contour), lineWidth: 0.6)

                var route = Path()
                route.move(to: CGPoint(x: size.width * 0.16, y: size.height * 0.8))
                route.addCurve(
                    to: CGPoint(x: size.width * 0.84, y: size.height * 0.2),
                    control1: CGPoint(x: size.width * 0.1, y: size.height * 0.35),
                    control2: CGPoint(x: size.width * 0.86, y: size.height * 0.62)
                )
                context.stroke(route, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
            .padding(4)

            Circle()
                .fill(Color(red: 0.32, green: 0.85, blue: 0.55))
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(Color.black, lineWidth: 1.4))
                .offset(x: -14, y: 12)
        }
        .frame(height: 128)
        .overlay(alignment: .top) {
            HStack(spacing: 3) {
                Image(systemName: "flag.fill").font(.system(size: 6))
                Text("Saddle").font(.system(size: 8, weight: .semibold))
                Text("480").font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.highlight)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.8), in: .capsule)
            .padding(.top, 4)
        }
    }

    private var elevationPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                miniStat("ASCENT", "612", Theme.highlight)
                miniStat("ELEV", "1284", Theme.textPrimary)
                miniStat("GRADE", "+6.4", Theme.danger)
            }
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                let samples = 22
                for step in 0...samples {
                    let x = size.width * Double(step) / Double(samples)
                    let wave = sin(Double(step) / Double(samples) * .pi * 2)
                    let y = size.height * (0.72 - 0.5 * (0.5 + wave / 2))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [Theme.accent.opacity(0.6), Theme.accent.opacity(0.05)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
                context.stroke(path, with: .color(Theme.accent), lineWidth: 1.4)

                var marker = Path()
                marker.move(to: CGPoint(x: size.width * 0.62, y: 0))
                marker.addLine(to: CGPoint(x: size.width * 0.62, y: size.height))
                context.stroke(marker, with: .color(Theme.highlight), lineWidth: 1.2)
            }
            .frame(height: 78)
        }
    }

    private var climbPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("CLIMB 2 OF 4")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                Spacer(minLength: 0)
                Text("CAT 2")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.highlight, in: .capsule)
            }

            Canvas { context, size in
                var wedge = Path()
                wedge.move(to: CGPoint(x: 0, y: size.height))
                wedge.addLine(to: CGPoint(x: size.width, y: size.height * 0.12))
                wedge.addLine(to: CGPoint(x: size.width, y: size.height))
                wedge.closeSubpath()
                context.fill(wedge, with: .color(Theme.highlight.opacity(0.28)))

                var done = Path()
                done.move(to: CGPoint(x: 0, y: size.height))
                done.addLine(to: CGPoint(x: size.width * 0.55, y: size.height * 0.52))
                done.addLine(to: CGPoint(x: size.width * 0.55, y: size.height))
                done.closeSubpath()
                context.fill(done, with: .color(Theme.highlight))
            }
            .frame(height: 52)

            HStack(spacing: 6) {
                miniStat("TO TOP", "1.20", Theme.textPrimary)
                miniStat("LEFT", "148", Theme.highlight)
                miniStat("GRADE", "+8.2", Theme.danger)
            }
        }
    }

    private var upAheadPreview: some View {
        VStack(spacing: 3) {
            ForEach(
                [("flag.fill", "Saddle", "0.48", "07:58"),
                 ("mountain.2.fill", "Summit", "2.10", "08:26"),
                 ("flag.checkered", "Finish", "6.40", "09:44")],
                id: \.1
            ) { item in
                HStack(spacing: 5) {
                    Image(systemName: item.0)
                        .font(.system(size: 7))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 9)
                    Text(item.1)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(item.2)
                        .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Text(item.3)
                        .font(.system(size: 8, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(Theme.surface, in: .rect(cornerRadius: 6))
            }
        }
    }

    private var zonesPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("154")
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.zoneColor(3))
                VStack(alignment: .leading, spacing: -2) {
                    Text("BPM")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    Text("Zone 3")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.zoneColor(3))
                }
                Spacer(minLength: 0)
            }
            ForEach(1...5, id: \.self) { zone in
                HStack(spacing: 4) {
                    Text("Z\(zone)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.textPrimary.opacity(zone == 3 ? 0.9 : 0.45))
                        .frame(width: 12, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surfaceRaised)
                            Capsule()
                                .fill(Theme.zoneColor(zone))
                                .frame(width: proxy.size.width * [0.14, 0.4, 0.72, 0.46, 0.18][zone - 1])
                        }
                    }
                    .frame(height: zone == 3 ? 8 : 6)
                }
            }
        }
    }

    private var lapsPreview: some View {
        VStack(spacing: 3) {
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("LAP 8")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    Text("IN PROGRESS")
                        .font(.system(size: 6, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("6:04")
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("0.62 \(Formatters.units.distanceUnit)")
                        .font(.system(size: 10, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                }
            }
            .padding(6)
            .background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: 7))

            ForEach([("7", "5:58", "5:12"), ("6", "6:12", "5:26")], id: \.0) { lap in
                HStack(spacing: 5) {
                    Text(lap.0)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    Text(lap.1)
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(lap.2)
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.highlight)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Theme.surface, in: .rect(cornerRadius: 6))
            }
        }
    }

    private var compassPreview: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Theme.surfaceRaised, lineWidth: 4)
                Text("N")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .offset(y: -26)
                Image(systemName: "location.north.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 64, height: 64)
            Text("312°")
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }

    private func miniStat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: -1) {
            Text(label)
                .font(.system(size: 6, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
