import SwiftUI

/// A conversation with Trekka about the athlete's own training.
///
/// The facts handed to the assistant are built here, from the same engines the
/// dashboard and the insights screen use — so anything Trekka says in the chat
/// can be found somewhere else in the app as a number on a card. Nothing is
/// computed specially for the conversation, which is what keeps the two from
/// disagreeing.
struct TrekkaChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TrekkaChatService.self) private var chat
    @Environment(RouteStore.self) private var store
    @Environment(HealthService.self) private var health
    @Environment(NutritionStore.self) private var nutrition
    @Environment(GoalSettings.self) private var goals
    @Environment(ProfileSettings.self) private var profile

    @State private var draft = ""
    @FocusState private var isTyping: Bool

    private var allActivities: [ActivityRecord] {
        (store.activities + health.healthActivities).sorted { $0.startDate > $1.startDate }
    }

    /// Everything Trekka is allowed to answer from.
    private var facts: [String] {
        var lines = InsightEngine.insights(
            activities: allActivities,
            snapshot: health.snapshot,
            day: nutrition.day(Date()),
            fuelGoals: nutrition.goals,
            dailyGoals: goals.snapshot
        ).map(\.fact)

        // The three most recent sessions by name, so "how was my last run?" has
        // something to land on.
        for activity in allActivities.prefix(3) {
            var parts = [activity.name, activity.startDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))]
            if activity.distance > 0 { parts.append(Formatters.distanceWithUnit(activity.distance)) }
            parts.append(Formatters.compactDuration(activity.duration))
            if activity.elevationGain > 0 {
                parts.append("\(Formatters.elevation(activity.elevationGain)) \(Formatters.elevationUnit) climb")
            }
            if activity.averageHeartRate > 0 {
                parts.append("\(Int(activity.averageHeartRate.rounded())) bpm average")
            }
            lines.append("Recent session — " + parts.joined(separator: ", "))
        }
        return lines
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                composer
            }
            .background(Theme.canvas)
            .navigationTitle("Trekka")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if chat.hasConversation {
                        Button("Clear") { chat.clear() }
                            .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .task { chat.refreshAvailability() }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if case let .unavailable(reason) = chat.availability {
                        unavailableCard(reason)
                    } else if !chat.hasConversation {
                        opener
                    }

                    ForEach(chat.messages) { message in
                        bubble(message)
                            .id(message.id)
                    }

                    if chat.isThinking {
                        thinkingBubble
                            .id("thinking")
                    }

                    disclaimer
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.count) { _, _ in
                guard let last = chat.messages.last else { return }
                withAnimation(.snappy(duration: 0.3)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: chat.isThinking) { _, thinking in
                guard thinking else { return }
                withAnimation(.snappy(duration: 0.3)) {
                    proxy.scrollTo("thinking", anchor: .bottom)
                }
            }
        }
    }

    private var opener: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Ask me about your training, your recovery or what you have been eating. I answer from what this app has actually recorded — nothing else, and nothing invented.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(TrekkaChatService.suggestions, id: \.self) { suggestion in
                    Button {
                        submit(suggestion)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Text(suggestion)
                                .font(.system(.subheadline, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(Theme.surface, in: .rect(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            if facts.isEmpty {
                Text("There is nothing recorded yet, so there is not much I can tell you. Record a workout or connect Apple Health and come back.")
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var greeting: String {
        profile.firstName.isEmpty ? "Ask Trekka" : "Hello, \(profile.firstName)"
    }

    private func bubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.speaker == .athlete { Spacer(minLength: 40) }

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.speaker == .athlete ? Theme.canvas : Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(background(for: message), in: .rect(cornerRadius: 16))
                .overlay {
                    if message.isDeclined {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Theme.highlight.opacity(0.4), lineWidth: 1)
                    }
                }

            if message.speaker == .trekka { Spacer(minLength: 40) }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func background(for message: ChatMessage) -> Color {
        switch message.speaker {
        case .athlete: Theme.accent
        case .trekka: message.isDeclined ? Theme.highlight.opacity(0.12) : Theme.surface
        }
    }

    private var thinkingBubble: some View {
        HStack(spacing: 8) {
            ProgressView().tint(Theme.accent)
            Text("Thinking…")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
            Spacer(minLength: 40)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
    }

    private func unavailableCard(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Trekka can't talk here", systemImage: "sparkles.slash")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(reason)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Text("The conversation runs on your iPhone itself, which is why nothing you ask leaves the device — and why it needs a phone that can run Apple Intelligence.")
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var disclaimer: some View {
        Text("Answers come from your own recorded data, on this device. Trekka is not a doctor and gives no medical advice.")
            .font(.caption2)
            .foregroundStyle(Theme.textPrimary.opacity(0.35))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask Trekka…", text: $draft, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...4)
                .focused($isTyping)
                .submitLabel(.send)
                .onSubmit { submit(draft) }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Theme.surface, in: .capsule)
                .overlay { Capsule().strokeBorder(Theme.border, lineWidth: 1) }

            Button {
                submit(draft)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.canvas)
                    .frame(width: 38, height: 38)
                    .background(canSend ? Theme.accent : Theme.textPrimary.opacity(0.2), in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(.snappy(duration: 0.2), value: canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !chat.isThinking
            && chat.availability.isReady
    }

    private func submit(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !chat.isThinking else { return }
        draft = ""
        isTyping = false
        let context = facts
        let name = profile.firstName
        Task { await chat.ask(question, facts: context, name: name) }
    }
}
