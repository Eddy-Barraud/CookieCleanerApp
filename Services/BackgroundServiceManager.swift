import Foundation
import ServiceManagement
import Cocoa
import Observation

public enum HelperServiceState: Equatable, Sendable {
    case active(pid: Int32?)
    case requiresApproval
    case registering
    case stopped
    case notFound
    
    public var displayText: String {
        switch self {
        case .active(let pid):
            if let pid = pid {
                return "Active & Running (PID \(pid))"
            } else {
                return "Active & Running in Background"
            }
        case .requiresApproval:
            return "Approval Required in System Settings"
        case .registering:
            return "Registering Service..."
        case .stopped:
            return "Not Installed / Stopped"
        case .notFound:
            return "Not Installed"
        }
    }
    
    public var isOperational: Bool {
        if case .active = self { return true }
        return false
    }
}

@Observable
@MainActor
public final class BackgroundServiceManager {
    public static let shared = BackgroundServiceManager()
    
    public static let plistName = "com.eddybarraud.CookieCleanerHelper.plist"
    
    public private(set) var state: HelperServiceState = .stopped
    public private(set) var lastHeartbeatDate: Date?
    public private(set) var helperPID: Int32?
    
    @ObservationIgnored
    private var timer: Timer?
    
    private init() {
        refreshStatus()
        startPeriodicCheck()
    }
    
    public func register() {
        let service = SMAppService.agent(plistName: Self.plistName)
        AppLogger.shared.info("Registering background helper service with launchd...")
        do {
            try service.register()
            AppLogger.shared.success("Background helper registered successfully!")
        } catch {
            AppLogger.shared.error("Failed to register background helper: \(error.localizedDescription)")
        }
        refreshStatus()
    }
    
    public func unregister() {
        let service = SMAppService.agent(plistName: Self.plistName)
        AppLogger.shared.info("Unregistering background helper service from launchd...")
        do {
            try service.unregister()
            AppLogger.shared.success("Background helper unregistered successfully.")
        } catch {
            AppLogger.shared.warning("Service unregister: \(error.localizedDescription)")
        }
        
        // Terminate any active background process for the helper
        if let pid = self.helperPID, pid > 0, pid != ProcessInfo.processInfo.processIdentifier {
            kill(pid, SIGTERM)
            AppLogger.shared.debug("Sent SIGTERM to background helper (PID \(pid))")
        }
        
        // Clear state & persisted heartbeat
        UserDefaults.standard.removeObject(forKey: "CookieCleanerHelper.lastHeartbeat")
        UserDefaults.standard.removeObject(forKey: "CookieCleanerHelper.lastPID")
        self.lastHeartbeatDate = nil
        self.helperPID = nil
        self.state = .stopped
        
        refreshStatus()
    }
    
    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func refreshStatus() {
        let service = SMAppService.agent(plistName: Self.plistName)
        let lastHb = UserDefaults.standard.double(forKey: "CookieCleanerHelper.lastHeartbeat")
        let pid = Int32(UserDefaults.standard.integer(forKey: "CookieCleanerHelper.lastPID"))
        
        if lastHb > 0 {
            self.lastHeartbeatDate = Date(timeIntervalSince1970: lastHb)
        }
        self.helperPID = pid > 0 ? pid : nil
        
        let now = Date().timeIntervalSince1970
        let isAlive = (lastHb > 0) && ((now - lastHb) < 30.0)
        
        switch service.status {
        case .enabled:
            if isAlive {
                self.state = .active(pid: self.helperPID)
            } else {
                self.state = .active(pid: nil)
            }
        case .requiresApproval:
            self.state = .requiresApproval
        case .notRegistered:
            self.state = .stopped
        case .notFound:
            // If BTM hasn't indexed the agent yet, treat as stopped so user can register
            self.state = .stopped
        @unknown default:
            self.state = .stopped
        }
    }
    
    private func startPeriodicCheck() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }
    }
}
