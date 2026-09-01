import SwiftUI

/// Every root screen reachable from the bottom bar. Adding a screen is one case
/// here plus one entry in `ContentView`.
nonisolated enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today
    case routes
    case calendar
    case activities
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .routes: "Routes"
        case .calendar: "Calendar"
        case .activities: "Log"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .today: "gauge.open.with.lines.needle.33percent"
        case .routes: "map.fill"
        case .calendar: "calendar"
        case .activities: "waveform.path.ecg"
        case .settings: "gearshape.fill"
        }
    }
}

nonisolated enum TabBarMetrics {
    /// Height of the bar itself, above the home indicator.
    static let barHeight: CGFloat = 58
    /// Bottom padding scroll content needs so the last row clears the bar.
    static let scrollInset: CGFloat = 104
    /// Height of the dissolve above the bar.
    static let fadeHeight: CGFloat = 22
}

/// The app's fixed bottom bar: one solid slab the content scrolls underneath.
struct SummitTabBar: View {
    @Binding var selection: AppTab
    var onReselect: (AppTab) -> Void

    @Namespace private var indicator
    @State private var feedback = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                item(for: tab)
            }
        }
        .padding(.top, 7)
        .frame(height: TabBarMetrics.barHeight, alignment: .top)
        .background { surface }
        .sensoryFeedback(.selection, trigger: feedback)
    }

    private var surface: some View {
        Theme.surface
            .overlay(alignment: .top) {
                // A sheen lifting the bar off the content behind it. Tinted
                // from the text colour so it lightens the bar at night and
                // shades it in daylight, instead of a fixed white that simply
                // vanishes on a white bar.
                LinearGradient(
                    colors: [Theme.textPrimary.opacity(0.05), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 16)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
            }
            .ignoresSafeArea(edges: .bottom)
    }

    private func item(for tab: AppTab) -> some View {
        let isActive = tab == selection
        return Button {
            if isActive {
                onReselect(tab)
            } else {
                withAnimation(.snappy(duration: 0.3, extraBounce: 0.15)) {
                    selection = tab
                }
            }
            feedback += 1
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Capsule()
                        .fill(.clear)
                        .frame(width: 22, height: 3)
                    if isActive {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: 22, height: 3)
                            .matchedGeometryEffect(id: "summit.tab.indicator", in: indicator)
                    }
                }

                Image(systemName: tab.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)
                    .background {
                        if isActive {
                            Circle()
                                .fill(Theme.accent.opacity(0.22))
                                .frame(width: 30, height: 30)
                                .blur(radius: 9)
                        }
                    }

                Text(tab.title)
                    .font(.system(size: 10, weight: isActive ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isActive ? Theme.accent : Theme.textPrimary.opacity(0.45))
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(TabPressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

/// Subtle squeeze so bar taps feel physical.
private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Dissolves scrolling content into the bar instead of cutting it off.
struct TabBarFade: View {
    var body: some View {
        LinearGradient(
            colors: [Theme.canvas.opacity(0), Theme.canvas.opacity(0.85)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: TabBarMetrics.fadeHeight)
        .allowsHitTesting(false)
    }
}
