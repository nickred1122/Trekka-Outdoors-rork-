import SwiftUI

/// The running record of what the app did, newest first.
///
/// Exists so a fault can be reported with its actual timestamps and reasons
/// rather than recalled. Failures can be isolated with one tap, because that is
/// what anybody opening this screen is looking for.
struct EventLogView: View {
    @State private var showsFailuresOnly = false
    @State private var showsClearConfirmation = false
    @State private var didCopy = false

    private let log = EventLog.shared

    private var visible: [LoggedEvent] {
        let all = log.newestFirst
        return showsFailuresOnly ? all.filter { $0.level == .failure } : all
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                header

                if visible.isEmpty {
                    emptyState
                } else {
                    ForEach(visible) { event in
                        eventCard(event)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Event log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = log.report()
                        didCopy = true
                    } label: {
                        Label("Copy report", systemImage: "doc.on.doc")
                    }
                    Button(role: .destructive) {
                        showsClearConfirmation = true
                    } label: {
                        Label("Clear log", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Clear the event log?", isPresented: $showsClearConfirmation) {
            Button("Clear", role: .destructive) { log.clear() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Everything recorded so far is deleted. This cannot be undone.")
        }
        .sensoryFeedback(.success, trigger: didCopy)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Everything the app records as it happens. Nothing here leaves your phone unless you copy it out yourself.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                countChip(
                    "\(log.events.count)",
                    label: log.events.count == 1 ? "event" : "events",
                    tint: Theme.accent
                )
                if log.failureCount > 0 {
                    countChip(
                        "\(log.failureCount)",
                        label: log.failureCount == 1 ? "failure" : "failures",
                        tint: Theme.danger
                    )
                }
                Spacer(minLength: 0)
            }

            Toggle(isOn: $showsFailuresOnly) {
                Text("Failures only")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(radius: 14)
    }

    private func countChip(_ value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: .capsule)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: showsFailuresOnly ? "checkmark.seal" : "text.append")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textPrimary.opacity(0.3))
            Text(showsFailuresOnly ? "No failures recorded" : "Nothing recorded yet")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(showsFailuresOnly
                 ? "Every event so far went through cleanly."
                 : "Downloads, syncs and Health access will appear here as they happen.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .panel(radius: 14)
    }

    private func eventCard(_ event: LoggedEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.level.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint(for: event.level))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.category.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint(for: event.level))
                    Spacer(minLength: 0)
                    Text(event.at.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary.opacity(0.4))
                }
                Text(event.message)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(radius: 12)
    }

    private func tint(for level: EventLevel) -> Color {
        switch level {
        case .info: Theme.accent
        case .warning: Theme.highlight
        case .failure: Theme.danger
        }
    }
}
