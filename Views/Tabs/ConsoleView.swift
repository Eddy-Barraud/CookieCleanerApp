import SwiftUI

public struct ConsoleView: View {
    @Environment(AppLogger.self) private var logger
    
    @State private var selectedLevel: LevelFilter = .all
    @State private var autoScroll: Bool = true
    @State private var searchQuery: String = ""
    
    public enum LevelFilter: String, CaseIterable, Identifiable {
        case all = "All Levels"
        case info = "Info"
        case debug = "Debug"
        case success = "Success"
        case warning = "Warnings"
        case error = "Errors"
        
        public var id: String { rawValue }
    }
    
    private var filteredEntries: [LogEntry] {
        logger.entries.filter { entry in
            switch selectedLevel {
            case .all: break
            case .info: if entry.level != .info { return false }
            case .debug: if entry.level != .debug { return false }
            case .success: if entry.level != .success { return false }
            case .warning: if entry.level != .warning { return false }
            case .error: if entry.level != .error { return false }
            }
            
            if !searchQuery.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(searchQuery)
            }
            return true
        }
    }
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 12) {
            // Control bar
            HStack(spacing: 12) {
                Picker("Level", selection: $selectedLevel) {
                    ForEach(LevelFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .frame(width: 140)
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter logs...", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)
                
                Spacer()
                
                Button {
                    let logText = filteredEntries.map { "[\($0.formattedTimestamp)] [\($0.level.displayName)] \($0.message)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                } label: {
                    Label("Copy Logs", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button {
                    logger.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Console text area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(filteredEntries) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.formattedTimestamp)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                
                                Text(entry.level.displayName)
                                    .font(.system(.caption2, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundStyle(colorForLevel(entry.level))
                                    .frame(width: 65, alignment: .leading)
                                
                                Text(entry.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Color(NSColor.textColor))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .onChange(of: logger.entries.count) {
                    if autoScroll, let last = filteredEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .debug: return .gray
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
}
