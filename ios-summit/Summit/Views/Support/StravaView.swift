import SwiftUI

/// The Strava connection, in one screen: sign in, decide what gets sent, sign out.
struct StravaView: View {
    @Environment(StravaService.self) private var strava
    @Environment(RouteStore.self) private var store

    @State private var isWorking = false
    @State private var confirmsDisconnect = false

    private var recentActivities: [ActivityRecord] {
        Array(store.activities.sorted { $0.startDate > $1.startDate }.prefix(10))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusCard

                if strava.isConnected {
                    optionsCard
                    sendCard
                } else if case .notConfigured = strava.connection {
                    unavailableCard
                } else {
                    explainerCard
                }

                if let result = strava.lastResult {
                    resultCard(result)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .background(Theme.canvas)
        .scrollIndicators(.hidden)
        .navigationTitle("Strava")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy(duration: 0.28), value: strava.isConnected)
        .confirmationDialog(
            "Disconnect Strava?",
            isPresented: $confirmsDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task { await strava.disconnect() }
            }
            Button("Keep connected", role: .cancel) {}
        } message: {
            Text("Trekka will forget your Strava sign-in and withdraw its access. Workouts already on Strava stay there.")
        }
    }

    // MARK: - Cards

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(strava.isConnected ? Theme.positive : Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if case .notConfigured = strava.connection {
                EmptyView()
            } else if strava.isConnected {
                Button {
                    confirmsDisconnect = true
                } label: {
                    Text("Disconnect")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.danger.opacity(0.12), in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Task {
                        isWorking = true
                        await strava.connect()
                        isWorking = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isWorking { ProgressView().tint(Theme.canvas) }
                        Text(isWorking ? "Opening Strava…" : "Sign in with Strava")
                            .font(.system(.subheadline, weight: .bold))
                    }
                    .foregroundStyle(Theme.canvas)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.accent, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var optionsCard: some View {
        @Bindable var strava = strava

        return VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $strava.isAutoUploadEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Send new workouts automatically")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Each workout goes across once it is saved.")
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.5))
                }
            }
            .tint(Theme.accent)

            // Says plainly what leaves the phone. An athlete turning this on is
            // agreeing to publish where they went, and that deserves a sentence
            // rather than a switch on its own.
            Text("Sending a workout uploads its route, distance, time and climb to Strava, under your Strava account. Nothing else in Trekka is shared — not your food diary, your sleep, or your readiness.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var sendCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent workouts")
                .metricLabelStyle()

            if recentActivities.isEmpty {
                Text("Nothing recorded yet. Workouts appear here once you have one to send.")
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            } else {
                ForEach(recentActivities) { activity in
                    activityRow(activity)
                    if activity.id != recentActivities.last?.id {
                        Rectangle().fill(Theme.border).frame(height: 1)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func activityRow(_ activity: ActivityRecord) -> some View {
        let isSent = strava.hasSent(activity.id)
        let isSending = strava.sendingActivityID == activity.id

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle(for: activity))
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
            }
            Spacer(minLength: 0)

            if isSending {
                ProgressView().tint(Theme.accent)
            } else if isSent {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.positive)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Send") {
                    Task { await strava.send(activity) }
                }
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(Theme.accent)
                .disabled(strava.sendingActivityID != nil)
            }
        }
        .padding(.vertical, 8)
    }

    private func resultCard(_ result: StravaService.SendResult) -> some View {
        let isFailure: Bool
        let text: String
        switch result {
        case let .sent(message):
            isFailure = false
            text = message
        case let .failed(message):
            isFailure = true
            text = message
        }

        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isFailure ? Theme.danger : Theme.positive)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isFailure ? Theme.danger : Theme.positive).opacity(0.1), in: .rect(cornerRadius: 12))
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            point("map.fill", "Your route, as you walked it", "Workouts with a recorded track go across with their real trace and their real times, so Strava draws the map and works out the splits from what actually happened.")
            point("dumbbell.fill", "Gym sessions too", "A session with no track is sent as a summary — its name, sport, start, duration and sets in the description.")
            point("hand.raised.fill", "Only what you send", "Trekka never uploads anything else. Sign-in is handled by Strava; Trekka never sees your Strava password.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Strava is not set up in this build")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Connecting to Strava needs an application key issued by Strava to Trekka. Once that is in place, this screen signs you in and starts sending workouts across. Everything else in Trekka works without it.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Copy

    private var headline: String {
        switch strava.connection {
        case .notConfigured: "Strava is unavailable"
        case .signedOut: "Not connected"
        case .connecting: "Connecting…"
        case let .connected(athlete): athlete ?? "Connected to Strava"
        case .failed: "Could not connect"
        }
    }

    private var detail: String {
        switch strava.connection {
        case .notConfigured:
            "This copy of Trekka has no Strava key."
        case .signedOut:
            "Sign in to send your workouts to Strava."
        case .connecting:
            "Waiting for Strava."
        case .connected:
            strava.isAutoUploadEnabled
                ? "New workouts are sent automatically."
                : "Workouts are sent when you choose to send them."
        case let .failed(message):
            message
        }
    }

    private func subtitle(for activity: ActivityRecord) -> String {
        let day = activity.startDate.formatted(.dateTime.day().month(.abbreviated))
        guard activity.distance > 0 else {
            return "\(day) · \(Formatters.compactDuration(activity.duration))"
        }
        return "\(day) · \(Formatters.distanceWithUnit(activity.distance))"
    }
}
