import SwiftUI

/// Chooses which screens sit in the bottom bar, and in what order.
///
/// Six screens is one more than the bar comfortably holds, and which of them
/// earns a permanent slot is genuinely personal: somebody logging every meal
/// wants Fuel under their thumb, and somebody who never opens the calendar
/// should not be paying screen width for it.
struct TabBarEditorView: View {
    @Environment(TabBarSettings.self) private var tabBar

    @State private var feedback = 0

    var body: some View {
        List {
            Section {
                ForEach(tabBar.allTabsInOrder, id: \.self) { tab in
                    row(tab)
                }
                .onMove { offsets, destination in
                    tabBar.move(fromOffsets: offsets, toOffset: destination)
                    feedback += 1
                }
            } header: {
                Text("Bottom bar")
            } footer: {
                Text("Drag to reorder. Switch a screen off to take it out of the bar — nothing in it is lost, and you can still reach it from here. Settings always stays, so there is always a way back.")
            }

            Section {
                Button("Restore Trekka's order") {
                    tabBar.resetToDefaults()
                    feedback += 1
                }
            }
        }
        .navigationTitle("Bottom bar")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
        .sensoryFeedback(.selection, trigger: feedback)
    }

    private func row(_ tab: AppTab) -> some View {
        let isVisible = tabBar.isVisible(tab)
        let isLocked = !tabBar.canHide(tab) && isVisible

        return HStack(spacing: 12) {
            Image(systemName: tab.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isVisible ? Theme.accent : Theme.textPrimary.opacity(0.35))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title)
                    .font(.system(.body, weight: .medium))
                if isLocked {
                    Text(tab == .settings ? "Always in the bar" : "The bar keeps at least one other screen")
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }

            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { isVisible },
                set: { _ in
                    tabBar.toggle(tab)
                    feedback += 1
                }
            ))
            .labelsHidden()
            .tint(Theme.accent)
            .disabled(isLocked)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.title)
        .accessibilityValue(isVisible ? "In the bar" : "Hidden")
    }
}
