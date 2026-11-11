import Foundation
import Cocoa

/// Headless background daemon and CLI helper service for CookieCleaner.
///
/// This daemon runs as an `SMAppService` launchd agent or on-demand CLI command.
/// It performs the exact same cleaning operations as clicking the "Clean" button in the GUI:
/// it cleans cookies not in the whitelist of each profile and also cleans the data cache storage.
@MainActor
public final class CookieCleanerHelperDaemon {
    /// Shared singleton instance of the helper daemon.
    public static let shared = CookieCleanerHelperDaemon()
    
    /// Periodic timer that broadcasts live heartbeats to UserDefaults for GUI monitoring.
    private var heartbeatTimer: Timer?
    
    /// Private initializer enforcing singleton pattern.
    private init() {}
    
    /// Main entry point for the headless background daemon process.
    public static func main() {
        // Inspect command line arguments for one-shot cleaning or help flags
        let args = CommandLine.arguments
        
        // Check for help flag
        if args.contains("--help") || args.contains("-h") {
            printUsage()
            exit(EXIT_SUCCESS)
        }
        
        // Check for explicit clean action command
        if args.contains("--clean") || args.contains("-c") || args.contains("clean") {
            performCleanAndExit()
            return
        }
        
        // Log daemon startup message with current process ID
        AppLogger.shared.info("🤖 CookieCleanerHelper daemon started (PID \(ProcessInfo.processInfo.processIdentifier))")
        #if DEBUG
        AppLogger.shared.debug("Background helper daemon initializing with arguments: \(args)")
        #endif
        
        // Start background monitoring and heartbeat loop
        let daemon = CookieCleanerHelperDaemon.shared
        daemon.start()
        
        // Use RunLoop.main.run() without initializing NSApplication.
        // This prevents the background helper from hijacking the GUI bundle registration in LaunchServices.
        RunLoop.main.run()
    }
    
    /// Starts background services including heartbeat publishing, Safari lifecycle observation,
    /// and an initial cleanup if Safari is already closed on daemon launch.
    public func start() {
        // Publish immediate heartbeat with current PID
        updateHeartbeat()
        
        // Schedule periodic heartbeat updates every 10 seconds
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateHeartbeat()
            }
        }
        
        // Begin listening for Safari launch and termination notifications
        SafariClosureWatcher.shared.startWatching()
        
        // If Safari is already closed when the daemon starts, perform an initial clean
        Task { @MainActor in
            await SafariClosureWatcher.shared.cleanIfSafariClosed()
        }
    }
    
    /// Performs the exact same cleaning operation as clicking the "Clean" button in the GUI.
    ///
    /// It cleans non-whitelisted cookies across all active profiles and removes non-whitelisted data cache storage.
    /// - Returns: A `CleaningResult` detailing cookies kept/deleted, files removed, and bytes freed.
    @discardableResult
    public func performClean() async -> CleaningResult {
        #if DEBUG
        AppLogger.shared.debug("Helper daemon executing unified clean operation...")
        #endif
        
        // Synchronize cross-process preferences so daemon sees latest user whitelists and toggles
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        CumulativeStatsManager.shared.reloadFromDefaults()
        WhitelistManager.shared.reloadFromDefaults()
        
        // Delegate to the shared CookieStore cleaning implementation
        let result = await CookieStore.shared.cleanCookies(whitelist: WhitelistManager.shared)
        return result
    }
    
    /// One-shot CLI entry point: executes the full clean routine, outputs summary to stdout, and exits.
    public static func performCleanAndExit() {
        // Dispatch cleaning task asynchronously on the main actor
        Task { @MainActor in
            print("CookieCleaner: Starting cookie and data cache storage cleanup...")
            
            // Check full disk access permissions first
            let permStatus = CookieStore.shared.checkPermissions()
            if !permStatus.isGranted {
                print("Error: Full Disk Access is required. Status: \(permStatus.displayText)")
                exit(EXIT_FAILURE)
            }
            
            // Execute the exact same clean action as clicking the GUI button
            let result = await CookieCleanerHelperDaemon.shared.performClean()
            
            if result.isSuccess {
                print("CookieCleaner: Cleaning completed successfully in \(String(format: "%.2f", result.duration))s")
                print("  Cookies kept: \(result.cookiesKept)")
                print("  Cookies deleted: \(result.cookiesDeleted)")
                print("  Cache/Storage files removed: \(result.profileCachesRemoved)")
                print("  Disk space freed: \(result.formattedBytesFreed)")
                exit(EXIT_SUCCESS)
            } else {
                print("CookieCleaner: Cleaning failed: \(result.errorMessage ?? "Unknown error")")
                exit(EXIT_FAILURE)
            }
        }
        
        // Keep runloop alive until the asynchronous Task calls exit()
        RunLoop.main.run()
    }
    
    /// Updates the heartbeat timestamp and process ID in standard UserDefaults and flushes to disk.
    private func updateHeartbeat() {
        let defaults = UserDefaults.standard
        defaults.set(Date().timeIntervalSince1970, forKey: "CookieCleanerHelper.lastHeartbeat")
        defaults.set(ProcessInfo.processInfo.processIdentifier, forKey: "CookieCleanerHelper.lastPID")
        defaults.synchronize()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
    }
    
    /// Prints command line usage information to stdout.
    public nonisolated static func printUsage() {
        print("""
        CookieCleanerHelper — Safari Cookie & Data Cache Storage Cleaner

        Usage:
          CookieCleanerHelper [options]

        Options:
          --clean, -c        Clean non-whitelisted cookies and data cache storage immediately, then exit.
          --helper           Run as continuous background daemon via launchd (default when launched as helper).
          --help, -h         Display this help message.
        """)
    }
}
