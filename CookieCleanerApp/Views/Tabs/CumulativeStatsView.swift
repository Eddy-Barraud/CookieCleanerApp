import SwiftUI

public struct CumulativeStatsView: View {
    @Environment(SafariClosureWatcher.self) private var watcher
    @Environment(CookieStore.self) private var cookieStore
    @Environment(WhitelistManager.self) private var whitelistManager
    @Environment(CumulativeStatsManager.self) private var stats
    @Environment(AppLogger.self) private var logger
    
    @Binding var activeSummaryResult: CleaningResult?
    @Binding var isSummaryFlush: Bool
    
    @State private var showingFlushAlert: Bool = false
    @State private var showingResetAlert: Bool = false
    
    public init(
        activeSummaryResult: Binding<CleaningResult?>,
        isSummaryFlush: Binding<Bool>
    ) {
        self._activeSummaryResult = activeSummaryResult
        self._isSummaryFlush = isSummaryFlush
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Metric cards grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    StatCardView(
                        title: "Times Cleaned",
                        value: "\(stats.timesCleaned)",
                        subtitle: "Automated & manual",
                        icon: "arrow.triangle.2.circlepath",
                        color: .blue
                    )
                    
                    StatCardView(
                        title: "Cookies Deleted",
                        value: "\(stats.totalCookiesDeleted)",
                        subtitle: "Lifetime total",
                        icon: "trash.fill",
                        color: .red
                    )
                    
                    StatCardView(
                        title: "Data Recovered",
                        value: stats.formattedTotalBytesFreed,
                        subtitle: "Disk space freed",
                        icon: "internaldrive.fill",
                        color: .green
                    )
                    
                    StatCardView(
                        title: "Last Cleaned",
                        value: stats.lastCleanedDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never",
                        subtitle: stats.lastCleanedDate != nil ? "Last operation" : "Awaiting first run",
                        icon: "clock.fill",
                        color: .purple
                    )
                }
                
                // Safari Auto-clean Watcher Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "safari.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Safari Background Automation")
                                .font(.headline)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(watcher.isSafariRunning ? Color.green : Color.secondary.opacity(0.6))
                                    .frame(width: 8, height: 8)
                                Text(watcher.isSafariRunning ? "Safari is currently running" : "Safari is currently closed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        @Bindable var bindableStats = stats
                        Toggle("Auto-clean on Safari Quit", isOn: $bindableStats.autoCleanEnabled)
                            .toggleStyle(.switch)
                    }
                    
                    Text("When enabled, CookieCleaner silently filters non-whitelisted cookies and caches whenever Safari quits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                // Detected Profiles Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Detected Safari Profiles", systemImage: "person.crop.rectangle.stack")
                            .font(.headline)
                        Spacer()
                        Text("\(cookieStore.discoveredProfiles.count) profile(s) found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if cookieStore.discoveredProfiles.isEmpty {
                        Text("No profile databases found yet. Make sure Full Disk Access is enabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(cookieStore.discoveredProfiles) { profile in
                                let count = cookieStore.loadedCookies.filter { $0.profileName == profile.name }.count
                                HStack(spacing: 12) {
                                    Image(systemName: profile.id == "default" ? "star.fill" : "person.fill")
                                        .foregroundStyle(profile.id == "default" ? .yellow : .blue)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.name)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text(profile.cookieURL.lastPathComponent)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(count)")
                                            .font(.headline)
                                            .monospacedDigit()
                                        Text("cookies")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(NSColor.textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                // Action Buttons Bar
                HStack(spacing: 14) {
                    Button {
                        Task {
                            let result = await cookieStore.cleanCookies(whitelist: whitelistManager)
                            isSummaryFlush = false
                            activeSummaryResult = result
                        }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Clean Non-Whitelisted Now")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(cookieStore.isCleaning)
                    
                    Button {
                        showingFlushAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "flame.fill")
                            Text("Flush All Cookies")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.large)
                    .disabled(cookieStore.isCleaning)
                    
                    Button {
                        _ = try? cookieStore.loadCookies(whitelist: whitelistManager)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("Refresh live cookies from Safari")
                }
                
                // Reset stats footer
                HStack {
                    Spacer()
                    Button("Reset Statistics...", role: .destructive) {
                        showingResetAlert = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .confirmationDialog(
            "Flush All Cookies?",
            isPresented: $showingFlushAlert,
            titleVisibility: .visible
        ) {
            Button("Flush Every Cookie", role: .destructive) {
                Task {
                    let result = await cookieStore.flushAllCookies()
                    isSummaryFlush = true
                    activeSummaryResult = result
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will purge all cookies across all profiles unconditionally. You will be logged out of all active websites.")
        }
        .confirmationDialog(
            "Reset All Statistics?",
            isPresented: $showingResetAlert,
            titleVisibility: .visible
        ) {
            Button("Reset Counter to Zero", role: .destructive) {
                stats.resetStats()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to reset all historical cleaning statistics to zero? This action cannot be undone.")
        }
    }
}
