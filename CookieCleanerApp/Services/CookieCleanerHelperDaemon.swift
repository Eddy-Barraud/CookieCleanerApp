import Foundation
import Cocoa

@MainActor
public final class CookieCleanerHelperDaemon {
    public static let shared = CookieCleanerHelperDaemon()
    
    private var heartbeatTimer: Timer?
    
    public static func main() {
        AppLogger.shared.info("🤖 CookieCleanerHelper daemon started (PID \(ProcessInfo.processInfo.processIdentifier))")
        
        let daemon = CookieCleanerHelperDaemon.shared
        daemon.start()
        
        // Use RunLoop.main.run() without initializing NSApplication.
        // This prevents the background helper from hijacking the GUI bundle registration in LaunchServices.
        RunLoop.main.run()
    }
    
    public func start() {
        updateHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateHeartbeat()
            }
        }
        
        SafariClosureWatcher.shared.startWatching()
    }
    
    private func updateHeartbeat() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "CookieCleanerHelper.lastHeartbeat")
        UserDefaults.standard.set(ProcessInfo.processInfo.processIdentifier, forKey: "CookieCleanerHelper.lastPID")
    }
}
