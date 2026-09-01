import SwiftUI

/// Lightweight vector preview of a track — used in lists where a full map
/// would be wasteful. Draws the route over faint terrain hatching.
struct RouteThumbnail: View {
    let points: [RoutePoint]
    var lineColor: Color = Theme.accent
    var showsContours: Bool = true

    var body: some View {
        Canvas { context, size in
            if showsContours {
                drawContours(context: context, size: size)
            }
            guard points.count > 1 else { return }
            let path = routePath(in: size)
            context.stroke(path, with: .color(lineColor.opacity(0.25)), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(lineColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .background(Theme.terrain)
        .accessibilityHidden(true)
    }

    private func drawContours(context: GraphicsContext, size: CGSize) {
        let rings = 5
        for ring in 0..<rings {
            var path = Path()
            let inset = CGFloat(ring) * (size.height / CGFloat(rings * 2))
            let rect = CGRect(x: -size.width * 0.1 + inset, y: -size.height * 0.15 + inset,
                              width: size.width * 1.2 - inset * 2, height: size.height * 1.3 - inset * 2)
            path.addEllipse(in: rect)
            context.stroke(path, with: .color(Theme.contour.opacity(0.55)), lineWidth: 0.8)
        }
    }

    private func routePath(in size: CGSize) -> Path {
        var path = Path()
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return path }

        let latRange = max(0.00001, maxLat - minLat)
        let lonRange = max(0.00001, maxLon - minLon)
        let inset: CGFloat = 10
        let drawWidth = max(1, size.width - inset * 2)
        let drawHeight = max(1, size.height - inset * 2)
        // Preserve aspect so loops don't look stretched.
        let scale = min(drawWidth / lonRange, drawHeight / latRange)
        let offsetX = (size.width - lonRange * scale) / 2
        let offsetY = (size.height - latRange * scale) / 2

        for (index, point) in points.enumerated() {
            let x = offsetX + (point.longitude - minLon) * scale
            let y = size.height - (offsetY + (point.latitude - minLat) * scale)
            let cgPoint = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: cgPoint)
            } else {
                path.addLine(to: cgPoint)
            }
        }
        return path
    }
}
