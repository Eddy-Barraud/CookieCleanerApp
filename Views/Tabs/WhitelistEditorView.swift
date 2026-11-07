import SwiftUI

/// Interactive split-pane editor for configuring per-profile domain whitelists, profile cleaning toggles, and live regex testing.
public struct WhitelistEditorView: View {
    // Shared whitelist manager injected from the SwiftUI environment
    @Environment(WhitelistManager.self) private var whitelistManager
    // Shared cookie store injected from the SwiftUI environment
    @Environment(CookieStore.self) private var cookieStore
    
    // Currently selected Safari profile ID in the dropdown picker
    @State private var selectedProfileId: String = "default"
    // Raw multiline text content bound to the TextEditor
    @State private var editedContent: String = ""
    // Domain string entered into the live regex tester field
    @State private var testDomain: String = ""
    // Current auto-save status indicator state
    @State private var saveStatus: SaveStatus = .saved
    // Debounced background task for auto-saving text edits after 1 second
    @State private var saveTask: Task<Void, Never>?
    // Flag preventing programmatic profile loads from triggering auto-save
    @State private var isInitialLoad: Bool = true
    
    /// Represents the current persistence status of the editor text.
    private enum SaveStatus {
        case saved
        case saving
    }
    
    /// Initializes the WhitelistEditorView.
    public init() {}
    
    /// Returns all discovered Safari profiles, falling back to the Default Profile if none are loaded yet.
    private var availableProfiles: [SafariProfile] {
        // Provide a fallback default profile if discovery hasn't populated yet
        if cookieStore.discoveredProfiles.isEmpty {
            return [SafariProfile(id: "default", name: "Default Profile", cookieURL: CookieStore.primaryCookiesURL)]
        }
        return cookieStore.discoveredProfiles
    }
    
    /// Resolves the SafariProfile struct matching the currently selected profile ID.
    private var currentProfile: SafariProfile? {
        // Match selectedProfileId or fall back to the first available profile
        availableProfiles.first(where: { $0.id == selectedProfileId }) ?? availableProfiles.first
    }
    
    /// Returns whether cookie and cache cleaning is currently enabled for the selected profile.
    private var isCleaningEnabledForSelectedProfile: Bool {
        // Query WhitelistManager for the selected profile's activation state
        whitelistManager.isProfileCleaningEnabled(profileId: selectedProfileId)
    }
    
    /// Evaluates the live test domain against the currently selected profile's regex whitelist.
    private var testResult: Bool? {
        // Trim whitespace from the test input
        let trimmed = testDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Check if the domain matches any rule in the selected profile
        return whitelistManager.isWhitelisted(test: trimmed, profileId: selectedProfileId)
    }
    
    public var body: some View {
        HSplitView {
            // Left pane: Editor
            VStack(alignment: .leading, spacing: 14) {
                // Header bar
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Whitelist Configuration")
                            .font(.headline)
                        Text("Configured per Safari profile • Auto-saves after 1 second")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Saved status badge
                    HStack(spacing: 6) {
                        switch saveStatus {
                        case .saving:
                            ProgressView()
                                .controlSize(.small)
                            Text("Saving...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .saved:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Saved")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    
                    // Profile Selection Dropdown (at the right side of "Saved")
                    Picker("Profile", selection: $selectedProfileId) {
                        ForEach(availableProfiles) { profile in
                            HStack {
                                Text(profile.name)
                            }
                            .tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 140, maxWidth: 190)
                    .onChange(of: selectedProfileId) { _, newId in
                        loadContentForProfile(newId)
                    }
                    
                    // Activate / Deactivate Cleaning Button for this profile
                    Button {
                        let current = whitelistManager.isProfileCleaningEnabled(profileId: selectedProfileId)
                        whitelistManager.setProfileCleaningEnabled(!current, for: selectedProfileId)
                        _ = try? cookieStore.loadCookies(whitelist: whitelistManager)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isCleaningEnabledForSelectedProfile ? "checkmark.shield.fill" : "pause.circle.fill")
                            Text(isCleaningEnabledForSelectedProfile ? "Cleaning Active" : "Cleaning Deactivated")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .tint(isCleaningEnabledForSelectedProfile ? .green : .orange)
                    .controlSize(.small)
                    .help(isCleaningEnabledForSelectedProfile ? "Click to deactivate cookie and data cleaning for this profile" : "Click to activate cookie and data cleaning for this profile")
                }
                
                // Warning Banner if cleaning is deactivated for the selected profile
                if !isCleaningEnabledForSelectedProfile {
                    HStack(spacing: 8) {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Cleaning is **deactivated** for **\(currentProfile?.name ?? "this profile")**. Cookies, app data caches, and local storage in this profile are preserved untouched.")
                            .font(.caption)
                        Spacer()
                        Button("Re-activate") {
                            whitelistManager.setProfileCleaningEnabled(true, for: selectedProfileId)
                            _ = try? cookieStore.loadCookies(whitelist: whitelistManager)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.green)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                }
                
                Text("Enter one regular expression per line for **\(currentProfile?.name ?? "this profile")**. Lines starting with # are comments.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextEditor(text: $editedContent)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .onChange(of: editedContent) { _, newValue in
                        guard !isInitialLoad else { return }
                        scheduleAutoSave(newContent: newValue)
                    }
            }
            .padding(16)
            .frame(minWidth: 420)
            
            // Right pane: Regex Cheatsheet & Live Tester
            VStack(alignment: .leading, spacing: 18) {
                // Live Domain Tester
                VStack(alignment: .leading, spacing: 10) {
                    Label("Live Regex Tester", systemImage: "bolt.shield.fill")
                        .font(.headline)
                    
                    Text("Testing rules for **\(currentProfile?.name ?? "Selected Profile")** in real time:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                        TextField("e.g. github.com", text: $testDomain)
                            .textFieldStyle(.plain)
                        if !testDomain.isEmpty {
                            Button {
                                testDomain = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    
                    if let result = testResult {
                        HStack(spacing: 8) {
                            if !isCleaningEnabledForSelectedProfile {
                                Image(systemName: "pause.circle.fill")
                                    .foregroundStyle(.orange)
                                Text("SKIPPED (Profile cleaning is deactivated)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                            } else {
                                Image(systemName: result ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                    .foregroundStyle(result ? .green : .red)
                                Text(result ? "PROTECTED (Will be preserved)" : "UNMATCHED (Will be deleted on exit)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(result ? .green : .red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                // Cheatsheet & Quick Insert Templates
                VStack(alignment: .leading, spacing: 12) {
                    Label("Regex Guide & Templates", systemImage: "book.fill")
                        .font(.headline)
                    
                    Text("Click any template below to append it to \(currentProfile?.name ?? "this profile") rules:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        templateRow(
                            title: "Domain & All Subdomains",
                            template: "(^|\\.)domain\\.com$",
                            description: "Matches domain.com, www.domain.com, mail.domain.com"
                        )
                        
                        templateRow(
                            title: "Exact Subdomain Only",
                            template: "^auth\\.domain\\.com$",
                            description: "Matches strictly auth.domain.com"
                        )
                        
                        templateRow(
                            title: "Multiple Country TLDs",
                            template: "(^|\\.)amazon\\.(com|fr|de)$",
                            description: "Matches amazon.com, amazon.fr, amazon.de"
                        )
                        
                        templateRow(
                            title: "Single Exact Domain",
                            template: "^example\\.org$",
                            description: "Excludes subdomains, matches only example.org"
                        )
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                Spacer()
            }
            .padding(16)
            .frame(minWidth: 320, maxWidth: 420)
        }
        .onAppear {
            if !availableProfiles.contains(where: { $0.id == selectedProfileId }) {
                selectedProfileId = availableProfiles.first?.id ?? "default"
            }
            loadContentForProfile(selectedProfileId)
        }
    }
    
    /// Loads the stored raw whitelist content for the specified profile ID into the editor without triggering auto-save.
    private func loadContentForProfile(_ profileId: String) {
        // Cancel any pending debounced save task from the previous profile
        saveTask?.cancel()
        saveStatus = .saved
        // Suppress onChange auto-save while setting programmatic text
        isInitialLoad = true
        editedContent = whitelistManager.rawContent(for: profileId)
        #if DEBUG
        // Log profile switch in the whitelist editor
        AppLogger.shared.debug("WhitelistEditorView switched to profile '\(profileId)' (\(editedContent.count) chars)")
        #endif
        // Re-enable user edit observation on the next main queue tick
        DispatchQueue.main.async {
            isInitialLoad = false
        }
    }
    
    /// Schedules a 1-second debounced auto-save for the currently selected profile's whitelist text.
    private func scheduleAutoSave(newContent: String) {
        // Cancel any in-flight save timer before starting a new 1s countdown
        saveTask?.cancel()
        saveStatus = .saving
        // Capture the target profile ID at the time of the edit
        let profileToSave = selectedProfileId
        
        saveTask = Task {
            // Wait 1 second for typing to pause
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            
            #if DEBUG
            // Log debounced auto-save trigger in debug mode
            AppLogger.shared.debug("Auto-saving whitelist edits for profile '\(profileToSave)'")
            #endif
            // Persist updated content for the profile and refresh live cookie statuses
            whitelistManager.updateWhitelist(content: newContent, for: profileToSave)
            _ = try? cookieStore.loadCookies(whitelist: whitelistManager)
            
            // Update UI badge back to Saved on the main actor
            await MainActor.run {
                withAnimation {
                    saveStatus = .saved
                }
            }
        }
    }
    
    /// Builds a reusable row card displaying a regex template with a one-click Insert button.
    @ViewBuilder
    private func templateRow(title: String, template: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Template title header
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                // Button to append template pattern to the active profile's editor
                Button {
                    appendTemplate(template)
                } label: {
                    Label("Insert", systemImage: "plus")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // Monospaced preview of the regex pattern
            Text(template)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.blue)
            
            // Explanation of what the regex matches
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
        )
    }
    
    /// Appends a regex template string on a new line in the active editor buffer.
    private func appendTemplate(_ template: String) {
        // Ensure a newline separator exists if the editor is non-empty
        if !editedContent.hasSuffix("\n") && !editedContent.isEmpty {
            editedContent += "\n"
        }
        // Append the template followed by a newline
        editedContent += "\(template)\n"
    }
}
