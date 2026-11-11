import Foundation
import Cocoa
import Observation

@Observable
@MainActor
public final class SafariClosureWatcher {
    public static let shared = SafariClosureWatcher()
    
    nonisolated public static let safariBundleId = "com.apple.Safari"
    
    public private(set) var isWatching: Bool = false
    public private(set) var isSafariRunning: Bool = false
    public private(set) var lastTerminationDate: Date?
    
    @ObservationIgnored
    private var terminateObserver: NSObjectProtocol?
    @ObservationIgnored
    private var launchObserver: NSObjectProtocol?
    
    private init() {
        checkCurrentSafariState()
    }
    
    public func checkCurrentSafariState() {
        let runningSafaris = NSRunningApplication.runningApplications(withBundleIdentifier: Self.safariBundleId)
        let running = !runningSafaris.isEmpty
        self.isSafariRunning = running
        #if DEBUG
        if running {
            let pids = runningSafaris.map { "\($0.processIdentifier)" }.joined(separator: ", ")
            AppLogger.shared.debug("Safari is currently RUNNING (PID(s): \(pids))")
        } else {
            AppLogger.shared.debug("Safari is currently NOT running.")
        }
        #endif
    }
    
    public func startWatching() {
        guard !isWatching else { return }
        
        checkCurrentSafariState()
        
        terminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.safariBundleId else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handleSafariTerminated(app: app)
            }
        }
        
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.safariBundleId else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handleSafariLaunched(app: app)
            }
        }
        
        isWatching = true
        AppLogger.shared.info("👀 Safari background watcher started (Listening for termination events)")
    }
    
    public func stopWatching() {
        if let obs = terminateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            terminateObserver = nil
        }
        if let obs = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            launchObserver = nil
        }
        isWatching = false
        AppLogger.shared.info("Safari background watcher stopped.")
    }
    
    private func handleSafariLaunched(app: NSRunningApplication) {
        self.isSafariRunning = true
        AppLogger.shared.info("🚀 Safari launched (PID: \(app.processIdentifier))")
    }
    
    private func handleSafariTerminated(app: NSRunningApplication) {
        self.isSafariRunning = false
        self.lastTerminationDate = Date()
        
        AppLogger.shared.info("🛑 Safari closed by user (PID: \(app.processIdentifier))")
        
        CumulativeStatsManager.shared.reloadFromDefaults()
        WhitelistManager.shared.reloadFromDefaults()
        
        guard CumulativeStatsManager.shared.autoCleanEnabled else {
            AppLogger.shared.info("⏸️ Auto-clean on Safari Quit is disabled in settings. Skipping cleanup.")
            return
        }
        
        let now = Date().timeIntervalSince1970
        let lastCleanKey = "CookieCleaner.lastAutoCleanTimestamp"
        let lastClean = UserDefaults.standard.double(forKey: lastCleanKey)
        if now - lastClean < 4.0 {
            #if DEBUG
            AppLogger.shared.debug("Auto-clean already performed by helper/watcher within last 4s. Skipping duplicate.")
            #endif
            return
        }
        // Persist debounce timestamp and synchronize across processes immediately
        UserDefaults.standard.set(now, forKey: lastCleanKey)
        UserDefaults.standard.synchronize()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        
        #if DEBUG
        AppLogger.shared.debug("⏳ Waiting 1.0 second to allow Safari's SQLite/binary write buffers to flush to disk...")
        #endif
        
        Task { @MainActor in
            // Wait 1.0 second for Safari to finish closing file descriptors
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            AppLogger.shared.info("⚡ Background Task Triggered: Cleaning Safari cookies & cache...")
            let result = await CookieCleanerHelperDaemon.shared.performClean()
            
            if result.isSuccess {
                AppLogger.shared.success("✨ Auto-clean on Safari quit succeeded! (\(result.cookiesDeleted) deleted, \(result.formattedBytesFreed) freed)")
            } else {
                AppLogger.shared.error("💥 Auto-clean on Safari quit failed: \(result.errorMessage ?? "Unknown error")")
            }
        }
    }
    
    /// Triggers the full cleaning routine if Safari is not currently running and debounce permits.
    ///
    /// - Returns: The CleaningResult if a cleanup was executed, or nil if skipped.
    @discardableResult
    public func cleanIfSafariClosed() async -> CleaningResult? {
        // Refresh running application status
        checkCurrentSafariState()
        // If Safari is running, skip immediate cleanup to avoid writing over active buffers
        guard !isSafariRunning else {
            #if DEBUG
            AppLogger.shared.debug("Safari is currently running, skipping immediate background cleanup.")
            #endif
            return nil
        }
        
        // Synchronize and reload preferences from disk
        CumulativeStatsManager.shared.reloadFromDefaults()
        WhitelistManager.shared.reloadFromDefaults()
        
        // Ensure autoCleanEnabled is active
        guard CumulativeStatsManager.shared.autoCleanEnabled else {
            return nil
        }
        
        // Check debounce interval to avoid duplicate runs across GUI and daemon
        let now = Date().timeIntervalSince1970
        let lastCleanKey = "CookieCleaner.lastAutoCleanTimestamp"
        let lastClean = UserDefaults.standard.double(forKey: lastCleanKey)
        if now - lastClean < 4.0 {
            #if DEBUG
            AppLogger.shared.debug("Cleanup already performed within last 4s. Skipping duplicate.")
            #endif
            return nil
        }
        
        // Persist timestamp and flush cross-process
        UserDefaults.standard.set(now, forKey: lastCleanKey)
        UserDefaults.standard.synchronize()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        
        AppLogger.shared.info("⚡ Background Task: Safari is closed, executing cleanup routine...")
        let result = await CookieCleanerHelperDaemon.shared.performClean()
        if result.isSuccess {
            AppLogger.shared.success("✨ Background cleanup succeeded! (\(result.cookiesDeleted) deleted, \(result.formattedBytesFreed) freed)")
        } else {
            AppLogger.shared.error("💥 Background cleanup failed: \(result.errorMessage ?? "Unknown error")")
        }
        return result
    }
}
