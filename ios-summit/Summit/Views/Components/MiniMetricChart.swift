import SwiftUI

/// Tile-sized trend line.
///
/// Drawn in a single `Canvas` rather than a stack of shapes: a dashboard renders
/// up to ten of these at once, and they only need shape, not axes.
///
/// Nothing here depends on an entrance animation having run. `onAppear` never
/// fires in a widget or snapshot render, so a chart that only becomes visible
/// once it has animated is a chart that renders blank there.
struct MiniMetricChart: View {
    let samples: [MetricSample]
    var color: Color = Theme.accent

    var body: some View {
        Canvas { context, size in
            guard size.width > 1, size.height > 1 else { return }
            drawBaseline(in: &context, size: size)
            drawLine(in: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Line

    private func drawLine(in context: inout GraphicsContext, size: CGSize) {
        let points = linePoints(in: size)
        guard points.count > 1 else { return }

        var area = path(through: points)
        area.addLine(to: CGPoint(x: points[points.count - 1].x, y: size.height))
        area.addLine(to: CGPoint(x: points[0].x, y: size.height))
        area.closeSubpath()
        context.fill(
            area,
            with: .linearGradient(
                Gradient(colors: [color.opacity(0.3), color.opacity(0.02)]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        context.stroke(
            path(through: points),
            with: .color(color),
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        )

        if let last = points.last {
            let dot = CGRect(x: last.x - 2.25, y: last.y - 2.25, width: 4.5, height: 4.5)
            context.fill(Path(ellipseIn: dot), with: .color(color))
        }
    }

    /// Only populated buckets are plotted, so an empty day does not drag the
    /// line down to a zero that was never measured.
    private func linePoints(in size: CGSize) -> [CGPoint] {
        let populated = samples.filter { $0.value > 0 }
        guard populated.count > 1,
              let minimum = populated.map(\.value).min(),
              let maximum = populated.map(\.value).max() else { return [] }

        let span = max(0.0001, maximum - minimum)
        let lastIndex = CGFloat(max(1, (samples.last?.index ?? 1)))
        let inset: CGFloat = 2.5

        return populated.map { sample in
            let x = CGFloat(sample.index) / lastIndex * size.width
            let fraction = CGFloat((sample.value - minimum) / span)
            let y = size.height - inset - fraction * max(1, size.height - inset * 2)
            return CGPoint(x: min(max(x, 0), size.width), y: min(max(y, 0), size.height))
        }
    }

    /// Smooth curve that cannot overshoot the samples it joins — the control
    /// point shares the destination's height, so the curve stays inside the
    /// band between each pair of values.
    private func path(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            path.addQuadCurve(
                to: current,
                control: CGPoint(x: (previous.x + current.x) / 2, y: current.y)
            )
        }
        return path
    }

    private func drawBaseline(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)
        context.fill(Path(rect), with: .color(Theme.border))
    }
}
