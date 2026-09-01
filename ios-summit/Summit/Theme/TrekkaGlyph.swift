import SwiftUI

/// Trekka's own icon set.
///
/// Every mark here is drawn from scratch as vector geometry in a normalised
/// 0–1 box, rather than pulled from a system symbol font. Two reasons:
///
/// - The activity marks are the app's signature. Borrowing the platform's
///   figure set made Trekka read as a copy of the stock fitness apps.
/// - Nothing in the app's identity then depends on artwork Trekka does not own.
///
/// Glyphs are deliberately geometric — strokes with round caps, simple filled
/// bodies — so they stay legible down to 10 pt on a watch face.
nonisolated enum TrekkaGlyph: String, CaseIterable, Sendable, Identifiable {
    // Activity families
    case run, ride, hike, climb, snow, water, gym, ball, more
    // Health and performance metrics
    case sleep, hrv, vo2, load, calories, steps, heart, distance, elevation, pace
    // Navigation, wayfinding and actions
    case route, breadcrumb, backtrack, navigate, compass, flag, trash

    var id: String { rawValue }

    /// Stroke weight as a fraction of the icon's size, so a glyph keeps its
    /// visual weight whether it is drawn at 10 pt or 40 pt.
    var strokeRatio: CGFloat {
        switch self {
        case .snow, .hrv, .water: 0.085
        default: 0.10
        }
    }

    // MARK: - Geometry

    /// The stroked portion of the glyph.
    func strokes(in rect: CGRect) -> Path {
        let pen = GlyphPen(rect: rect)
        var path = Path()

        switch self {
        case .run:
            // Three forward chevrons: motion, without borrowing a figure.
            for x in [0.20, 0.42, 0.64] as [CGFloat] {
                path.move(to: pen.at(x, 0.24))
                path.addLine(to: pen.at(x + 0.17, 0.50))
                path.addLine(to: pen.at(x, 0.76))
            }

        case .ride:
            path.addEllipse(in: pen.box(centre: (0.23, 0.68), radius: 0.18))
            path.addEllipse(in: pen.box(centre: (0.77, 0.68), radius: 0.18))
            path.move(to: pen.at(0.23, 0.68))
            path.addLine(to: pen.at(0.46, 0.38))
            path.addLine(to: pen.at(0.62, 0.68))
            path.move(to: pen.at(0.46, 0.38))
            path.addLine(to: pen.at(0.71, 0.38))
            path.addLine(to: pen.at(0.77, 0.68))
            path.move(to: pen.at(0.64, 0.30))
            path.addLine(to: pen.at(0.80, 0.30))

        case .hike:
            // Lace rungs across the boot shaft.
            for y in [0.24, 0.34] as [CGFloat] {
                path.move(to: pen.at(0.30, y))
                path.addLine(to: pen.at(0.44, y))
            }

        case .climb:
            // Carabiner: an open oval with the gate drawn across the gap.
            path.addArc(
                center: pen.at(0.48, 0.50),
                radius: pen.length(0.32),
                startAngle: .degrees(38),
                endAngle: .degrees(322),
                clockwise: false
            )
            path.move(to: pen.at(0.48 + 0.32 * 0.788, 0.50 + 0.32 * 0.616))
            path.addLine(to: pen.at(0.48 + 0.32 * 0.788, 0.50 - 0.32 * 0.616))

        case .snow:
            // Three crossing spokes with a tick at each tip.
            let arms: [CGFloat] = [0, 60, 120]
            for degrees in arms {
                let radians: CGFloat = degrees * .pi / 180
                let dx: CGFloat = cos(radians) * 0.38
                let dy: CGFloat = sin(radians) * 0.38
                path.move(to: pen.at(0.5 - dx, 0.5 - dy))
                path.addLine(to: pen.at(0.5 + dx, 0.5 + dy))

                for direction in [1.0, -1.0] as [CGFloat] {
                    let tipX: CGFloat = 0.5 + dx * direction
                    let tipY: CGFloat = 0.5 + dy * direction
                    for spread in [35.0, -35.0] as [CGFloat] {
                        let sweep: CGFloat = degrees + 180 + spread * direction
                        let branch: CGFloat = sweep * .pi / 180
                        let branchX: CGFloat = tipX + cos(branch) * 0.13 * direction
                        let branchY: CGFloat = tipY + sin(branch) * 0.13 * direction
                        path.move(to: pen.at(tipX, tipY))
                        path.addLine(to: pen.at(branchX, branchY))
                    }
                }
            }

        case .water:
            for y in [0.34, 0.52, 0.70] as [CGFloat] {
                path.move(to: pen.at(0.08, y))
                path.addQuadCurve(to: pen.at(0.36, y), control: pen.at(0.22, y - 0.13))
                path.addQuadCurve(to: pen.at(0.64, y), control: pen.at(0.50, y + 0.13))
                path.addQuadCurve(to: pen.at(0.92, y), control: pen.at(0.78, y - 0.13))
            }

        case .gym:
            path.move(to: pen.at(0.28, 0.50))
            path.addLine(to: pen.at(0.72, 0.50))
            path.move(to: pen.at(0.24, 0.28))
            path.addLine(to: pen.at(0.24, 0.72))
            path.move(to: pen.at(0.76, 0.28))
            path.addLine(to: pen.at(0.76, 0.72))
            path.move(to: pen.at(0.11, 0.37))
            path.addLine(to: pen.at(0.11, 0.63))
            path.move(to: pen.at(0.89, 0.37))
            path.addLine(to: pen.at(0.89, 0.63))

        case .ball:
            path.addEllipse(in: pen.box(centre: (0.5, 0.5), radius: 0.36))
            path.move(to: pen.at(0.22, 0.24))
            path.addQuadCurve(to: pen.at(0.22, 0.76), control: pen.at(0.60, 0.50))
            path.move(to: pen.at(0.78, 0.24))
            path.addQuadCurve(to: pen.at(0.78, 0.76), control: pen.at(0.40, 0.50))

        case .hrv:
            path.move(to: pen.at(0.06, 0.50))
            path.addLine(to: pen.at(0.26, 0.50))
            path.addLine(to: pen.at(0.34, 0.24))
            path.addLine(to: pen.at(0.45, 0.76))
            path.addLine(to: pen.at(0.55, 0.38))
            path.addLine(to: pen.at(0.63, 0.50))
            path.addLine(to: pen.at(0.94, 0.50))

        case .vo2:
            // Two stacked chevrons: capacity climbing.
            for y in [0.58, 0.82] as [CGFloat] {
                path.move(to: pen.at(0.18, y))
                path.addLine(to: pen.at(0.50, y - 0.30))
                path.addLine(to: pen.at(0.82, y))
            }

        case .distance, .route:
            path.move(to: pen.at(0.12, 0.80))
            path.addCurve(
                to: pen.at(0.88, 0.22),
                control1: pen.at(0.38, 0.28),
                control2: pen.at(0.62, 0.76)
            )

        case .pace:
            path.addEllipse(in: pen.box(centre: (0.5, 0.58), radius: 0.32))
            path.move(to: pen.at(0.50, 0.26))
            path.addLine(to: pen.at(0.50, 0.16))
            path.move(to: pen.at(0.38, 0.14))
            path.addLine(to: pen.at(0.62, 0.14))
            path.move(to: pen.at(0.50, 0.58))
            path.addLine(to: pen.at(0.66, 0.42))

        case .backtrack:
            path.move(to: pen.at(0.24, 0.86))
            path.addLine(to: pen.at(0.24, 0.46))
            path.addQuadCurve(to: pen.at(0.74, 0.46), control: pen.at(0.49, 0.12))
            path.addLine(to: pen.at(0.74, 0.62))
            path.move(to: pen.at(0.60, 0.50))
            path.addLine(to: pen.at(0.74, 0.66))
            path.addLine(to: pen.at(0.88, 0.50))

        case .compass:
            path.addEllipse(in: pen.box(centre: (0.5, 0.5), radius: 0.38))

        case .flag:
            path.move(to: pen.at(0.28, 0.12))
            path.addLine(to: pen.at(0.28, 0.88))

        case .trash:
            path.move(to: pen.at(0.14, 0.28))
            path.addLine(to: pen.at(0.86, 0.28))
            path.move(to: pen.at(0.38, 0.28))
            path.addLine(to: pen.at(0.38, 0.16))
            path.addLine(to: pen.at(0.62, 0.16))
            path.addLine(to: pen.at(0.62, 0.28))
            path.move(to: pen.at(0.24, 0.32))
            path.addLine(to: pen.at(0.30, 0.86))
            path.addLine(to: pen.at(0.70, 0.86))
            path.addLine(to: pen.at(0.76, 0.32))

        case .sleep, .load, .calories, .steps, .heart, .elevation, .more, .breadcrumb, .navigate:
            break
        }
        return path
    }

    /// The filled portion of the glyph.
    func fills(in rect: CGRect) -> Path {
        let pen = GlyphPen(rect: rect)
        var path = Path()

        switch self {
        case .hike:
            // Boot: shaft, instep, toe, then the sole as its own slab.
            path.move(to: pen.at(0.28, 0.16))
            path.addLine(to: pen.at(0.46, 0.16))
            path.addLine(to: pen.at(0.46, 0.44))
            path.addLine(to: pen.at(0.74, 0.56))
            path.addLine(to: pen.at(0.78, 0.70))
            path.addLine(to: pen.at(0.28, 0.70))
            path.closeSubpath()
            path.addRoundedRect(
                in: pen.rect(0.20, 0.70, 0.66, 0.13),
                cornerSize: pen.corner(0.055)
            )

        case .sleep:
            path.move(to: pen.at(0.70, 0.14))
            path.addQuadCurve(to: pen.at(0.70, 0.86), control: pen.at(0.14, 0.50))
            path.addQuadCurve(to: pen.at(0.70, 0.14), control: pen.at(0.46, 0.50))
            path.closeSubpath()

        case .load:
            path.addRoundedRect(in: pen.rect(0.14, 0.58, 0.18, 0.30), cornerSize: pen.corner(0.05))
            path.addRoundedRect(in: pen.rect(0.41, 0.40, 0.18, 0.48), cornerSize: pen.corner(0.05))
            path.addRoundedRect(in: pen.rect(0.68, 0.22, 0.18, 0.66), cornerSize: pen.corner(0.05))

        case .calories:
            path.move(to: pen.at(0.50, 0.08))
            path.addCurve(
                to: pen.at(0.80, 0.56),
                control1: pen.at(0.64, 0.26),
                control2: pen.at(0.80, 0.34)
            )
            path.addCurve(
                to: pen.at(0.20, 0.56),
                control1: pen.at(0.80, 0.86),
                control2: pen.at(0.20, 0.86)
            )
            path.addCurve(
                to: pen.at(0.50, 0.08),
                control1: pen.at(0.20, 0.34),
                control2: pen.at(0.42, 0.34)
            )
            path.closeSubpath()

        case .steps:
            path.addEllipse(in: pen.rect(0.12, 0.28, 0.28, 0.40))
            path.addEllipse(in: pen.rect(0.10, 0.17, 0.11, 0.11))
            path.addEllipse(in: pen.rect(0.58, 0.44, 0.28, 0.40))
            path.addEllipse(in: pen.rect(0.79, 0.33, 0.11, 0.11))

        case .heart:
            path.move(to: pen.at(0.50, 0.84))
            path.addCurve(
                to: pen.at(0.08, 0.42),
                control1: pen.at(0.26, 0.70),
                control2: pen.at(0.08, 0.58)
            )
            path.addCurve(
                to: pen.at(0.50, 0.32),
                control1: pen.at(0.08, 0.18),
                control2: pen.at(0.36, 0.16)
            )
            path.addCurve(
                to: pen.at(0.92, 0.42),
                control1: pen.at(0.64, 0.16),
                control2: pen.at(0.92, 0.18)
            )
            path.addCurve(
                to: pen.at(0.50, 0.84),
                control1: pen.at(0.92, 0.58),
                control2: pen.at(0.74, 0.70)
            )
            path.closeSubpath()

        case .elevation:
            path.move(to: pen.at(0.04, 0.80))
            path.addLine(to: pen.at(0.38, 0.24))
            path.addLine(to: pen.at(0.72, 0.80))
            path.closeSubpath()
            path.move(to: pen.at(0.52, 0.80))
            path.addLine(to: pen.at(0.74, 0.44))
            path.addLine(to: pen.at(0.96, 0.80))
            path.closeSubpath()

        case .more:
            for x in [0.20, 0.50, 0.80] as [CGFloat] {
                path.addEllipse(in: pen.box(centre: (x, 0.50), radius: 0.10))
            }

        case .route:
            path.addEllipse(in: pen.box(centre: (0.12, 0.80), radius: 0.11))
            path.addEllipse(in: pen.box(centre: (0.88, 0.22), radius: 0.11))

        case .breadcrumb:
            let dots: [(CGFloat, CGFloat)] = [
                (0.12, 0.84), (0.30, 0.64), (0.50, 0.50), (0.70, 0.36), (0.88, 0.16),
            ]
            for dot in dots {
                path.addEllipse(in: pen.box(centre: dot, radius: 0.085))
            }

        case .navigate:
            path.move(to: pen.at(0.50, 0.10))
            path.addLine(to: pen.at(0.84, 0.88))
            path.addLine(to: pen.at(0.50, 0.68))
            path.addLine(to: pen.at(0.16, 0.88))
            path.closeSubpath()

        case .compass:
            path.move(to: pen.at(0.50, 0.24))
            path.addLine(to: pen.at(0.66, 0.68))
            path.addLine(to: pen.at(0.50, 0.56))
            path.addLine(to: pen.at(0.34, 0.68))
            path.closeSubpath()

        case .flag:
            path.move(to: pen.at(0.32, 0.18))
            path.addLine(to: pen.at(0.82, 0.34))
            path.addLine(to: pen.at(0.32, 0.50))
            path.closeSubpath()

        case .run, .ride, .climb, .snow, .water, .gym, .ball,
             .hrv, .vo2, .distance, .pace, .backtrack, .trash:
            break
        }
        return path
    }
}

/// Maps the normalised 0–1 glyph space onto the box a glyph is drawn in.
///
/// `nonisolated` because glyph geometry is pure maths built inside `Shape`
/// bodies, which SwiftUI is free to evaluate off the main actor.
private nonisolated struct GlyphPen {
    let rect: CGRect

    func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    func length(_ value: CGFloat) -> CGFloat { value * min(rect.width, rect.height) }

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX + x * rect.width,
            y: rect.minY + y * rect.height,
            width: width * rect.width,
            height: height * rect.height
        )
    }

    func box(centre: (CGFloat, CGFloat), radius: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX + (centre.0 - radius) * rect.width,
            y: rect.minY + (centre.1 - radius) * rect.height,
            width: radius * 2 * rect.width,
            height: radius * 2 * rect.height
        )
    }

    func corner(_ value: CGFloat) -> CGSize {
        CGSize(width: value * rect.width, height: value * rect.height)
    }
}

private nonisolated struct TrekkaStrokeShape: Shape {
    let glyph: TrekkaGlyph
    func path(in rect: CGRect) -> Path { glyph.strokes(in: rect) }
}

private nonisolated struct TrekkaFillShape: Shape {
    let glyph: TrekkaGlyph
    func path(in rect: CGRect) -> Path { glyph.fills(in: rect) }
}

/// Draws a Trekka glyph at an explicit point size.
///
/// With no tint the glyph fills with `.foreground`, so it inherits
/// `foregroundStyle` from its surroundings exactly like a text-based symbol
/// would — every existing tint modifier keeps working.
struct TrekkaIcon: View {
    let glyph: TrekkaGlyph
    var size: CGFloat
    private let style: AnyShapeStyle

    init(_ glyph: TrekkaGlyph, size: CGFloat = 17, tint: Color? = nil) {
        self.glyph = glyph
        self.size = size
        self.style = tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.foreground)
    }

    var body: some View {
        ZStack {
            TrekkaFillShape(glyph: glyph).fill(style)
            TrekkaStrokeShape(glyph: glyph)
                .stroke(
                    style,
                    style: StrokeStyle(
                        lineWidth: max(1, size * glyph.strokeRatio),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
        .frame(width: size, height: size)
    }
}

/// A glyph and a title on one line — the Trekka equivalent of `Label`.
struct TrekkaLabel: View {
    let title: String
    let glyph: TrekkaGlyph
    var size: CGFloat = 15
    var spacing: CGFloat = 6
    var tint: Color?

    init(_ title: String, glyph: TrekkaGlyph, size: CGFloat = 15, spacing: CGFloat = 6, tint: Color? = nil) {
        self.title = title
        self.glyph = glyph
        self.size = size
        self.spacing = spacing
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: spacing) {
            TrekkaIcon(glyph, size: size, tint: tint)
            Text(title)
        }
    }
}
