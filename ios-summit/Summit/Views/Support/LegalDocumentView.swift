import SwiftUI

/// One agreement, read in full.
///
/// Presented as a sheet from first run and from Settings, so the wording an
/// athlete agreed to is always reachable rather than being a link they saw once.
struct LegalDocumentView: View {
    let document: LegalDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    ForEach(document.sections) { section in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(section.heading)
                                .font(.system(.headline, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(section.body)
                                .font(.callout)
                                .foregroundStyle(Theme.textPrimary.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .background(Theme.canvas)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(.subheadline, weight: .semibold))
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: document.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.accent)

            Text(document.summary)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(LegalAgreements.appName) · effective \(LegalAgreements.effectiveDate)")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }
}
