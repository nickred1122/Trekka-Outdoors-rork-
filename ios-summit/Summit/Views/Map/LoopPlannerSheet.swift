import CoreLocation
import SwiftUI

/// Asks for a distance and a direction, then routes a loop that comes home.
///
/// The one thing drawing cannot give you: you know you want ten kilometres from
/// the front door and you do not much mind where it goes. Everything else in the
/// planner starts from a line you have already imagined.
struct LoopPlannerSheet: View {
    let draft: RouteDraftModel
    let start: CLLocationCoordinate2D
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.unitSystem) private var units

    /// Held in the athlete's own unit, converted to metres on the way out.
    @State private var targetDistance: Double = 10
    @State private var bearing: Double = 0

    private static let compassPoints: [(label: String, degrees: Double)] = [
        ("N", 0), ("NE", 45), ("E", 90), ("SE", 135),
        ("S", 180), ("SW", 225), ("W", 270), ("NW", 315),
    ]

    private var targetMetres: Double { units.metres(fromDistance: targetDistance) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    distanceCard
                    directionCard

                    if draft.isGeneratingLoop {
                        progressCard
                    } else {
                        generateButton
                    }

                    Text("Trekka will route a circuit along real paths and correct it until it lands close to your distance. Anything it cannot route stays a straight line and is marked as one.")
                        .font(.system(.footnote))
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
            .background(Theme.canvas)
            .scrollIndicators(.hidden)
            .navigationTitle("Loop from here")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(draft.isGeneratingLoop)
                }
            }
        }
    }

    private var distanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Distance")
                .metricLabelStyle()

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", targetDistance))
                    .font(.metric(38))
                    .foregroundStyle(Theme.accent)
                Text(units.distanceUnit)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }

            Slider(value: $targetDistance, in: sliderRange, step: 0.5)
                .tint(Theme.accent)

            HStack {
                ForEach(quickDistances, id: \.self) { value in
                    Button {
                        targetDistance = value
                    } label: {
                        Text(String(format: value < 10 ? "%.0f" : "%.0f", value))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(
                                abs(targetDistance - value) < 0.01 ? Theme.surface : Theme.textPrimary
                            )
                            .background(
                                abs(targetDistance - value) < 0.01 ? Theme.accent : Theme.surfaceRaised,
                                in: .rect(cornerRadius: 9)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var sliderRange: ClosedRange<Double> {
        units == .metric ? 1...42 : 0.5...26
    }

    private var quickDistances: [Double] {
        units == .metric ? [5, 10, 15, 21] : [3, 6, 10, 13]
    }

    private var directionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Head out towards")
                .metricLabelStyle()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Self.compassPoints, id: \.label) { point in
                    Button {
                        bearing = point.degrees
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 12, weight: .bold))
                                .rotationEffect(.degrees(point.degrees))
                            Text(point.label)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(bearing == point.degrees ? Theme.surface : Theme.textPrimary)
                        .background(
                            bearing == point.degrees ? Theme.accent : Theme.surfaceRaised,
                            in: .rect(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var progressCard: some View {
        VStack(spacing: 10) {
            ProgressView(value: draft.loopProgress ?? 0)
                .tint(Theme.accent)
            Text("Routing your loop and correcting the length…")
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.65))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .panel()
    }

    private var generateButton: some View {
        Button {
            Task {
                await draft.generateLoop(
                    from: start,
                    targetMetres: targetMetres,
                    bearingDegrees: bearing
                )
                onFinished()
                dismiss()
            }
        } label: {
            Text("Build the loop")
                .font(.system(.headline, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(Theme.surface)
                .background(Theme.accent, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
