import SwiftUI
import UniformTypeIdentifiers

/// A Trekka backup on disk. Plain JSON, so it can be read, kept anywhere and
/// moved between devices without Trekka's help.
nonisolated struct BackupFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw BackupError.unreadable
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Saving and restoring the athlete's data — to their own iCloud, or to a file
/// they keep themselves. Both paths write the same archive and offer the same
/// choice of what to include, so neither is the poor relation.
struct BackupView: View {
    @Environment(RouteStore.self) private var routes
    @Environment(WatchLayoutStore.self) private var watchLayout
    @Environment(DashboardSettings.self) private var dashboard
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(UnitSettings.self) private var units
    @Environment(MapPackStore.self) private var mapPacks

    @State private var cloud = CloudBackupService()
    @State private var selection: Set<BackupSection> = Set(BackupSection.allCases)

    @State private var exportDocument: BackupFileDocument?
    @State private var exportFilename = "Trekka Backup"
    @State private var isExporting = false
    @State private var isImporting = false

    @State private var pendingArchive: SummitArchive?
    @State private var pendingOrigin = ""
    @State private var showsRestoreSheet = false
    @State private var showsDeleteConfirmation = false

    @State private var resultLines: [String] = []
    @State private var localError: String?
    @State private var feedback = 0

    private var stores: BackupStores {
        BackupStores(
            routes: routes,
            watchLayout: watchLayout,
            dashboard: dashboard,
            appearance: appearance,
            units: units,
            mapPacks: mapPacks
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !resultLines.isEmpty { resultBanner }
                cloudCard
                includeSection
                fileSection
                footnote
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.canvas, for: .navigationBar)
        .animation(.snappy(duration: 0.26), value: resultLines)
        .animation(.snappy(duration: 0.26), value: cloud.activity)
        .sensoryFeedback(.success, trigger: feedback)
        .task { await cloud.refresh() }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                resultLines = ["Backup file saved"]
                feedback += 1
            case .failure:
                localError = "The file could not be saved. Try another location."
            }
            exportDocument = nil
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json]
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showsRestoreSheet) {
            if let pendingArchive {
                RestoreReviewSheet(archive: pendingArchive, origin: pendingOrigin) { sections, strategy in
                    restore(pendingArchive, sections: sections, strategy: strategy)
                }
            }
        }
        .confirmationDialog(
            "Remove the iCloud backup?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from iCloud", role: .destructive) {
                Task {
                    await cloud.deleteBackup(sections: Set(BackupSection.allCases))
                    if cloud.lastError == nil {
                        resultLines = ["iCloud backup removed"]
                        feedback += 1
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing on this phone changes. You just will not be able to restore from iCloud until you back up again.")
        }
    }

    // MARK: - iCloud

    private var cloudCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: cloud.hasBackup ? "checkmark.icloud.fill" : "icloud")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(cloud.hasBackup ? Theme.positive : Theme.accent)
                    .frame(width: 48, height: 48)
                    .background(
                        (cloud.hasBackup ? Theme.positive : Theme.accent).opacity(0.12),
                        in: .rect(cornerRadius: 13)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("iCloud Backup")
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(cloudStatusLine)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if let activity = cloud.activity {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accent)
                    Text(activity)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }

            if let error = cloud.lastError ?? localError {
                errorRow(error)
            }

            HStack(spacing: 10) {
                actionButton(
                    title: "Back up now",
                    symbol: "arrow.up.to.line",
                    isProminent: true,
                    isEnabled: cloud.availability.isReady && !cloud.isWorking && !selection.isEmpty
                ) {
                    Task { await backUpToCloud() }
                }

                actionButton(
                    title: "Restore",
                    symbol: "arrow.down.to.line",
                    isProminent: false,
                    isEnabled: cloud.availability.isReady && !cloud.isWorking && cloud.hasBackup
                ) {
                    Task { await restoreFromCloud() }
                }
            }

            if cloud.hasBackup {
                Button {
                    showsDeleteConfirmation = true
                } label: {
                    Text("Remove backup from iCloud")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(cloud.isWorking)
            }
        }
        .padding(16)
        .panel()
    }

    private var cloudStatusLine: String {
        if !cloud.availability.isReady { return cloud.availability.message }
        guard let last = cloud.lastBackupAt else {
            return "Nothing backed up yet — your data stays on this phone."
        }
        return "Last backup \(last.formatted(.relative(presentation: .named)))"
    }

    // MARK: - Selection

    private var includeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("What to include")
                    .metricLabelStyle()
                Spacer()
                Button(selection.count == BackupSection.allCases.count ? "None" : "All") {
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = selection.count == BackupSection.allCases.count
                            ? []
                            : Set(BackupSection.allCases)
                    }
                }
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Theme.accent)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(BackupSection.ordered.enumerated()), id: \.element) { index, section in
                    if index > 0 { divider }
                    selectionRow(section)
                }
            }
            .panel()
        }
    }

    private func selectionRow(_ section: BackupSection) -> some View {
        let isOn = selection.contains(section)
        let stored = cloud.remote[section]
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isOn { selection.remove(section) } else { selection.insert(section) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.accent : Theme.textPrimary.opacity(0.25))

                Image(systemName: section.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .frame(width: 30, height: 30)
                    .background(Theme.surfaceRaised, in: .rect(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(BackupArchive.liveSummary(for: section, in: stores))
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

                if let stored {
                    VStack(alignment: .trailing, spacing: 1) {
                        Image(systemName: "checkmark.icloud")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.positive)
                        Text(stored.updatedAt.formatted(.relative(presentation: .numeric)))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    }
                }
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Files

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backup files")
                .metricLabelStyle()
                .padding(.leading, 4)

            VStack(spacing: 0) {
                row(
                    symbol: "square.and.arrow.up",
                    title: "Export a file",
                    detail: selection.isEmpty
                        ? "Choose what to include first"
                        : "Save the selected data to Files, iCloud Drive or anywhere else",
                    isEnabled: !selection.isEmpty
                ) {
                    export()
                }
                divider
                row(
                    symbol: "square.and.arrow.down",
                    title: "Import a file",
                    detail: "Read a Trekka backup file and choose what to bring in"
                ) {
                    localError = nil
                    isImporting = true
                }
            }
            .panel()
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Backups are your data only — they hold no personal account and are never sent to Trekka. The iCloud copy lives in your own private iCloud storage.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
            Text("Offline maps are not included: they are large and can be downloaded again on the Routes tab. Workouts written to Apple Health stay in Health and come back with your device backup.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private var resultBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.positive)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(resultLines, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)

            Button {
                withAnimation(.snappy(duration: 0.2)) { resultLines = [] }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.4))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.positive.opacity(0.1), in: .rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.positive.opacity(0.3), lineWidth: 1)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Actions

    private func backUpToCloud() async {
        localError = nil
        resultLines = []
        let archive = BackupArchive.make(sections: selection, from: stores)
        let stored = await cloud.backUp(archive, sections: selection)
        guard stored else { return }
        resultLines = selection.count == BackupSection.allCases.count
            ? ["Everything backed up to iCloud"]
            : ["Backed up to iCloud: " + BackupSection.ordered
                .filter(selection.contains)
                .map { $0.title.lowercased() }
                .formatted(.list(type: .and))]
        feedback += 1
    }

    private func restoreFromCloud() async {
        localError = nil
        resultLines = []
        // Everything stored is fetched, then reviewed — the choice of what to
        // put back belongs on the review screen, beside what each part holds.
        guard let archive = await cloud.fetchArchive(sections: Set(cloud.remote.keys)) else { return }
        pendingArchive = archive
        pendingOrigin = "iCloud"
        showsRestoreSheet = true
    }

    private func export() {
        localError = nil
        resultLines = []
        let archive = BackupArchive.make(sections: selection, from: stores)
        do {
            exportDocument = BackupFileDocument(data: try archive.encoded())
            exportFilename = archive.suggestedFilename
            isExporting = true
        } catch {
            localError = "That backup could not be prepared. Try fewer kinds of data."
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        localError = nil
        resultLines = []
        switch result {
        case .success(let url):
            // A file picked outside the app's own storage has to be opened
            // explicitly, and closed again whatever happens.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let archive = try SummitArchive.decode(try Data(contentsOf: url))
                pendingArchive = archive
                pendingOrigin = url.lastPathComponent
                showsRestoreSheet = true
            } catch let error as BackupError {
                localError = error.errorDescription
            } catch {
                localError = BackupError.unreadable.errorDescription
            }
        case .failure:
            localError = "That file could not be opened."
        }
    }

    private func restore(_ archive: SummitArchive, sections: Set<BackupSection>, strategy: RestoreStrategy) {
        let report = BackupArchive.apply(archive, sections: sections, strategy: strategy, to: stores)
        resultLines = report.isEmpty ? ["Nothing to restore"] : report
        pendingArchive = nil
        feedback += 1
    }

    // MARK: - Building blocks

    private func actionButton(
        title: String,
        symbol: String,
        isProminent: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(.subheadline, weight: .bold))
            }
            .foregroundStyle(
                isEnabled
                    ? (isProminent ? Theme.canvas : Theme.accent)
                    : Theme.textPrimary.opacity(0.35)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if isProminent {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isEnabled ? Theme.accent : Theme.surfaceRaised)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isEnabled ? Theme.accent.opacity(0.55) : Theme.border,
                            lineWidth: 1.5
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.caption)
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.danger.opacity(0.1), in: .rect(cornerRadius: 10))
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 54)
    }

    private func row(
        symbol: String,
        title: String,
        detail: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isEnabled ? Theme.accent : Theme.textPrimary.opacity(0.3))
                    .frame(width: 30, height: 30)
                    .background(
                        (isEnabled ? Theme.accent : Theme.textPrimary).opacity(0.12),
                        in: .rect(cornerRadius: 9)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textPrimary.opacity(0.4))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary.opacity(0.3))
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
