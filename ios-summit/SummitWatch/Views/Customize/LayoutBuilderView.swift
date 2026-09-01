import SwiftUI

/// Miniature drawing of a layout: one block per readout, rows top to bottom.
struct WatchLayoutDiagram: View {
    let layout: WatchScreenLayout?
    var tint: Color = WatchTheme.accent
    var isSelected: Bool = false

    var body: some View {
        if let layout {
            VStack(spacing: 1.5) {
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, width in
                    HStack(spacing: 1.5) {
                        ForEach(0..<width, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(isSelected ? tint : tint.opacity(0.4))
                        }
                    }
                }
            }
            .padding(2)
            .background(WatchTheme.surfaceRaised, in: .rect(cornerRadius: 4))
            .accessibilityHidden(true)
        } else {
            // Automatic has no fixed shape, so it is drawn as a wildcard.
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? tint : tint.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WatchTheme.surfaceRaised, in: .rect(cornerRadius: 4))
                .accessibilityHidden(true)
        }
    }
}

/// Builds a data screen's shape by hand: how many rows, then how many readouts
/// share each row. Every change applies straight away, so the diagram at the
/// top is always the screen you are about to get.
struct LayoutBuilderView: View {
    let sport: WatchSport
    let initial: WatchScreenLayout?
    /// How many metrics the screen holds today, so turning automatic off starts
    /// from the shape already on the wrist rather than resetting it.
    let fieldCount: Int
    var onChange: (WatchScreenLayout?) -> Void

    @State private var draft: WatchScreenLayout?

    init(
        sport: WatchSport,
        initial: WatchScreenLayout?,
        fieldCount: Int,
        onChange: @escaping (WatchScreenLayout?) -> Void
    ) {
        self.sport = sport
        self.initial = initial
        self.fieldCount = fieldCount
        self.onChange = onChange
        _draft = State(initialValue: initial)
    }

    private var shape: WatchScreenLayout {
        draft ?? .automatic(forSlots: fieldCount, capacity: capacity)
    }

    /// What this watch can actually hold, straight from its own screen size.
    private var capacity: WatchScreenCapacity { WatchDisplay.capacity }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    WatchLayoutDiagram(layout: shape, tint: sport.tint, isSelected: true)
                        .frame(width: 40, height: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(shape.title)
                            .font(.metric(15, weight: .semibold))
                            .foregroundStyle(WatchTheme.textPrimary)
                        Text(shape.summary)
                            .font(.system(size: 9))
                            .foregroundStyle(WatchTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .listRowBackground(Color.clear)
            }

            Section {
                HStack(spacing: 6) {
                    Text("Rows")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WatchTheme.textPrimary)
                    Spacer(minLength: 0)
                    stepButton(systemImage: "minus", isEnabled: shape.canRemoveRow) {
                        apply(shape.settingRowCount(shape.rows.count - 1, capacity: capacity))
                    }
                    Text("\(shape.rows.count)")
                        .font(.metric(16, weight: .semibold))
                        .foregroundStyle(sport.tint)
                        .frame(minWidth: 18)
                        .contentTransition(.numericText())
                    stepButton(systemImage: "plus", isEnabled: shape.canAddRow(capacity: capacity)) {
                        apply(shape.settingRowCount(shape.rows.count + 1, capacity: capacity))
                    }
                }
            } footer: {
                Text("Up to \(capacity.maxRows) rows and \(capacity.maxSlots) readouts on this watch.")
                    .font(.system(size: 9))
            }

            Section {
                ForEach(Array(shape.rows.enumerated()), id: \.offset) { index, width in
                    HStack(spacing: 6) {
                        Text("Row \(index + 1)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WatchTheme.textSecondary)
                        Spacer(minLength: 0)
                        ForEach(1...capacity.maxColumns, id: \.self) { candidate in
                            widthButton(candidate, row: index, current: width)
                        }
                    }
                    .padding(.vertical, 1)
                }
            } header: {
                Text("Fields per row")
            } footer: {
                Text("Fields share their row evenly — one fills the width, two split it in half.")
                    .font(.system(size: 9))
            }

            Section {
                Button {
                    apply(nil)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: draft == nil ? "checkmark.circle.fill" : "wand.and.stars")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(draft == nil ? sport.tint : WatchTheme.textSecondary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Fit automatically")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WatchTheme.textPrimary)
                            Text("Rearranges as you add metrics")
                                .font(.system(size: 9))
                                .foregroundStyle(WatchTheme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .navigationTitle("Layout")
    }

    private func stepButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 26)
                .foregroundStyle(isEnabled ? WatchTheme.textPrimary : WatchTheme.textSecondary.opacity(0.4))
                .background(WatchTheme.surfaceRaised, in: .rect(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(systemImage == "plus" ? "Add a row" : "Remove a row")
    }

    /// One choice of how many readouts a row holds, drawn as that many blocks.
    private func widthButton(_ width: Int, row: Int, current: Int) -> some View {
        let isSelected = width == current
        let isAllowed = shape.canSetWidth(width, forRow: row, capacity: capacity)
        return Button {
            guard let next = shape.settingWidth(width, forRow: row, capacity: capacity) else { return }
            apply(next)
        } label: {
            HStack(spacing: 1.5) {
                ForEach(0..<width, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(isSelected ? sport.tint : WatchTheme.textSecondary.opacity(isAllowed ? 0.5 : 0.2))
                }
            }
            .frame(width: 26, height: 16)
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? sport.tint.opacity(0.18) : WatchTheme.surfaceRaised)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAllowed)
        .accessibilityLabel("Row \(row + 1), \(width) \(width == 1 ? "field" : "fields")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func apply(_ layout: WatchScreenLayout?) {
        withAnimation(.snappy(duration: 0.2)) { draft = layout }
        onChange(layout)
    }
}
