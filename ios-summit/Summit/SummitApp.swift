//
//  SummitApp.swift
//  Summit
//

import SwiftUI

@main
struct SummitApp: App {
    init() {
        configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    /// Keeps system chrome on the app canvas instead of default grays. The
    /// colors are trait-dynamic, so they follow the appearance setting.
    private func configureAppearance() {
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = Theme.canvasUIColor
        navigationAppearance.shadowColor = Theme.borderUIColor
        navigationAppearance.titleTextAttributes = [.foregroundColor: Theme.textPrimaryUIColor]
        navigationAppearance.largeTitleTextAttributes = [.foregroundColor: Theme.textPrimaryUIColor]
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
    }
}
