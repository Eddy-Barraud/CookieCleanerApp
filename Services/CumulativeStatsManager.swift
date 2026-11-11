import Foundation
import Observation

/// Manages lifetime cleaning statistics and global cleanup configuration toggles in UserDefaults.
@Observable
@MainActor
public final class CumulativeStatsManager {
    /// Shared singleton instance used across GUI views and background daemon processes.
    public static let shared = CumulativeStatsManager()
    
    // UserDefaults key for total number of completed clean operations
    private let timesCleanedKey = "CookieCleaner.timesCleaned"
    // UserDefaults key for cumulative count of deleted cookies
    private let totalCookiesDeletedKey = "CookieCleaner.totalCookiesDeleted"
    // UserDefaults key for cumulative disk bytes freed
    private let totalBytesFreedKey = "CookieCleaner.totalBytesFreed"
    // UserDefaults key for the timestamp of the most recent cleanup
    private let lastCleanedDateKey = "CookieCleaner.lastCleanedDate"
    // UserDefaults key for toggling automatic cleanup when Safari terminates
    private let autoCleanEnabledKey = "CookieCleaner.autoCleanEnabled"
    // UserDefaults key for toggling combined Safari profile cache & storage cleaning
    private let clearProfileCachesEnabledKey = "CookieCleaner.clearProfileCachesEnabled"
    
    // Total number of cleanup runs executed
    public private(set) var timesCleaned: Int = 0
    // Total number of cookies purged across all runs
    public private(set) var totalCookiesDeleted: Int = 0
    // Total bytes of disk space reclaimed across all runs
    public private(set) var totalBytesFreed: Int64 = 0
    // Optional date of the last successful cleanup operation
    public private(set) var lastCleanedDate: Date?
    /// Controls whether the app or daemon automatically cleans when Safari quits.
    public var autoCleanEnabled: Bool = true {
        didSet {
            // Persist updated auto-clean toggle to UserDefaults and flush cross-process
            UserDefaults.standard.set(autoCleanEnabled, forKey: autoCleanEnabledKey)
            UserDefaults.standard.synchronize()
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        }
    }
    /// Controls whether profile app data caches and web storage are cleared alongside cookies.
    public var clearProfileCachesEnabled: Bool = true {
        didSet {
            // Persist updated profile cache toggle to UserDefaults and flush cross-process
            UserDefaults.standard.set(clearProfileCachesEnabled, forKey: clearProfileCachesEnabledKey)
            UserDefaults.standard.synchronize()
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        }
    }
    
    /// Human-readable file size string representing total bytes freed.
    public var formattedTotalBytesFreed: String {
        // Configure byte count formatter for standard file units
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytesFreed)
    }
    
    /// Initializes the manager and loads persisted statistics and toggles from UserDefaults.
    private init() {
        // Synchronize and populate stored values from disk
        reloadFromDefaults()
    }
    
    /// Synchronizes CFPreferences and reloads all statistics and settings from UserDefaults.
    public func reloadFromDefaults() {
        // Ensure cross-process updates between GUI and helper daemon are flushed from disk
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        let defaults = UserDefaults.standard
        // Load cumulative counters
        self.timesCleaned = defaults.integer(forKey: timesCleanedKey)
        self.totalCookiesDeleted = defaults.integer(forKey: totalCookiesDeletedKey)
        self.totalBytesFreed = defaults.object(forKey: totalBytesFreedKey) as? Int64 ?? 0
        self.lastCleanedDate = defaults.object(forKey: lastCleanedDateKey) as? Date
        
        // Load autoCleanEnabled toggle (defaults to true if never set)
        if defaults.object(forKey: autoCleanEnabledKey) == nil {
            self.autoCleanEnabled = true
        } else {
            self.autoCleanEnabled = defaults.bool(forKey: autoCleanEnabledKey)
        }
        
        // Load clearProfileCachesEnabled toggle (defaults to true if never set)
        if defaults.object(forKey: clearProfileCachesEnabledKey) == nil {
            self.clearProfileCachesEnabled = true
        } else {
            self.clearProfileCachesEnabled = defaults.bool(forKey: clearProfileCachesEnabledKey)
        }
    }
    
    /// Records the metrics of a completed cleaning run and persists updated totals to UserDefaults.
    public func recordCleaning(result: CleaningResult) {
        // Ignore failed cleanup attempts
        guard result.isSuccess else { return }
        
        // Reload latest values from disk first to avoid overwriting daemon or GUI updates
        reloadFromDefaults()
        
        // Increment lifetime counters with the new result metrics
        timesCleaned += 1
        totalCookiesDeleted += result.cookiesDeleted
        totalBytesFreed += result.bytesFreed
        lastCleanedDate = result.timestamp
        
        // Save updated counters to UserDefaults and flush to disk
        let defaults = UserDefaults.standard
        defaults.set(timesCleaned, forKey: timesCleanedKey)
        defaults.set(totalCookiesDeleted, forKey: totalCookiesDeletedKey)
        defaults.set(totalBytesFreed, forKey: totalBytesFreedKey)
        defaults.set(lastCleanedDate, forKey: lastCleanedDateKey)
        defaults.synchronize()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        
        #if DEBUG
        // Log updated cumulative totals in debug builds
        AppLogger.shared.debug("Recorded cleaning stats: runs=\(timesCleaned), cookiesDeleted=\(totalCookiesDeleted), bytesFreed=\(totalBytesFreed)")
        #endif
    }
    
    /// Resets all lifetime cleaning statistics back to zero.
    public func resetStats() {
        // Clear in-memory counters
        timesCleaned = 0
        totalCookiesDeleted = 0
        totalBytesFreed = 0
        lastCleanedDate = nil
        
        // Remove persisted keys from UserDefaults
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: timesCleanedKey)
        defaults.removeObject(forKey: totalCookiesDeletedKey)
        defaults.removeObject(forKey: totalBytesFreedKey)
        defaults.removeObject(forKey: lastCleanedDateKey)
        
        AppLogger.shared.info("Historical cleaning statistics have been reset.")
    }
}
