import Foundation

/// The three agreements Trekka asks for before it will open.
nonisolated enum LegalDocumentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case privacy
    case terms
    case health

    var id: String { rawValue }
}

/// One headed passage of an agreement. Documents are held as sections rather
/// than one slab of text so they can be read on a phone without becoming a wall.
nonisolated struct LegalSection: Identifiable, Hashable, Sendable {
    let heading: String
    let body: String

    var id: String { heading }
}

/// An agreement, its plain-language summary, and the line the athlete ticks.
///
/// Each document carries its own version. If one is revised later, only that
/// one is asked for again — nobody should have to re-accept a privacy statement
/// because a sentence changed in the terms.
nonisolated struct LegalDocument: Identifiable, Hashable, Sendable {
    let kind: LegalDocumentKind
    let title: String
    let symbol: String
    /// The one line shown beside the tick box.
    let acceptance: String
    /// What the document says, in a sentence, for somebody who will not read it.
    let summary: String
    let version: Int
    let sections: [LegalSection]

    var id: LegalDocumentKind { kind }

    static var all: [LegalDocument] { [privacy, terms, health] }

    static func document(_ kind: LegalDocumentKind) -> LegalDocument {
        all.first { $0.kind == kind } ?? privacy
    }
}

/// Names, dates and contact details that appear inside every document, kept in
/// one place so they are never edited in five and missed in a sixth.
nonisolated enum LegalAgreements {
    static let appName = "Trekka"
    static let provider = "Trekka"
    static let contactEmail = "support@trekka.app"
    static let effectiveDate = "8 September 2026"

    /// True once every current document has been accepted.
    static var kinds: [LegalDocumentKind] { LegalDocumentKind.allCases }
}

// MARK: - Privacy

extension LegalDocument {
    static let privacy = LegalDocument(
        kind: .privacy,
        title: "Privacy Statement",
        symbol: "lock.shield.fill",
        acceptance: "I have read and agree to the Privacy Statement",
        summary: "Your training data stays on your devices. No account, no analytics, nothing sold.",
        version: 1,
        sections: [
            LegalSection(
                heading: "The short version",
                body: """
                Trekka has no accounts and no server of its own. Your routes, workouts, food log, goals and settings are stored on your iPhone and Apple Watch. We cannot see them, because they are never sent to us.

                We do not sell, rent or share your personal data. There is no advertising in Trekka, and no third-party analytics or tracking software of any kind is built into it.
                """
            ),
            LegalSection(
                heading: "What is stored on your device",
                body: """
                Planned routes and waypoints; recorded activities, including GPS tracks, heart rate and elevation; food and nutrition entries; daily goals; your first name, if you choose to give one; downloaded offline map data; and your app settings.

                All of this lives in Trekka's own storage on your device and is removed when you delete the app.
                """
            ),
            LegalSection(
                heading: "Apple Health",
                body: """
                If you connect Apple Health, Trekka reads the data types you approve — such as steps, heart rate, heart rate variability, sleep, energy and workouts — to fill the dashboard and its insights. It writes back the workouts you record in Trekka and the food you log in Fuel.

                Health data is read on your device and used only to show you your own information inside the app and on your watch. It is never transmitted to us, never used for advertising or marketing, never sold, and never shared with any third party. You can change or revoke this access at any time in the Health app, under Sharing.
                """
            ),
            LegalSection(
                heading: "What leaves your device, and when",
                body: """
                Trekka contacts outside services only to fetch things it cannot hold locally, and it sends the minimum needed to fetch them. No account identifier, name, or Health data is attached to any of these requests.

                • Map and terrain tiles — when you view or download a map, the map area you are looking at is requested from OpenFreeMap and from a public terrain elevation archive hosted on Amazon S3.
                • Food lookups — when you scan a barcode or search for a food, that barcode or search term is sent to Open Food Facts.
                • Route and terrain helpers — when you plan a route, the coordinates of that route may be sent to fetch elevation, place names and weather for it.

                These providers receive the request and your device's IP address, as any web request involves, and their own privacy practices apply to what they do with it. Trekka sends them nothing that identifies you.
                """
            ),
            LegalSection(
                heading: "Backups you make yourself",
                body: """
                If you turn on iCloud backup, your Trekka archive is written to your own iCloud storage under your own Apple ID. It goes to Apple, not to us, and we have no access to it. If you export a backup file instead, it goes wherever you choose to put it, and looking after it becomes your responsibility.
                """
            ),
            LegalSection(
                heading: "On-device intelligence",
                body: """
                On supported iPhones, Trekka can use Apple Intelligence to write a short summary of your training week. This model runs entirely on your device. Your training data is not sent to Apple, to us, or to any other server for this feature, and the feature is simply absent on devices that do not support it.
                """
            ),
            LegalSection(
                heading: "Children",
                body: """
                Trekka is not directed at children and we do not knowingly collect personal data from anyone under 13. Because the app has no accounts and collects nothing centrally, there is nothing for us to hold.
                """
            ),
            LegalSection(
                heading: "Your control",
                body: """
                You can delete any route, activity or food entry from inside the app. You can revoke Apple Health access at any time in the Health app. Deleting Trekka removes everything it stored on that device; an iCloud backup you made is deleted from your own iCloud storage, by you, in the same way as any other iCloud data.
                """
            ),
            LegalSection(
                heading: "Changes and contact",
                body: """
                If this statement changes in a way that affects you, you will be asked to read and accept it again before continuing to use the app.

                Questions about privacy can be sent to \(LegalAgreements.contactEmail).

                Effective \(LegalAgreements.effectiveDate).
                """
            ),
        ]
    )
}

// MARK: - Terms

extension LegalDocument {
    static let terms = LegalDocument(
        kind: .terms,
        title: "Terms of Service",
        symbol: "doc.text.fill",
        acceptance: "I have read and agree to the Terms of Service",
        summary: "The rules for using the app, and the limits of what it promises.",
        version: 1,
        sections: [
            LegalSection(
                heading: "This agreement",
                body: """
                These terms are between you and \(LegalAgreements.provider), the provider of the \(LegalAgreements.appName) app. By accepting them and using \(LegalAgreements.appName), you agree to them. If you do not agree, do not use the app.
                """
            ),
            LegalSection(
                heading: "Your licence",
                body: """
                You are granted a personal, non-exclusive, non-transferable licence to use \(LegalAgreements.appName) on devices you own or control, for your own non-commercial use, in line with the Apple Media Services Terms that govern anything downloaded from the App Store.

                You may not copy, resell or redistribute the app, reverse-engineer it except where law permits, or remove attribution from map data it displays.
                """
            ),
            LegalSection(
                heading: "Your data is yours, and it is your responsibility",
                body: """
                \(LegalAgreements.appName) has no accounts and keeps no copy of your data. Everything you record lives on your device. If you lose the device, reset it, or delete the app without a backup, that data is gone and we cannot recover it. Backup and restore are provided in the app for exactly this reason, and using them is up to you.
                """
            ),
            LegalSection(
                heading: "Safety, and your own judgement",
                body: """
                \(LegalAgreements.appName) is a training and navigation aid. It is not a substitute for proper preparation, a paper map and compass, local knowledge, or your own judgement in the outdoors.

                You are solely responsible for your safety and for the safety of anyone with you. You decide whether conditions, terrain, weather, daylight and your own fitness make an outing sensible. Never rely on a phone or watch as your only means of navigation or of calling for help.
                """
            ),
            LegalSection(
                heading: "Maps, distances and other approximations",
                body: """
                Maps, trails, elevation figures, place names, weather and GPS positions come from open data sources and from device sensors. They can be out of date, incomplete or simply wrong. A path shown on the map may not exist on the ground, may be impassable, or may cross private or dangerous terrain. Elevation and distance are estimates.

                Nutrition information in Fuel largely comes from Open Food Facts, a public database that anyone may edit, or from a label you photographed. It may be inaccurate. If you have an allergy or a medical dietary requirement, read the physical packaging — never the app.
                """
            ),
            LegalSection(
                heading: "Third-party data",
                body: """
                Map data is © OpenStreetMap contributors, available under the Open Database Licence, rendered via OpenFreeMap. Terrain elevation comes from public datasets including those published by the USGS and other national agencies. Food data comes from Open Food Facts, also under the Open Database Licence. These sources keep their own licences and attribution requirements, which the app displays where their data is shown.
                """
            ),
            LegalSection(
                heading: "Acceptable use",
                body: """
                Do not use \(LegalAgreements.appName) for anything unlawful, do not use it to trespass or to access places you have no right to be, and do not attempt to disrupt or misuse the third-party services it relies on, including by automated bulk downloading of map or food data.
                """
            ),
            LegalSection(
                heading: "Availability and changes",
                body: """
                Features may change, and features that depend on outside services may stop working if those services change or shut down. Offline maps depend on data downloaded in advance while you had a connection. We do not promise uninterrupted availability of anything that needs the network.
                """
            ),
            LegalSection(
                heading: "No warranty",
                body: """
                To the fullest extent permitted by law, \(LegalAgreements.appName) is provided "as is" and "as available", without warranty of any kind, express or implied, including any implied warranty of merchantability, fitness for a particular purpose, accuracy, or non-infringement.
                """
            ),
            LegalSection(
                heading: "Limitation of liability",
                body: """
                To the fullest extent permitted by law, \(LegalAgreements.provider) is not liable for any indirect, incidental, special or consequential loss, nor for loss of data, arising from your use of the app.

                Nothing in these terms excludes or limits liability for death or personal injury caused by negligence, for fraud, or for anything else that cannot lawfully be excluded. Some jurisdictions do not allow certain exclusions, so parts of this section may not apply to you, and you may have rights under local consumer law that these terms cannot affect.
                """
            ),
            LegalSection(
                heading: "Ending this agreement",
                body: """
                You may end this agreement at any time by deleting the app. We may end it if you materially breach these terms. Sections that by their nature should survive — disclaimers, limitation of liability, and the health notice — continue to apply afterwards.
                """
            ),
            LegalSection(
                heading: "Changes to these terms",
                body: """
                If these terms change materially, you will be asked to read and accept the new version before continuing to use the app.
                """
            ),
            LegalSection(
                heading: "Contact",
                body: """
                Questions about these terms can be sent to \(LegalAgreements.contactEmail).

                Effective \(LegalAgreements.effectiveDate).
                """
            ),
        ]
    )
}

// MARK: - Health notice

extension LegalDocument {
    static let health = LegalDocument(
        kind: .health,
        title: "Health & Safety Notice",
        symbol: "heart.text.square.fill",
        acceptance: "I understand \(LegalAgreements.appName) is not a medical device",
        summary: "An overview of your health and training — not a diagnosis, and not medical advice.",
        version: 1,
        sections: [
            LegalSection(
                heading: "Not a medical device",
                body: """
                \(LegalAgreements.appName) is a fitness and wellbeing app. It is not a medical device. It is not cleared, approved or registered by the FDA, the MHRA, the EMA or any other regulator, and it is not intended to diagnose, treat, cure, monitor or prevent any disease or medical condition.

                Nothing in the app should be read as a medical finding. If a number here worries you, that is a reason to speak to a doctor — not a reason to conclude anything.
                """
            ),
            LegalSection(
                heading: "What the numbers actually are",
                body: """
                Everything \(LegalAgreements.appName) shows is an overview built from consumer sensors and from data Apple Health has collected. Heart rate, heart rate variability, sleep stages, calories, steps, distance and elevation are all estimates produced by hardware that was never designed for clinical use, and they can be affected by fit, movement, temperature, skin, tattoos and signal quality.

                Readiness, training load, zone minutes and the written insights are Trekka's own interpretations of that data. They are informed guesses meant to help you notice patterns over time. They are not measurements of your health, and they carry no clinical meaning whatsoever.
                """
            ),
            LegalSection(
                heading: "Not medical advice",
                body: """
                Nothing in \(LegalAgreements.appName) — including any goal, target, suggestion, insight or summary — is medical, nutritional or professional advice. Never disregard advice from a qualified professional, or delay seeking it, because of something you read in this app.

                Daily goals and fuel targets are numbers you chose. \(LegalAgreements.appName) deliberately does not calculate a calorie or activity target for you, because it does not know enough about you to do so safely.
                """
            ),
            LegalSection(
                heading: "Talk to a doctor first",
                body: """
                Speak to a qualified healthcare professional before starting or significantly changing an exercise or nutrition programme — and particularly if you have or suspect a heart condition, high blood pressure, diabetes, an eating disorder, a respiratory condition, an injury, are pregnant or recently postpartum, are taking medication that affects heart rate, or are otherwise unsure that new activity is safe for you.
                """
            ),
            LegalSection(
                heading: "In an emergency",
                body: """
                \(LegalAgreements.appName) does not detect medical events. It cannot detect a heart attack, an arrhythmia, a fall or any other emergency, and it will never call for help on your behalf.

                If you feel chest pain, unusual breathlessness, faintness, confusion or any other symptom that concerns you, stop what you are doing and contact emergency services immediately. Do not wait to see what the app says.
                """
            ),
            LegalSection(
                heading: "Food and nutrition figures",
                body: """
                Nutrition data comes from a public, community-edited database or from a label you scanned, and it may be wrong. Do not rely on it for allergies, intolerances or any medically prescribed diet. Always check the physical packaging.
                """
            ),
            LegalSection(
                heading: "You accept this risk",
                body: """
                Any physical activity carries risk of injury, and the outdoors adds risks of its own. By using \(LegalAgreements.appName) you accept that you exercise at your own risk, and that decisions about your training, your nutrition and your safety remain yours.

                Effective \(LegalAgreements.effectiveDate).
                """
            ),
        ]
    )
}
