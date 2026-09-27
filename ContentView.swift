import SwiftUI

public enum MainTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case cookies = "Inspect Cookies"
    case whitelist = "Whitelist"
    case logs = "Console"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .cookies: return "circle.grid.3x3.fill"
        case .whitelist: return "shield.lefthalf.filled"
        case .logs: return "terminal.fill"
        }
    }
}

public struct ContentView: View {
    @Environment(SafariClosureWatcher.self) private var watcher
    @Environment(CookieStore.self) private var cookieStore
    @Environment(WhitelistManager.self) private var whitelistManager
    @Environment(CumulativeStatsManager.self) private var stats
    @Environment(AppLogger.self) private var logger
    
    @State private var selectedTab: MainTab = .dashboard
    @State private var activeSummaryResult: CleaningResult?
    @State private var isSummaryFlush: Bool = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Permission Banner (only if not granted)
            if !cookieStore.permissionStatus.isGranted {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full Disk Access Required")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("CookieCleaner needs Full Disk Access in System Settings to read and clean Safari cookies.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    
                    Button("Check Permissions") {
                        _ = cookieStore.checkPermissions()
                        _ = try? cookieStore.loadCookies(whitelist: whitelistManager)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color.yellow.opacity(0.12))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.yellow.opacity(0.3)),
                    alignment: .bottom
                )
            }
            
            // Tab Content
            Group {
                switch selectedTab {
                case .dashboard:
                    CumulativeStatsView(
                        activeSummaryResult: $activeSummaryResult,
                        isSummaryFlush: $isSummaryFlush
                    )
                case .cookies:
                    LiveCookiesView()
                case .whitelist:
                    WhitelistEditorView()
                case .logs:
                    ConsoleView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $selectedTab) {
                    ForEach(MainTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 440)
            }
            
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    _ = try? cookieStore.loadCookies(whitelist: whitelistManager)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh live cookies from Safari")
                
                Button {
                    Task {
                        let result = await cookieStore.cleanCookies(whitelist: whitelistManager)
                        isSummaryFlush = false
                        activeSummaryResult = result
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("Clean")
                    }
                }
                .buttonStyle(.borderedProminent)
                .help("Clean non-whitelisted cookies")
                .disabled(cookieStore.isCleaning)
            }
        }
        .sheet(item: $activeSummaryResult) { result in
            ActionSummarySheet(result: result, isFlush: isSummaryFlush) {
                activeSummaryResult = nil
            }
        }
        .onAppear {
            _ = cookieStore.checkPermissions()
            _ = try? cookieStore.loadCookies(whitelist: whitelistManager)
        }
    }
}
