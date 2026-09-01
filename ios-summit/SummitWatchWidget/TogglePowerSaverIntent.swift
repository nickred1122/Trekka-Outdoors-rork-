import AppIntents
import WidgetKit

/// Arms or clears workout power saver straight from the watch face.
///
/// The intent runs inside the widget extension, so it only writes to the shared
/// container. The Trekka app applies it on its next tick — or the next time it
/// comes forward if no workout is running.
nonisolated struct TogglePowerSaverIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Power Saver"
    static let description = IntentDescription("Arms Trekka's workout power saver from the watch face.")

    func perform() async throws -> some IntentResult {
        let snapshot = PowerFace.load()
        PowerFace.request(!snapshot.isPowerSaving)
        return .result()
    }
}
