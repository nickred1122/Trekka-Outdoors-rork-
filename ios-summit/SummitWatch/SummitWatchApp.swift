import SwiftUI
import WatchKit

/// Brings the phone bridge up the instant the app launches.
///
/// WatchConnectivity launches the watch app in the background to hand over a
/// file, and it will not wait for a view to appear first. Activating from the
/// app delegate means the session always has a delegate by the time a pack is
/// delivered — previously this happened when the first screen appeared, so a
/// map sent to a watch whose app was not open could be dropped on the floor.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchLink.shared.activate()
    }
}

@main
struct SummitWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var settings = WatchScreenSettings()
    @State private var routeStore = WatchRouteStore()
    @State private var engine = WorkoutEngine()
    @State private var glance = WatchGlanceService()
    @State private var dashboard = WatchDashboardStore()
    @State private var breadcrumbs = BreadcrumbStore()
    @State private var mapPacks = WatchMapPackStore()
    @State private var mapDownloader = WatchMapDownloader()

    init() {
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(routeStore)
                .environment(engine)
                .environment(glance)
                .environment(dashboard)
                .environment(breadcrumbs)
                .environment(mapPacks)
                .environment(mapDownloader)
                .tint(WatchTheme.accent)
                .task {
                    WatchLink.shared.configure(
                        settings: settings,
                        routeStore: routeStore,
                        dashboard: dashboard,
                        mapPacks: mapPacks
                    )
                    mapDownloader.configure(packs: mapPacks)
                    engine.prepare(settings: settings)
                    engine.onFinishedWorkout = { activity in
                        dashboard.recordLocalWorkout(activity)
                    }

                    // Breadcrumbs are laid for the whole workout, so the trail
                    // survives a reboot and can be walked back afterwards.
                    engine.onRecordingBegan = { _ in
                        breadcrumbs.beginRecording()
                    }
                    engine.onLocation = { coordinate, elevation in
                        breadcrumbs.record(coordinate: coordinate, elevation: elevation)
                    }
                    engine.onRecordingEnded = { sport, name in
                        breadcrumbs.finishRecording(name: name, sport: sport)
                    }
                    engine.onRecordingDiscarded = {
                        breadcrumbs.cancelRecording()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Pick up anything armed from the watch face while the app
                    // was in the background.
                    if phase == .active { engine.applyFaceRequestIfNeeded() }
                }
        }
    }
}
