import Foundation
import Observation

@Observable
@MainActor
public final class CumulativeStatsManager {
    public static let shared = CumulativeStatsManager()
    
    private let timesCleanedKey = "CookieCleaner.timesCleaned"
    private let totalCookiesDeletedKey = "CookieCleaner.totalCookiesDeleted"
    private let totalBytesFreedKey = "CookieCleaner.totalBytesFreed"
    private let lastCleanedDateKey = "CookieCleaner.lastCleanedDate"
    private let autoCleanEnabledKey = "CookieCleaner.autoCleanEnabled"
    
    public private(set) var timesCleaned: Int = 0
    public private(set) var totalCookiesDeleted: Int = 0
    public private(set) var totalBytesFreed: Int64 = 0
    public private(set) var lastCleanedDate: Date?
    public var autoCleanEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCleanEnabled, forKey: autoCleanEnabledKey)
        }
    }
    
    public var formattedTotalBytesFreed: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytesFreed)
    }
    
    private init() {
        let defaults = UserDefaults.standard
        self.timesCleaned = defaults.integer(forKey: timesCleanedKey)
        self.totalCookiesDeleted = defaults.integer(forKey: totalCookiesDeletedKey)
        self.totalBytesFreed = defaults.object(forKey: totalBytesFreedKey) as? Int64 ?? 0
        self.lastCleanedDate = defaults.object(forKey: lastCleanedDateKey) as? Date
        
        if defaults.object(forKey: autoCleanEnabledKey) == nil {
            self.autoCleanEnabled = true
        } else {
            self.autoCleanEnabled = defaults.bool(forKey: autoCleanEnabledKey)
        }
    }
    
    public func recordCleaning(result: CleaningResult) {
        guard result.isSuccess else { return }
        
        timesCleaned += 1
        totalCookiesDeleted += result.cookiesDeleted
        totalBytesFreed += result.bytesFreed
        lastCleanedDate = result.timestamp
        
        let defaults = UserDefaults.standard
        defaults.set(timesCleaned, forKey: timesCleanedKey)
        defaults.set(totalCookiesDeleted, forKey: totalCookiesDeletedKey)
        defaults.set(totalBytesFreed, forKey: totalBytesFreedKey)
        defaults.set(lastCleanedDate, forKey: lastCleanedDateKey)
    }
    
    public func resetStats() {
        timesCleaned = 0
        totalCookiesDeleted = 0
        totalBytesFreed = 0
        lastCleanedDate = nil
        
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: timesCleanedKey)
        defaults.removeObject(forKey: totalCookiesDeletedKey)
        defaults.removeObject(forKey: totalBytesFreedKey)
        defaults.removeObject(forKey: lastCleanedDateKey)
        
        AppLogger.shared.info("Historical cleaning statistics have been reset.")
    }
}
