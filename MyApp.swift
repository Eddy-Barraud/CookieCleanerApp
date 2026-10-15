import SwiftUI
import AppIntents

struct MyApp: App {
    @State private var watcher = SafariClosureWatcher.shared
    @State private var cookieStore = CookieStore.shared
    @State private var whitelistManager = WhitelistManager.shared
    @State private var stats = CumulativeStatsManager.shared
    @State private var logger = AppLogger.shared
    @State private var backgroundService = BackgroundServiceManager.shared
    
    init() {
        #if DEBUG
        AppLogger.shared.debug("🔧 CookieCleanerApp starting in DEBUG mode with verbose logging enabled.")
        #endif
        SafariClosureWatcher.shared.startWatching()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(watcher)
                .environment(cookieStore)
                .environment(whitelistManager)
                .environment(stats)
                .environment(logger)
                .environment(backgroundService)
                .frame(minWidth: 880, minHeight: 580)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
