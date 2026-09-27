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
            return "Stopped / Not Running"
        case .notFound:
            return "Helper Plist Missing"
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
        ensureRegistered()
    }
    
    public func ensureRegistered() {
        let service = SMAppService.agent(plistName: Self.plistName)
        if service.status == .enabled {
            AppLogger.shared.debug("Background helper service is already registered and enabled.")
            refreshStatus()
            return
        }
        if service.status == .requiresApproval {
            AppLogger.shared.warning("Background helper requires user approval in macOS System Settings.")
            refreshStatus()
            return
        }
        
        AppLogger.shared.info("Registering background helper service with launchd...")
        do {
            try service.register()
            AppLogger.shared.success("Successfully registered background helper service!")
        } catch {
            AppLogger.shared.error("Failed to register background helper: \(error.localizedDescription)")
        }
        refreshStatus()
    }
    
    public func register() {
        let service = SMAppService.agent(plistName: Self.plistName)
        do {
            try service.register()
            AppLogger.shared.success("Background helper registered.")
        } catch {
            AppLogger.shared.error("Failed to register: \(error.localizedDescription)")
        }
        refreshStatus()
    }
    
    public func unregister() {
        let service = SMAppService.agent(plistName: Self.plistName)
        do {
            try service.unregister()
            AppLogger.shared.info("Background helper unregistered.")
        } catch {
            AppLogger.shared.error("Failed to unregister: \(error.localizedDescription)")
        }
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
