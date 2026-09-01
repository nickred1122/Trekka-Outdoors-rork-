import SwiftUI

/// One metric readout: uppercase label, tabular value, quiet unit.
struct MetricCell: View {
    enum Size {
        case hero, large, standard, compact

        var valueSize: CGFloat {
            switch self {
            case .hero: 46
            case .large: 34
            case .standard: 24
            case .compact: 19
            }
        }

        var unitSize: CGFloat {
            switch self {
            case .hero: 14
            case .large: 12
            default: 10
            }
        }

        /// The layout decides how prominent a row is; this turns that into type.
        init(_ emphasis: WatchSlotEmphasis) {
            switch emphasis {
            case .hero: self = .hero
            case .large: self = .large
            case .standard: self = .standard
            case .compact: self = .compact
            }
        }
    }

    let field: WatchDataField
    let value: String
    var size: Size = .standard
    var tint: Color = WatchTheme.textPrimary
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(field.label)
                .fieldLabelStyle()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.metric(size.valueSize, weight: size == .hero ? .bold : .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    // The last line of defence: a long value in a short slot
                    // shrinks rather than clipping or pushing the page taller.
                    .minimumScaleFactor(0.4)
                if !field.unit.isEmpty {
                    Text(field.unit)
                        .font(.watch(size.unitSize, weight: .medium))
                        .foregroundStyle(WatchTheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(field.title) \(value) \(field.unit)")
    }
}

/// Circular progress dial used for readiness and effort.
struct WatchRing: View {
    var progress: Double
    var tint: Color = WatchTheme.accent
    var lineWidth: CGFloat = 8
    var label: String
    var caption: String?

    var body: some View {
        ZStack {
            Circle()
                .stroke(WatchTheme.surfaceRaised, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: progress)
            // Text is held inside the inscribed square of the inner circle, so
            // neither the number nor its caption can ever touch the stroke.
            GeometryReader { proxy in
                let inner = max(0, min(proxy.size.width, proxy.size.height) / 2 - lineWidth)
                VStack(spacing: 0) {
                    Text(label)
                        .font(.metric(26, weight: .bold))
                        .foregroundStyle(WatchTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    if let caption {
                        Text(caption)
                            .font(.watch(9, weight: .semibold))
                            .foregroundStyle(WatchTheme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                .frame(width: inner * 2 / sqrt(2))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Horizontal bar for a single heart-rate zone.
struct ZoneRow: View {
    let zone: Int
    let seconds: TimeInterval
    let fraction: Double
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("Z\(zone)")
                .font(.watch(11, weight: .bold))
                .foregroundStyle(isCurrent ? WatchTheme.textPrimary : WatchTheme.textSecondary)
                .frame(width: WatchDisplay.scaled(20, atLeast: 16), alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(WatchTheme.surfaceRaised)
                    Capsule()
                        .fill(WatchTheme.zoneColor(zone))
                        .frame(width: max(3, proxy.size.width * max(0, min(1, fraction))))
                }
            }
            .frame(height: WatchDisplay.scaled(isCurrent ? 12 : 9, atLeast: 7))

            Text(WatchFormat.compactDuration(seconds))
                .font(.metric(11, weight: .medium))
                .foregroundStyle(WatchTheme.textSecondary)
                .frame(width: WatchDisplay.scaled(38, atLeast: 32), alignment: .trailing)
        }
        .overlay(alignment: .leading) {
            if isCurrent {
                Capsule()
                    .fill(WatchTheme.zoneColor(zone))
                    .frame(width: 2, height: 16)
                    .offset(x: -6)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Zone \(zone), \(WatchFormat.compactDuration(seconds))")
    }
}

/// Miniature route shape drawn from its coordinates.
struct RouteGlyph: View {
    let points: [WatchRoutePoint]
    var tint: Color = WatchTheme.accent

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            let lats = points.map(\.latitude)
            let lons = points.map(\.longitude)
            guard let minLat = lats.min(), let maxLat = lats.max(),
                  let minLon = lons.min(), let maxLon = lons.max() else { return }
            let spanLat = max(0.0001, maxLat - minLat)
            let spanLon = max(0.0001, maxLon - minLon)
            let inset: CGFloat = 3

            var path = Path()
            for (index, point) in points.enumerated() {
                let x = inset + CGFloat((point.longitude - minLon) / spanLon) * (size.width - inset * 2)
                let y = size.height - inset - CGFloat((point.latitude - minLat) / spanLat) * (size.height - inset * 2)
                let location = CGPoint(x: x, y: y)
                if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
            }
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Compact label + value line used across setup and summary screens.
struct WatchStatRow: View {
    let title: String
    let value: String
    var tint: Color = WatchTheme.textPrimary

    var body: some View {
        HStack {
            Text(title)
                .font(.watch(12, weight: .medium))
                .foregroundStyle(WatchTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text(value)
                .font(.metric(14, weight: .semibold))
                .foregroundStyle(tint)
        }
    }
}
