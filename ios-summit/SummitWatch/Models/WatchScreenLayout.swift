import Foundation

/// How prominent a readout is in its row. The renderer maps this onto a real
/// type size, so the model can describe emphasis without knowing about fonts.
nonisolated enum WatchSlotEmphasis: Sendable {
    case hero, large, standard, compact
}

/// How many readouts a watch of a given physical size can hold while staying
/// legible. The watch knows its own screen; the phone learns it over Watch
/// Connectivity and mirrors this mapping exactly, so both builders offer the
/// same shapes for the same wrist.
nonisolated struct WatchScreenCapacity: Hashable, Sendable {
    var maxRows: Int
    var maxColumns: Int
    var maxSlots: Int

    /// The ceiling for an unknown screen — never larger than the layout model
    /// itself allows, so a capacity can only ever tighten the limits.
    static let ceiling = WatchScreenCapacity(
        maxRows: WatchScreenLayout.maxRows,
        maxColumns: WatchScreenLayout.maxColumns,
        maxSlots: WatchScreenLayout.maxSlots
    )

    /// 40 mm and 41 mm: two readouts per row at most and six in total, where a
    /// third column would shrink values past what is readable mid-stride.
    static let compact = WatchScreenCapacity(maxRows: 4, maxColumns: 2, maxSlots: 6)

    /// Same thresholds as the renderer's size classes in WatchDisplay.
    static func forScreen(width: CGFloat) -> WatchScreenCapacity {
        width < 176 ? .compact : .ceiling
    }
}

/// The shape of a data screen: how many readouts sit in each row, top to bottom.
///
/// Encoded as a dash-joined pattern ("1-2-1" is one field on top, two in the
/// middle, one at the bottom) so the document stays readable and a build that
/// does not recognise a pattern can fall back rather than fail.
nonisolated struct WatchScreenLayout: Hashable, Sendable, Identifiable {
    /// Number of fields in each row, top to bottom.
    let rows: [Int]

    static let maxRows = 4
    static let maxColumns = 3
    static let maxSlots = 9

    /// Fails rather than clamping: an impossible pattern should be ignored by
    /// the decoder, not silently turned into a different screen.
    init?(rows: [Int]) {
        guard !rows.isEmpty,
              rows.count <= Self.maxRows,
              rows.allSatisfy({ $0 >= 1 && $0 <= Self.maxColumns }),
              rows.reduce(0, +) <= Self.maxSlots else { return nil }
        self.rows = rows
    }

    var id: String { rawValue }
    var rawValue: String { rows.map(String.init).joined(separator: "-") }
    var slotCount: Int { rows.reduce(0, +) }

    /// "1 · 2 · 1" — reads as the shape it describes.
    var title: String { rows.map(String.init).joined(separator: " · ") }

    var summary: String {
        let fields = slotCount == 1 ? "1 metric" : "\(slotCount) metrics"
        return rows.count == 1 ? fields : "\(fields) · \(rows.count) rows"
    }

    /// The arrangement used when no layout has been chosen, so a screen still
    /// looks deliberate as metrics are added and removed. Held to `capacity`
    /// so a small watch never suggests more than it can hold.
    static func automatic(forSlots count: Int, capacity: WatchScreenCapacity = .ceiling) -> WatchScreenLayout {
        let clamped = min(max(count, 1), capacity.maxSlots)
        let pattern: [Int]
        switch clamped {
        case ..<2: pattern = [1]
        case 2: pattern = [1, 1]
        case 3: pattern = [1, 2]
        case 4: pattern = [2, 2]
        case 5: pattern = [1, 2, 2]
        case 6: pattern = [2, 2, 2]
        case 7: pattern = [1, 2, 2, 2]
        case 8: pattern = [2, 2, 2, 2]
        default: pattern = [3, 3, 3]
        }
        return WatchScreenLayout(rows: pattern) ?? WatchScreenLayout(rows: [1])!
    }

    /// Splits a field list into rows, dropping rows there are no fields for.
    func slice<T>(_ items: [T]) -> [[T]] {
        var result: [[T]] = []
        var index = 0
        for width in rows {
            guard index < items.count else { break }
            let end = min(index + width, items.count)
            result.append(Array(items[index..<end]))
            index = end
        }
        return result
    }

    /// Type size for a row, chosen so a screen fills the bezel without
    /// scrolling however many rows it has.
    func emphasis(forRow index: Int) -> WatchSlotEmphasis {
        guard rows.indices.contains(index) else { return .standard }
        let width = rows[index]
        switch rows.count {
        case 1:
            switch width {
            case 1: return .hero
            case 2: return .large
            default: return .standard
            }
        case 2:
            switch (rows[0], rows[1]) {
            case (1, 1): return index == 0 ? .hero : .large
            case (1, 2), (2, 1): return width == 1 ? .hero : .standard
            case (2, 2): return .large
            case (1, 3), (3, 1): return width == 1 ? .hero : .compact
            default: return width == 3 ? .compact : .standard
            }
        case 3:
            switch width {
            case 1: return .large
            case 2: return .standard
            default: return .compact
            }
        default:
            return width == 1 ? .standard : .compact
        }
    }

    /// Where a slot sits, for the editor's slot list. "Row 2 · left".
    func position(ofSlot slot: Int) -> String {
        var index = 0
        for (rowIndex, width) in rows.enumerated() {
            if slot < index + width {
                let column = slot - index
                guard width > 1 else { return "Row \(rowIndex + 1)" }
                let side = width == 2
                    ? (column == 0 ? "left" : "right")
                    : ["left", "centre", "right"][min(column, 2)]
                return "Row \(rowIndex + 1) · \(side)"
            }
            index += width
        }
        return "Row \(rows.count)"
    }

    // MARK: - Building

    func canAddRow(capacity: WatchScreenCapacity = .ceiling) -> Bool {
        rows.count < capacity.maxRows && slotCount < capacity.maxSlots
    }
    var canRemoveRow: Bool { rows.count > 1 }

    /// The same shape with a different number of rows. A new row arrives
    /// holding one readout; removing takes from the bottom.
    func settingRowCount(_ count: Int, capacity: WatchScreenCapacity = .ceiling) -> WatchScreenLayout {
        let target = min(max(count, 1), capacity.maxRows)
        var widths = rows
        while widths.count > target { widths.removeLast() }
        while widths.count < target, widths.reduce(0, +) < capacity.maxSlots { widths.append(1) }
        return WatchScreenLayout(rows: widths) ?? self
    }

    /// The same shape with one row holding a different number of readouts, or
    /// nil when that would overflow the screen or the watch's capacity — so the
    /// caller can dim the choice rather than silently rearranging something else.
    func settingWidth(_ width: Int, forRow index: Int, capacity: WatchScreenCapacity = .ceiling) -> WatchScreenLayout? {
        guard rows.indices.contains(index),
              width >= 1, width <= capacity.maxColumns,
              slotCount - rows[index] + width <= capacity.maxSlots else { return nil }
        var widths = rows
        widths[index] = width
        return WatchScreenLayout(rows: widths)
    }

    func canSetWidth(_ width: Int, forRow index: Int, capacity: WatchScreenCapacity = .ceiling) -> Bool {
        settingWidth(width, forRow: index, capacity: capacity) != nil
    }

    /// The nearest shape holding exactly `count` readouts, narrowing the lower
    /// rows first so the top of the screen keeps the arrangement it had. Growth
    /// stays inside `capacity`, so a small watch never widens past its columns.
    func trimmed(toSlots count: Int, capacity: WatchScreenCapacity = .ceiling) -> WatchScreenLayout? {
        guard count >= 1, count <= capacity.maxSlots else { return nil }
        var widths = rows
        while widths.reduce(0, +) > count {
            if let index = widths.lastIndex(where: { $0 > 1 }) {
                widths[index] -= 1
            } else {
                widths.removeLast()
            }
        }
        while widths.reduce(0, +) < count {
            if let index = widths.lastIndex(where: { $0 < capacity.maxColumns }) {
                widths[index] += 1
            } else if widths.count < capacity.maxRows {
                widths.append(1)
            } else {
                break
            }
        }
        return WatchScreenLayout(rows: widths)
    }
}

extension WatchScreenLayout: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let parts = raw.split(separator: "-").map(String.init)
        let numbers = parts.compactMap(Int.init)
        guard numbers.count == parts.count, let layout = WatchScreenLayout(rows: numbers) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised layout \(raw)")
        }
        self = layout
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
