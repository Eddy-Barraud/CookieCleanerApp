import Foundation
import Cocoa
import Observation

@Observable
@MainActor
public final class SafariClosureWatcher {
    public static let shared = SafariClosureWatcher()
    
    public static let safariBundleId = "com.apple.Safari"
    
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
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.safariBundleId else {
                return
            }
            
            self.handleSafariTerminated(app: app)
        }
        
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.safariBundleId else {
                return
            }
            
            self.handleSafariLaunched(app: app)
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
        
        guard CumulativeStatsManager.shared.autoCleanEnabled else {
            AppLogger.shared.info("⏸️ Auto-clean on Safari Quit is disabled in settings. Skipping cleanup.")
            return
        }
        
        #if DEBUG
        AppLogger.shared.debug("⏳ Waiting 1.0 second to allow Safari's SQLite/binary write buffers to flush to disk...")
        #endif
        
        Task {
            // Wait 1.0 second for Safari to finish closing file descriptors
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            AppLogger.shared.info("⚡️ Background Task Triggered: Cleaning Safari cookies & cache...")
            let result = await CookieStore.shared.cleanCookies(whitelist: WhitelistManager.shared)
            
            if result.isSuccess {
                AppLogger.shared.success("✨ Auto-clean on Safari quit succeeded! (\(result.cookiesDeleted) deleted, \(result.formattedBytesFreed) freed)")
            } else {
                AppLogger.shared.error("💥 Auto-clean on Safari quit failed: \(result.errorMessage ?? "Unknown error")")
            }
        }
    }
}
