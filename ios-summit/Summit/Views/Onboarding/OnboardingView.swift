import SwiftUI

/// The steps of first run, in order.
private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case name
    case units
    case health
    case goals
    case fuel
    case ready

    var id: Int { rawValue }
}

/// Whether first run has been completed, and whether it should ever be shown.
///
/// Kept out of the view so the "this phone already has data" judgement is made
/// once, at launch, rather than every time the view rebuilds.
@Observable
final class OnboardingState {
    private static let key = "onboarding.completed.v2"

    private(set) var isComplete: Bool

    init() {
        isComplete = UserDefaults.standard.bool(forKey: Self.key)
    }

    func complete() {
        guard !isComplete else { return }
        isComplete = true
        UserDefaults.standard.set(true, forKey: Self.key)
    }

    /// Marks first run as done without showing it, for a phone that plainly has
    /// history already. Somebody who has been using Trekka for months should not
    /// be asked to choose their units as though they had just arrived — and
    /// worse, be offered defaults that would overwrite what they had set.
    func skipForExistingUser(hasData: Bool) {
        guard !isComplete, hasData else { return }
        complete()
    }
}

/// First run: what the app is, how it should measure, whether it may read
/// Health, and what a day's eating should aim at.
///
/// Every step is skippable and nothing here is asked twice — each choice is
/// also in Settings afterwards.
struct OnboardingView: View {
    @Environment(HealthService.self) private var health
    @Environment(UnitSettings.self) private var units
    @Environment(WatchLayoutStore.self) private var watchLayout
    @Environment(NutritionStore.self) private var nutrition
    @Environment(GoalSettings.self) private var goals
    @Environment(ProfileSettings.self) private var profile

    var onFinish: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var energyTarget: Double = NutritionGoals.default.energyKilocalories
    @State private var split: MacroSplit = .balanced
    @State private var setsFuelGoal = false
    @State private var name = ""
    @FocusState private var isNamingSelf: Bool
    @State private var feedback = 0

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                progressBar
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                ScrollView {
                    VStack(spacing: 0) {
                        stepContent
                            .padding(.horizontal, 24)
                            .padding(.top, 28)
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }
        }
        .sensoryFeedback(.selection, trigger: feedback)
        .animation(.snappy(duration: 0.3), value: step)
        .interactiveDismissDisabled()
    }

    // MARK: - Backdrop

    /// A low orange glow off the top corner, so first run does not open on a
    /// flat black rectangle.
    private var backdrop: some View {
        ZStack {
            Theme.canvas
            RadialGradient(
                colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0)],
                center: .init(x: 0.15, y: 0.05),
                startRadius: 10,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }

    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(OnboardingStep.allCases) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Theme.accent : Theme.textPrimary.opacity(0.15))
                    .frame(height: 3)
            }
        }
        .animation(.snappy(duration: 0.3), value: step)
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeStep
        case .name: nameStep
        case .units: unitsStep
        case .health: healthStep
        case .goals: goalsStep
        case .fuel: fuelStep
        case .ready: readyStep
        }
    }

    /// One field, and it is optional. The name is only ever used to address the
    /// athlete inside their own app — there is no account behind it.
    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.accent)

            heading("What should we call you?", detail: "Used to greet you on the dashboard and nowhere else. It stays on this phone — there is no account and nothing is sent anywhere.")

            TextField("Your name", text: $name)
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isNamingSelf)
                .onSubmit { advance() }
                .padding(14)
                .panel()

            if !name.isEmpty {
                Text(ProfileSettings.preview(greetingFor: name))
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: name.isEmpty)
    }

    /// Goals are offered, not assumed. Each one starts at a round number the
    /// athlete can move later; nothing here is derived from their body or their
    /// history, because Trekka does not know enough to set a target for anyone.
    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "target")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.accent)

            heading("Set a daily goal?", detail: "Pick any that matter to you. Each shows as a progress bar on its dashboard tile and on your watch, measured against what Apple Health and your workouts actually record.")

            VStack(spacing: 10) {
                ForEach(DashboardMetric.goalCapable) { metric in
                    choiceCard(
                        title: metric.title,
                        detail: metric.goalSummary(goals.target(for: metric) ?? metric.defaultGoalTarget),
                        symbol: metric.symbol,
                        isSelected: goals.hasGoal(for: metric)
                    ) {
                        goals.toggle(metric)
                        feedback += 1
                    }
                }
            }

            footnote("You can change the numbers, or turn any of these off, in Settings → Daily goals.")
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.accent)

            heading("Welcome to Trekka", detail: "Plan routes, record what you do, and carry a real topographic map on your wrist — with no signal and no phone in your pocket.")

            VStack(spacing: 10) {
                pointRow("map.fill", "Offline topo maps", "Download the ground along a route and navigate with no signal.")
                pointRow("figure.hiking", "80 activity types", "From trail runs and ski tours to yoga, pickleball and mowing the lawn.")
                pointRow("fork.knife", "Fuel", "Scan a barcode or a nutrition label and track what you eat.")
            }
        }
    }

    private var unitsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            heading("How should we measure?", detail: "Distance, speed, height and weight. You can change this any time, and weight and elevation can each go their own way later in Settings.")

            VStack(spacing: 10) {
                ForEach(UnitSystem.allCases) { system in
                    choiceCard(
                        title: system.title,
                        detail: system.subtitle,
                        symbol: system.symbol,
                        isSelected: units.system == system
                    ) {
                        units.set(system)
                        watchLayout.unitSystem = system
                        watchLayout.massSystem = units.massUnits
                        watchLayout.elevationSystem = units.elevationUnits
                        watchLayout.pushSilently()
                        feedback += 1
                    }
                }
            }

            footnote("Nothing you record is stored in these units — they only change how it reads, so switching later never alters a workout.")
        }
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Theme.danger)

            heading("Connect Apple Health", detail: "Trekka reads your steps, heart rate, sleep and workouts to fill the dashboard, and writes the workouts you record here back into Health.")

            VStack(spacing: 10) {
                pointRow("arrow.down.circle.fill", "Reads", "Steps, heart rate, sleep, energy and past workouts.")
                pointRow("arrow.up.circle.fill", "Writes", "Workouts you record in Trekka, and food you log in Fuel.")
                pointRow("lock.fill", "Stays yours", "Health data never leaves your phone through Trekka. There is no account and no server.")
            }

            switch health.authorization {
            case .authorized:
                statusRow(symbol: "checkmark.circle.fill", tint: Theme.positive, text: "Connected to Apple Health")
            case .denied:
                statusRow(
                    symbol: "exclamationmark.circle.fill",
                    tint: Theme.textPrimary.opacity(0.5),
                    text: "Not connected. You can turn this on later in Settings — the rest of Trekka works without it."
                )
            case .unavailable:
                statusRow(
                    symbol: "info.circle.fill",
                    tint: Theme.textPrimary.opacity(0.5),
                    text: "Apple Health is not available on this device."
                )
            case .requesting:
                statusRow(symbol: "hourglass", tint: Theme.accent, text: "Waiting for your answer…")
            case .unknown:
                EmptyView()
            }
        }
    }

    private var fuelStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "fork.knife")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)

            heading("Set a daily fuel target?", detail: "Only if you want one. Trekka will not guess a calorie target from your height and weight — a confidently wrong number is worse than none.")

            Toggle(isOn: $setsFuelGoal.animation(.snappy(duration: 0.25))) {
                Text("Track what I eat")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)
            .padding(14)
            .panel()

            if setsFuelGoal {
                VStack(spacing: 14) {
                    VStack(spacing: 6) {
                        Text("\(Int(energyTarget.rounded()))")
                            .font(.metric(38))
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        Text("kcal a day")
                            .metricLabelStyle()

                        Slider(value: $energyTarget, in: 1_200...5_000, step: 50)
                            .tint(Theme.accent)
                    }
                    .padding(14)
                    .panel()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Macro split")
                            .metricLabelStyle()
                        ForEach(MacroSplit.allCases.filter { $0 != .custom }) { option in
                            choiceCard(
                                title: option.title,
                                detail: option.detail,
                                symbol: "chart.pie.fill",
                                isSelected: split == option
                            ) {
                                split = option
                                feedback += 1
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            footnote("You can change this, or turn on adding your training energy on top, in Fuel → Goals.")
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Theme.positive)

            heading("You're set", detail: "Everything here is in Settings if you want to change it.")

            VStack(spacing: 10) {
                pointRow("point.topleft.down.curvedto.point.bottomright.up.fill", "Plan a route", "Routes tab — draw a line, then download its map for offline use.")
                pointRow("applewatch", "Set up your watch", "Settings → Watch screens & power, to choose what each screen shows.")
                pointRow("icloud.fill", "Back up", "Settings → Backup & restore, to keep a copy in your own iCloud.")
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                advance()
            } label: {
                Text(primaryTitle)
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(Theme.canvas)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.accent, in: .rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            if let secondary = secondaryTitle {
                Button(secondary) {
                    skip()
                }
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .frame(height: 26)
            } else {
                Color.clear.frame(height: 26)
            }
        }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome: "Get started"
        case .name: name.isEmpty ? "Continue" : "Nice to meet you"
        case .units: "Continue"
        case .health: health.authorization == .authorized ? "Continue" : "Connect Apple Health"
        case .goals: goals.isEmpty ? "Continue" : "Save \(goals.metricsWithGoals.count) goal\(goals.metricsWithGoals.count == 1 ? "" : "s")"
        case .fuel: setsFuelGoal ? "Save target" : "Continue"
        case .ready: "Start using Trekka"
        }
    }

    private var secondaryTitle: String? {
        switch step {
        case .name where !name.isEmpty: "Skip"
        case .health where health.authorization != .authorized: "Not now"
        case .goals where !goals.isEmpty: "No goals for now"
        case .fuel where setsFuelGoal: "Skip for now"
        default: nil
        }
    }

    private func advance() {
        feedback += 1
        switch step {
        case .name:
            profile.setName(name)
            isNamingSelf = false
            step = .units
        case .health where health.authorization != .authorized
            && health.authorization != .unavailable
            && health.authorization != .denied:
            // The system sheet is the whole point of this step, so the step is
            // held until the answer comes back rather than moving on behind it.
            Task {
                await health.requestAuthorization()
                step = .goals
            }
        case .fuel:
            if setsFuelGoal {
                var goals = NutritionGoals.default
                goals.energyKilocalories = energyTarget.rounded()
                goals.apply(split)
                nutrition.setGoals(goals)
            }
            step = .ready
        case .ready:
            onFinish()
        default:
            if let next = OnboardingStep(rawValue: step.rawValue + 1) {
                step = next
            }
        }
    }

    private func skip() {
        feedback += 1
        switch step {
        case .name:
            name = ""
            isNamingSelf = false
            step = .units
        case .health: step = .goals
        case .goals:
            // Turning them all off is the honest reading of "no goals for now" —
            // anything toggled while browsing should not be kept by accident.
            goals.clearAll()
            step = .fuel
        case .fuel:
            setsFuelGoal = false
            step = .ready
        default:
            if let next = OnboardingStep(rawValue: step.rawValue + 1) {
                step = next
            }
        }
    }

    // MARK: - Building blocks

    private func heading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pointRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.12), in: .rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .panel()
    }

    private func choiceCard(
        title: String,
        detail: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary.opacity(0.5))
                    .frame(width: 34, height: 34)
                    .background(
                        (isSelected ? Theme.accent : Theme.textPrimary).opacity(0.12),
                        in: .rect(cornerRadius: 10)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textPrimary.opacity(0.2))
            }
            .padding(13)
            .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.6) : Theme.border, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func statusRow(symbol: String, tint: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1), in: .rect(cornerRadius: 12))
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.textPrimary.opacity(0.42))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
