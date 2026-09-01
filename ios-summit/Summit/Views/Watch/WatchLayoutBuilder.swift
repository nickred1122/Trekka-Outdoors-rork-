import SwiftUI

/// Miniature drawing of a page layout: one block per readout, rows top to
/// bottom, so a shape can be read at a glance rather than described in words.
struct WatchLayoutGlyph: View {
    let layout: WatchPageLayout?
    var tint: Color = Theme.accent
    var isSelected: Bool = false

    var body: some View {
        Group {
            if let layout {
                VStack(spacing: 2.5) {
                    ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, width in
                        HStack(spacing: 2.5) {
                            ForEach(0..<width, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(isSelected ? tint : Theme.textPrimary.opacity(0.28))
                            }
                        }
                    }
                }
                .padding(4)
            } else {
                // Automatic has no fixed shape, so it is drawn as a wildcard.
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : Theme.textPrimary.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.opacity(0.45), in: .rect(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Builds a data page's shape by hand: how many rows, then how many readouts
/// share each row. Rows split their width evenly, so one field fills the row
/// and two take half each.
struct WatchLayoutBuilder: View {
    /// The chosen shape, or nil while the page is arranging itself.
    let layout: WatchPageLayout?
    /// Metrics on the page today, so leaving automatic keeps the current shape.
    let fieldCount: Int
    let tint: Color
    /// What the paired watch can hold, from the screen size it reported. The
    /// ceiling until the watch syncs once — limits only tighten from there.
    var capacity: WatchPageCapacity = .ceiling
    var onChange: (WatchPageLayout?) -> Void

    private var shape: WatchPageLayout {
        layout ?? .automatic(forSlots: fieldCount, capacity: capacity)
    }

    /// True when the page as it stands holds more than this watch can render
    /// comfortably — shown honestly rather than silently rearranged.
    private var isOverCapacity: Bool {
        shape.slotCount > capacity.maxSlots || shape.rows.contains { $0 > capacity.maxColumns }
    }

    var body: some View {
        VStack(spacing: 14) {
            automaticToggle

            if layout != nil {
                Divider().overlay(Theme.border)
                rowCountControl

                VStack(spacing: 8) {
                    ForEach(Array(shape.rows.enumerated()), id: \.offset) { index, width in
                        rowControl(index: index, width: width)
                    }
                }
            }
        }
    }

    private var automaticToggle: some View {
        Toggle(isOn: Binding(
            get: { layout == nil },
            set: { isAutomatic in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                    onChange(isAutomatic ? nil : .automatic(forSlots: min(max(fieldCount, 1), capacity.maxSlots), capacity: capacity))
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fit automatically")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("The page arranges itself as you add metrics")
                    .font(.caption2)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
            }
        }
        .tint(tint)
    }

    private var rowCountControl: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rows")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(isOverCapacity
                     ? "Your watch fits \(capacity.maxSlots) — trim a row or narrow one"
                     : "\(shape.slotCount) \(shape.slotCount == 1 ? "readout" : "readouts") in total")
                    .font(.caption2)
                    .foregroundStyle(isOverCapacity ? Theme.accent : Theme.textPrimary.opacity(0.55))
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                stepButton(systemImage: "minus", isEnabled: shape.canRemoveRow) {
                    change(shape.settingRowCount(shape.rows.count - 1, capacity: capacity))
                }
                Text("\(shape.rows.count)")
                    .font(.metric(19))
                    .foregroundStyle(tint)
                    .frame(minWidth: 26)
                    .contentTransition(.numericText())
                stepButton(systemImage: "plus", isEnabled: shape.canAddRow(capacity: capacity)) {
                    change(shape.settingRowCount(shape.rows.count + 1, capacity: capacity))
                }
            }
        }
    }

    private func rowControl(index: Int, width: Int) -> some View {
        HStack(spacing: 10) {
            Text("Row \(index + 1)")
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(Theme.textPrimary.opacity(0.65))
                .frame(width: 52, alignment: .leading)

            HStack(spacing: 8) {
                ForEach(1...capacity.maxColumns, id: \.self) { candidate in
                    widthButton(candidate, row: index, current: width)
                }
            }
        }
    }

    /// One choice of how many readouts a row holds, drawn as that many blocks
    /// sharing the row evenly — the shape it will actually make on the wrist.
    private func widthButton(_ width: Int, row: Int, current: Int) -> some View {
        let isSelected = width == current
        let isAllowed = shape.canSetWidth(width, forRow: row, capacity: capacity)
        return Button {
            guard let next = shape.settingWidth(width, forRow: row, capacity: capacity) else { return }
            change(next)
        } label: {
            HStack(spacing: 3) {
                ForEach(0..<width, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isSelected ? tint : Theme.textPrimary.opacity(isAllowed ? 0.3 : 0.12))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.14) : Theme.surfaceRaised)
                    .strokeBorder(isSelected ? tint : Theme.border, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAllowed)
        .accessibilityLabel("Row \(row + 1), \(width) \(width == 1 ? "field" : "fields")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func stepButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 38, height: 32)
                .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textPrimary.opacity(0.25))
                .background(Theme.surfaceRaised, in: .rect(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(systemImage == "plus" ? "Add a row" : "Remove a row")
    }

    private func change(_ next: WatchPageLayout) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            onChange(next)
        }
    }
}
