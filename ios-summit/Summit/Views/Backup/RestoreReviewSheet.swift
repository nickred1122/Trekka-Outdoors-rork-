import SwiftUI

/// Shown before anything is written back, so a restore is always a decision
/// rather than a surprise: what the backup holds, how old it is, where it came
/// from, and what it will do to the data already on this phone.
struct RestoreReviewSheet: View {
    let archive: SummitArchive
    /// Where this archive came from, e.g. "iCloud" or a filename.
    let origin: String
    var onRestore: (Set<BackupSection>, RestoreStrategy) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<BackupSection>
    @State private var strategy: RestoreStrategy = .merge
    @State private var showsReplaceConfirmation = false

    init(
        archive: SummitArchive,
        origin: String,
        onRestore: @escaping (Set<BackupSection>, RestoreStrategy) -> Void
    ) {
        self.archive = archive
        self.origin = origin
        self.onRestore = onRestore
        _selection = State(initialValue: Set(archive.includedSections))
    }

    /// Only the sections that can actually take part in the chosen strategy.
    private var mergeableSelection: [BackupSection] {
        selection.filter(\.supportsMerging).sorted { $0.rawValue < $1.rawValue }
    }

    private var replacesSomething: Bool {
        strategy == .replace && !mergeableSelection.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    provenanceCard
                    contentsSection
                    strategySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Restore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { restoreBar }
        }
        .confirmationDialog(
            "Replace data on this phone?",
            isPresented: $showsReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace", role: .destructive) { commit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anything recorded since this backup was made will be removed. This cannot be undone.")
        }
    }

    // MARK: - Cards

    private var provenanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(archive.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(origin) · \(archive.deviceName)")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Text("Made with Trekka \(archive.appVersion), \(archive.createdAt.formatted(.relative(presentation: .named))).")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var contentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What to restore")
                .metricLabelStyle()
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(archive.includedSections.enumerated()), id: \.element) { index, section in
                    if index > 0 { divider }
                    sectionRow(section)
                }
            }
            .panel()
        }
    }

    private func sectionRow(_ section: BackupSection) -> some View {
        let isOn = selection.contains(section)
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                if isOn { selection.remove(section) } else { selection.insert(section) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.accent : Theme.textPrimary.opacity(0.25))

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(archive.summary(for: section) ?? "")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
                Spacer(minLength: 0)
                if !section.supportsMerging {
                    Text("Replaces")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.45))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.surfaceRaised, in: .capsule)
                }
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var strategySection: some View {
        if mergeableSelection.isEmpty {
            Text("Watch screens and app settings are single documents, so restoring them puts the backup's version in place of the current one.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Routes & activities")
                    .metricLabelStyle()
                    .padding(.leading, 4)

                VStack(spacing: 0) {
                    ForEach(RestoreStrategy.allCases) { option in
                        if option != RestoreStrategy.allCases.first { divider }
                        strategyRow(option)
                    }
                }
                .panel()
            }
        }
    }

    private func strategyRow(_ option: RestoreStrategy) -> some View {
        let isOn = strategy == option
        return Button {
            withAnimation(.snappy(duration: 0.2)) { strategy = option }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.accent : Theme.textPrimary.opacity(0.25))

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(option == .replace ? Theme.danger : Theme.textPrimary)
                    Text(option.detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var restoreBar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Theme.canvas.opacity(0), Theme.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)

            Button {
                if replacesSomething {
                    showsReplaceConfirmation = true
                } else {
                    commit()
                }
            } label: {
                Text(selection.isEmpty ? "Choose what to restore" : "Restore \(selection.count) item\(selection.count == 1 ? "" : "s")")
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(selection.isEmpty ? Theme.textPrimary.opacity(0.4) : Theme.canvas)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        selection.isEmpty ? Theme.surfaceRaised : (replacesSomething ? Theme.danger : Theme.accent),
                        in: .rect(cornerRadius: 14)
                    )
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            .background(Theme.canvas)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.leading, 44)
    }

    private func commit() {
        onRestore(selection, strategy)
        dismiss()
    }
}
