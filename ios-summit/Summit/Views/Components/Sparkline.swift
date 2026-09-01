import SwiftUI

/// Compact trend line drawn under each metric tile.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.accent
    var lineWidth: CGFloat = 1.8
    var animated: Bool = true

    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let path = linePath(in: geometry.size)
            path
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .onAppear {
            guard animated, !reduceMotion else {
                progress = 1
                return
            }
            withAnimation(.easeOut(duration: 0.9)) { progress = 1 }
        }
        .accessibilityHidden(true)
    }

    private func linePath(in size: CGSize) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 1
        let range = max(0.0001, maximum - minimum)
        let stepX = size.width / CGFloat(values.count - 1)

        for (index, value) in values.enumerated() {
            let x = CGFloat(index) * stepX
            let normalized = (value - minimum) / range
            let y = size.height - CGFloat(normalized) * size.height
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                let previousX = CGFloat(index - 1) * stepX
                let control = CGPoint(x: (previousX + x) / 2, y: y)
                path.addQuadCurve(to: CGPoint(x: x, y: y), control: control)
            }
        }
        return path
    }
}
