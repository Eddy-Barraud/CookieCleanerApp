import SwiftUI

public struct CumulativeStatsView: View {
    @Environment(SafariClosureWatcher.self) private var watcher
    @Environment(CookieStore.self) private var cookieStore
    @Environment(WhitelistManager.self) private var whitelistManager
    @Environment(CumulativeStatsManager.self) private var stats
    @Environment(AppLogger.self) private var logger
    @Environment(BackgroundServiceManager.self) private var backgroundService
    
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
                metricCardsView
                safariAutomationCard
                backgroundServiceCard
                detectedProfilesCard
                actionButtonsBar
                resetStatsButton
            }
            .padding(20)
        }
        .confirmationDialog(
            "Flush All Cookies?",
            isPresented: $showingFlushAlert,
            titleVisibility: .visible
        ) {
            Button("Flush Everything", role: .destructive) {
                Task {
                    let result = await cookieStore.flushAllCookies()
                    isSummaryFlush = true
                    activeSummaryResult = result
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all cookies across all \(cookieStore.discoveredProfiles.count) profile(s), including whitelisted ones. Safari caches will also be wiped.")
        }
        .confirmationDialog(
            "Reset All Statistics?",
            isPresented: $showingResetAlert,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                stats.resetStats()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will reset your lifetime counters (times cleaned, cookies deleted, and bytes freed) back to zero.")
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private var metricCardsView: some View {
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
    }
    
    @ViewBuilder
    private var safariAutomationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "safari.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safari Automation Setting")
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
            
            Text("When enabled, non-whitelisted cookies are automatically cleared from disk whenever Safari quits.")
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
    }
    
    @ViewBuilder
    private var backgroundServiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Image(systemName: "gearshape.2.fill")
                    .font(.title3)
                    .foregroundStyle(backgroundService.state.isOperational ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("macOS Background Helper (launchd)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Circle()
                            .fill(backgroundService.state.isOperational ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                    }
                    
                    Text(backgroundService.state.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                serviceActionButton
            }
            
            HStack {
                Text("Registered with launchd. Runs 24/7 in the background so cookies are cleaned on Safari quit even when this app is closed.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if let hb = backgroundService.lastHeartbeatDate {
                    Text("Heartbeat: \(hb.formatted(date: .omitted, time: .standard))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
    }
    
    @ViewBuilder
    private var serviceActionButton: some View {
        switch backgroundService.state {
        case .active:
            Label("Functional", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.green.opacity(0.12)))
        case .requiresApproval:
            Button {
                backgroundService.openSystemSettings()
            } label: {
                Label("Allow in Settings", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
        case .stopped, .registering, .notFound:
            Button {
                backgroundService.register()
            } label: {
                Label("Register Helper", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    @ViewBuilder
    private var detectedProfilesCard: some View {
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
    }
    
    @ViewBuilder
    private var actionButtonsBar: some View {
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
        }
    }
    
    @ViewBuilder
    private var resetStatsButton: some View {
        Button {
            showingResetAlert = true
        } label: {
            Label("Reset Lifetime Statistics", systemImage: "arrow.counterclockwise")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}
