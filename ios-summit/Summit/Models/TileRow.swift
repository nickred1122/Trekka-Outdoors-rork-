import Foundation

/// One row of the dashboard, once tile widths are taken into account.
///
/// The dashboard used to be an adaptive grid, which cannot be told to let a
/// single cell span two columns. Now that a tile can be widened, the rows are
/// worked out up front instead: a wide tile takes a row to itself, and narrow
/// tiles pair up in the order the athlete put them in.
nonisolated struct TileRow: Identifiable, Sendable {
    let id: Int
    let metrics: [DashboardMetric]
    /// True for a row holding a single narrow tile, which needs an empty half
    /// beside it so it stays half width rather than stretching across.
    let needsFiller: Bool

    static func rows(
        for metrics: [DashboardMetric],
        isWide: (DashboardMetric) -> Bool
    ) -> [TileRow] {
        var rows: [TileRow] = []
        var pending: [DashboardMetric] = []

        func flushPending() {
            guard !pending.isEmpty else { return }
            rows.append(TileRow(id: rows.count, metrics: pending, needsFiller: pending.count == 1))
            pending = []
        }

        for metric in metrics {
            if isWide(metric) {
                // A wide tile cannot share a row, so anything waiting for a
                // partner gives up and takes its half-width slot now.
                flushPending()
                rows.append(TileRow(id: rows.count, metrics: [metric], needsFiller: false))
            } else {
                pending.append(metric)
                if pending.count == 2 { flushPending() }
            }
        }
        flushPending()
        return rows
    }
}
