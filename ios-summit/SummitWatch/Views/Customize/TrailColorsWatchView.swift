import SwiftUI

/// Picks the colours of the two lines that share the workout map.
///
/// The course you meant to follow and the trail you actually laid are drawn on
/// top of each other, so being able to tell them apart at arm's length — in
/// sun, in rain, at a junction — is worth choosing deliberately.
struct TrailColorsWatchView: View {
    @Environment(WatchScreenSettings.self) private var settings

    var body: some View {
        List {
            Section {
                preview
                    .listRowBackground(Color.clear)
            }

            Section("Course line") {
                ForEach(TrailColor.allCases) { option in
                    row(option, isSelected: settings.routeTrailColor == option) {
                        settings.routeTrailColor = option
                    }
                }
            }

            Section {
                ForEach(TrailColor.allCases) { option in
                    row(option, isSelected: settings.breadcrumbTrailColor == option) {
                        settings.breadcrumbTrailColor = option
                    }
                }
            } header: {
                Text("Your trail")
            } footer: {
                Text("Your trail is drawn dashed, the course solid, so they stay distinct even in the same colour.")
                    .font(.system(size: 9))
            }
        }
        .navigationTitle("Line colours")
    }

    /// Shows the real thing: a solid course with a dashed trail crossing it.
    private var preview: some View {
        ZStack {
            Canvas { context, size in
                var course = Path()
                course.move(to: CGPoint(x: 6, y: size.height * 0.72))
                course.addCurve(
                    to: CGPoint(x: size.width - 6, y: size.height * 0.28),
                    control1: CGPoint(x: size.width * 0.35, y: size.height * 0.9),
                    control2: CGPoint(x: size.width * 0.6, y: size.height * 0.1)
                )
                context.stroke(
                    course,
                    with: .color(WatchTheme.canvas.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                context.stroke(
                    course,
                    with: .color(settings.routeTrailColor.color),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )

                var trail = Path()
                trail.move(to: CGPoint(x: 6, y: size.height * 0.5))
                trail.addCurve(
                    to: CGPoint(x: size.width - 6, y: size.height * 0.52),
                    control1: CGPoint(x: size.width * 0.4, y: size.height * 0.15),
                    control2: CGPoint(x: size.width * 0.55, y: size.height * 0.95)
                )
                context.stroke(
                    trail,
                    with: .color(settings.breadcrumbTrailColor.color),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 3])
                )
            }
        }
        .frame(height: WatchDisplay.scaled(58, atLeast: 48))
        .background(WatchTheme.surface, in: .rect(cornerRadius: 8))
        .accessibilityLabel("Preview: course in \(settings.routeTrailColor.title), your trail in \(settings.breadcrumbTrailColor.title)")
    }

    private func row(_ option: TrailColor, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(option.color)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(WatchTheme.border, lineWidth: 0.5))
                Text(option.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(WatchTheme.textPrimary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(option.color)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
