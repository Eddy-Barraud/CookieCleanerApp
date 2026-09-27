import Foundation
import os
import SwiftUI
import Observation

public enum LogLevel: String, CaseIterable, Sendable {
    case info = "INFO"
    case debug = "DEBUG"
    case warning = "WARN"
    case error = "ERROR"
    case success = "SUCCESS"
    
    public var displayName: String {
        return rawValue
    }
    
    public var emoji: String {
        switch self {
        case .info: return "ℹ️"
        case .debug: return "🔍"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .success: return "✅"
        }
    }
    
    public var color: Color {
        switch self {
        case .info: return .blue
        case .debug: return .secondary
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}

public struct LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    
    public var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    public var fullFormattedString: String {
        "[\(formattedTimestamp)] [\(level.displayName)] \(message)"
    }
}

@Observable
@MainActor
public final class AppLogger {
    public static let shared = AppLogger()
    
    private let osLogger = Logger(subsystem: "com.eddybarraud.CookieCleanerApp", category: "BackgroundWatcher")
    
    public private(set) var entries: [LogEntry] = []
    private let maxEntries = 500
    
    private init() {}
    
    public func log(level: LogLevel, message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        
        switch level {
        case .info:
            osLogger.info("\(message, privacy: .public)")
        case .debug:
            osLogger.debug("\(message, privacy: .public)")
        case .warning:
            osLogger.warning("\(message, privacy: .public)")
        case .error:
            osLogger.error("\(message, privacy: .public)")
        case .success:
            osLogger.notice("\(message, privacy: .public)")
        }
        
        print("[\(entry.formattedTimestamp)] [\(level.rawValue)] \(message)")
    }
    
    public func info(_ msg: String) { log(level: .info, message: msg) }
    public func debug(_ msg: String) { log(level: .debug, message: msg) }
    public func warning(_ msg: String) { log(level: .warning, message: msg) }
    public func error(_ msg: String) { log(level: .error, message: msg) }
    public func success(_ msg: String) { log(level: .success, message: msg) }
    
    public func clear() {
        entries.removeAll()
    }
}
