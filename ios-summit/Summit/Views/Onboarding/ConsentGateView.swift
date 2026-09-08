import SwiftUI

/// The three agreements, each with its own tick box and its own full text.
///
/// Shared by first run and by the standalone gate an existing athlete sees after
/// an update, so there is exactly one implementation of "has this been agreed
/// to" and the two can never drift apart.
struct ConsentChecklist: View {
    @Binding var accepted: Set<LegalDocumentKind>
    var onToggle: () -> Void = {}

    @State private var reading: LegalDocument?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(LegalDocument.all) { document in
                row(document)
            }
        }
        .sheet(item: $reading) { LegalDocumentView(document: $0) }
    }

    private func row(_ document: LegalDocument) -> some View {
        let isAccepted = accepted.contains(document.kind)
        return VStack(spacing: 0) {
            // The tick box is its own button, and reading is its own button.
            // One control that both agreed and opened would make it possible to
            // agree by trying to read.
            HStack(alignment: .top, spacing: 12) {
                Button {
                    if isAccepted {
                        accepted.remove(document.kind)
                    } else {
                        accepted.insert(document.kind)
                    }
                    onToggle()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(isAccepted ? Theme.accent : Theme.textPrimary.opacity(0.3))
                            .frame(width: 24, height: 24)
                            .contentTransition(.symbolEffect(.replace))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(document.acceptance)
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(document.summary)
                                .font(.caption)
                                .foregroundStyle(Theme.textPrimary.opacity(0.5))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isAccepted ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(isAccepted ? "Tap to withdraw agreement" : "Tap to agree")
            }
            .padding(13)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            Button {
                reading = document
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: document.symbol)
                        .font(.system(size: 12, weight: .semibold))
                    Text("Read the \(document.title)")
                        .font(.system(.caption, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.3))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(
                    isAccepted ? Theme.accent.opacity(0.55) : Theme.border,
                    lineWidth: isAccepted ? 1.5 : 1
                )
        }
        .animation(.snappy(duration: 0.2), value: isAccepted)
    }
}

/// Shown when somebody who has already been through first run needs to accept a
/// new or revised agreement.
///
/// Deliberately not the whole of first run again — they have already chosen
/// their units and their goals, and walking them back through those to collect a
/// signature would be both rude and a good way to overwrite their settings.
struct ConsentGateView: View {
    @Environment(ConsentSettings.self) private var consent

    var onAccepted: () -> Void

    @State private var accepted: Set<LegalDocumentKind> = []
    @State private var feedback = 0

    private var isReady: Bool {
        accepted.count == LegalDocument.all.count
    }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Theme.accent)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(consent.isReconsenting ? "We've updated our terms" : "Before you start")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(consent.isReconsenting
                                ? "Please read and accept the updated agreements to carry on using \(LegalAgreements.appName). Your routes, activities and settings are untouched."
                                : "Please read and accept these three before using \(LegalAgreements.appName).")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ConsentChecklist(accepted: $accepted) { feedback += 1 }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 30)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)

                ConsentFooter(isReady: isReady) {
                    consent.acceptAll()
                    onAccepted()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .sensoryFeedback(.selection, trigger: feedback)
        .interactiveDismissDisabled()
    }

    private var backdrop: some View {
        ZStack {
            Theme.canvas
            RadialGradient(
                colors: [Theme.accent.opacity(0.2), Theme.accent.opacity(0)],
                center: .init(x: 0.15, y: 0.05),
                startRadius: 10,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}

/// The one button, and the line explaining why it is not available yet.
///
/// The button stays visible and disabled rather than hidden, so it is obvious
/// that continuing is possible and what is standing in the way.
struct ConsentFooter: View {
    let isReady: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            Button(action: action) {
                Text("Agree & continue")
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(isReady ? Theme.canvas : Theme.textPrimary.opacity(0.35))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        isReady ? Theme.accent : Theme.surfaceRaised,
                        in: .rect(cornerRadius: 14)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isReady)
            .animation(.snappy(duration: 0.2), value: isReady)

            Text(isReady
                ? "This is the only step that cannot be skipped."
                : "All three must be accepted to continue.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.42))
                .frame(height: 26)
        }
    }
}
