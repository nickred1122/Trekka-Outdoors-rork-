import SwiftUI

/// Where one optional connection has got to, in the three states a first-run
/// card can honestly be in: it can be switched on, it is on, or it cannot be.
private enum ConnectionState: Equatable {
    case available(String)
    case working
    case connected(String)
    case unavailable(String)
}

/// The steps of first run, in order.
private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case consent
    case name
    case units
    case connections
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

/// First run: what the app is, what the athlete is agreeing to, how it should
/// measure, whether it may read Health, and what a day's eating should aim at.
///
/// Every step is skippable except the agreements — a person can decline to name
/// themselves or set a goal, but they cannot use the app without accepting the
/// terms, the privacy statement and the health notice.
struct OnboardingView: View {
    @Environment(HealthService.self) private var health
    @Environment(UnitSettings.self) private var units
    @Environment(WatchLayoutStore.self) private var watchLayout
    @Environment(NutritionStore.self) private var nutrition
    @Environment(GoalSettings.self) private var goals
    @Environment(ProfileSettings.self) private var profile
    @Environment(ConsentSettings.self) private var consent
    @Environment(StravaService.self) private var strava

    var onFinish: () -> Void

    /// Location is a shared service rather than an environment value, because a
    /// map opened anywhere in the app uses the same one.
    @State private var location = MapLocationService.shared
    @State private var isConnectingStrava = false

    @State private var step: OnboardingStep = .welcome
    @State private var energyTarget: Double = NutritionGoals.default.energyKilocalories
    @State private var split: MacroSplit = .balanced
    @State private var setsFuelGoal = false
    @State private var name = ""
    @State private var acceptedDocuments: Set<LegalDocumentKind> = []
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
        case .consent: consentStep
        case .name: nameStep
        case .units: unitsStep
        case .connections: connectionsStep
        case .goals: goalsStep
        case .fuel: fuelStep
        case .ready: readyStep
        }
    }

    /// The one step with no way past it. Nothing is recorded until the button is
    /// pressed, so ticking boxes and then quitting leaves no agreement behind.
    private var consentStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)

            heading(
                "Before you start",
                detail: "Three things to read and agree to. They are short, they are in plain English, and they stay in Settings if you want them later."
            )

            ConsentChecklist(accepted: $acceptedDocuments) { feedback += 1 }

            footnote("Trekka is a fitness app, not a medical device. It gives you an overview of your health and training — never a diagnosis or medical advice.")
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

    /// Everything Trekka can be plugged into, each one asked for separately.
    ///
    /// Deliberately one screen with three independent choices rather than three
    /// screens in a row. Somebody who wants Health but not Strava, or a map
    /// without either, can say so here and move on — and nothing is requested by
    /// simply arriving on the step, so no system sheet appears unbidden.
    ///
    /// Only permissions Trekka actually uses are listed. There is no notification
    /// row because the app never sends one, and asking for a permission you have
    /// no use for is how an app teaches people to refuse everything.
    private var connectionsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "app.connected.to.app.below.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.accent)

            heading(
                "What should Trekka connect to?",
                detail: "Each of these is optional and each is separate. Turn any of them on now, or later in Settings — Trekka records and navigates without a single one."
            )

            VStack(spacing: 10) {
                healthConnectionRow
                locationConnectionRow
                if StravaService.isConfigured { stravaConnectionRow }
            }

            footnote("Your health data, routes and food diary stay on this phone. The only thing that ever leaves is a workout you send to Strava yourself.")
        }
    }

    private var healthConnectionRow: some View {
        connectionCard(
            symbol: "heart.text.square.fill",
            tint: Theme.danger,
            title: "Apple Health",
            detail: "Reads steps, heart rate, sleep and past workouts to fill your dashboard. Writes back what you record here.",
            state: healthConnectionState
        ) {
            Task { await health.requestAuthorization() }
        }
    }

    private var locationConnectionRow: some View {
        connectionCard(
            symbol: "location.fill",
            tint: Theme.accent,
            title: "Location",
            detail: "Needed to draw the map around you and to record where a workout went. Only ever while you are using Trekka.",
            state: locationConnectionState
        ) {
            location.requestAccess()
        }
    }

    private var stravaConnectionRow: some View {
        connectionCard(
            symbol: "figure.run.circle.fill",
            tint: Theme.accent,
            title: "Strava",
            detail: "Send finished workouts to Strava. Sign-in happens on Strava's own page — Trekka never sees your password.",
            state: stravaConnectionState
        ) {
            Task {
                isConnectingStrava = true
                await strava.connect()
                isConnectingStrava = false
            }
        }
    }

    private var healthConnectionState: ConnectionState {
        switch health.authorization {
        case .authorized: .connected("Connected")
        case .requesting: .working
        case .denied: .unavailable("Declined · change in the Settings app")
        case .unavailable: .unavailable("Not available on this device")
        case .unknown: .available("Connect")
        }
    }

    private var locationConnectionState: ConnectionState {
        if location.isAuthorized { return .connected("Allowed") }
        if location.isDenied { return .unavailable("Declined · change in the Settings app") }
        return .available("Allow")
    }

    private var stravaConnectionState: ConnectionState {
        if isConnectingStrava { return .working }
        switch strava.connection {
        case let .connected(athlete): return .connected(athlete ?? "Connected")
        case .connecting: return .working
        case .notConfigured: return .unavailable("Not available in this build")
        case .failed, .signedOut: return .available("Sign in")
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
        case .consent: "Agree & continue"
        case .name: name.isEmpty ? "Continue" : "Nice to meet you"
        case .units: "Continue"
        case .connections: "Continue"
        case .goals: goals.isEmpty ? "Continue" : "Save \(goals.metricsWithGoals.count) goal\(goals.metricsWithGoals.count == 1 ? "" : "s")"
        case .fuel: setsFuelGoal ? "Save target" : "Continue"
        case .ready: "Start using Trekka"
        }
    }

    /// Every step continues freely except the agreements, which need all three.
    private var isPrimaryEnabled: Bool {
        guard step == .consent else { return true }
        return acceptedDocuments.count == LegalDocument.all.count
    }

    private var secondaryTitle: String? {
        switch step {
        // No skip is offered on the agreements, and no "maybe later" either.
        // A step that cannot be passed should not appear to have a way around it.
        case .consent: nil
        case .name where !name.isEmpty: "Skip"
        case .connections where health.authorization != .authorized: "Skip for now"
        case .goals where !goals.isEmpty: "No goals for now"
        case .fuel where setsFuelGoal: "Skip for now"
        default: nil
        }
    }

    private func advance() {
        feedback += 1
        switch step {
        case .consent:
            guard isPrimaryEnabled else { return }
            consent.acceptAll()
            step = .name
        case .name:
            profile.setName(name)
            isNamingSelf = false
            step = .units
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
        case .connections: step = .goals
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

    /// One optional connection: what it is for, and a single control that either
    /// turns it on or explains why it cannot be turned on here.
    ///
    /// A connection already granted becomes a plain statement rather than a
    /// disabled button — there is nothing left to do, and a greyed-out control
    /// invites people to keep tapping it.
    @ViewBuilder
    private func connectionCard(
        symbol: String,
        tint: Color,
        title: String,
        detail: String,
        state: ConnectionState,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: .rect(cornerRadius: 10))

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
            }

            switch state {
            case let .available(label):
                Button {
                    feedback += 1
                    action()
                } label: {
                    Text(label)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Theme.canvas)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(tint, in: .rect(cornerRadius: 11))
                }
                .buttonStyle(.plain)

            case .working:
                HStack(spacing: 8) {
                    ProgressView().tint(tint)
                    Text("Waiting for your answer…")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case let .connected(label):
                Label(label, systemImage: "checkmark.circle.fill")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Theme.positive)
                    .frame(maxWidth: .infinity, alignment: .leading)

            case let .unavailable(label):
                Label(label, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(13)
        .background(Theme.surface, in: .rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .animation(.snappy(duration: 0.25), value: state)
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
