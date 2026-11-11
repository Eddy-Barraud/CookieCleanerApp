import Foundation
import Observation

/// Manages per-profile regex domain whitelists and profile cleaning activation states.
@Observable
@MainActor
public final class WhitelistManager {
    /// Shared singleton instance used by both the GUI app and background helper daemon.
    public static let shared = WhitelistManager()
    
    // UserDefaults key for legacy single-profile whitelist storage
    private let legacyDatastoreKey = "CookieCleaner.whitelistContent"
    // UserDefaults key mapping profile IDs to raw newline-separated whitelist strings
    private let perProfileDatastoreKey = "CookieCleaner.whitelistByProfile"
    // UserDefaults key mapping profile IDs to boolean cleaning enabled flags
    private let profileCleaningEnabledKey = "CookieCleaner.profileCleaningEnabled"
    
    // Raw multiline whitelist text indexed by profile ID
    public private(set) var rawContentByProfile: [String: String] = [:]
    // Parsed valid regex pattern strings indexed by profile ID
    public private(set) var rulesByProfile: [String: [String]] = [:]
    // Cleaning activation state per profile ID (true = active, false = skipped)
    public private(set) var profileCleaningEnabled: [String: Bool] = [:]
    
    // Compiled NSRegularExpression cache indexed by profile ID
    @ObservationIgnored
    private var regexListByProfile: [String: [NSRegularExpression]] = [:]
    
    /// Backward-compatible accessor returning raw whitelist text for the default profile.
    public var rawContent: String {
        // Delegate to the per-profile accessor for "default"
        rawContent(for: "default")
    }
    
    /// Backward-compatible accessor returning parsed rules for the default profile.
    public var rules: [String] {
        // Delegate to the per-profile rules accessor for "default"
        rules(for: "default")
    }
    
    /// Initializes the manager and loads saved whitelists from UserDefaults.
    public init() {
        // Load persisted per-profile rules and activation states on startup
        loadWhitelist()
    }
    
    /// Synchronizes CFPreferences across processes and reloads whitelist state from UserDefaults.
    public func reloadFromDefaults() {
        // Flush and synchronize preferences from disk for cross-process daemon visibility
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        #if DEBUG
        // Log debug trace when reloading preferences from disk
        AppLogger.shared.debug("Reloading WhitelistManager state from synchronized UserDefaults...")
        #endif
        // Re-read all per-profile rules and enabled states
        loadWhitelist()
    }
    
    /// Loads per-profile cleaning states and regex whitelists from UserDefaults, migrating legacy data if needed.
    public func loadWhitelist() {
        // Access standard UserDefaults container
        let defaults = UserDefaults.standard
        
        // 1. Load per-profile cleaning activation status dictionary
        if let storedEnabled = defaults.dictionary(forKey: profileCleaningEnabledKey) as? [String: Bool] {
            // Restore saved activation states
            self.profileCleaningEnabled = storedEnabled
        } else {
            // Default to enabled for the primary profile
            self.profileCleaningEnabled = ["default": true]
        }
        
        // 2. Load per-profile whitelists dictionary
        var loadedProfiles: [String: String] = [:]
        if let storedMap = defaults.dictionary(forKey: perProfileDatastoreKey) as? [String: String] {
            // Use existing per-profile dictionary from UserDefaults
            loadedProfiles = storedMap
        }
        
        // Check if "default" profile is missing or empty in perProfileDatastoreKey
        if loadedProfiles["default"] == nil || loadedProfiles["default"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            // Check legacy single-whitelist key for migration
            if let legacy = defaults.string(forKey: legacyDatastoreKey), !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Migrate legacy rules into the "default" profile slot
                loadedProfiles["default"] = legacy
                AppLogger.shared.info("Migrated legacy whitelist rules into 'default' profile")
            } else {
                // Candidate file paths to seed initial whitelist rules from disk
                let candidatePaths: [String] = [
                    "~/gitclones/cookie-cleaner/WHITELIST".expandingTildeInPath,
                    "../WHITELIST".expandingTildeInPath,
                    "~/Library/Application Support/CookieCleaner/WHITELIST".expandingTildeInPath
                ]
                var initialContent: String?
                // Attempt to read initial seed content from the first available candidate file
                for path in candidatePaths {
                    if FileManager.default.fileExists(atPath: path),
                       let content = try? String(contentsOfFile: path, encoding: .utf8),
                       !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        initialContent = content
                        AppLogger.shared.info("Migrated initial whitelist rules from '\(path)' into datastore")
                        break
                    }
                }
                
                // Fallback default whitelist seed if no external WHITELIST file was found
                let defaultSeed = initialContent ?? """
                (^|\\.)github\\.com$
                (^|\\.)trevalim\\.fr$
                (^|\\.)trevalim\\.cloudflareaccess\\.com$
                (^|\\.)sncf-connect\\.com$
                (^|\\.)monidentifiant\\.sncf$
                (^|\\.)digiposte\\.fr$
                (^|\\.)boursobank\\.com$
                (^|\\.)uca\\.fr$
                """
                // Assign seed to default profile and persist to legacy key
                loadedProfiles["default"] = defaultSeed
                defaults.set(defaultSeed, forKey: legacyDatastoreKey)
            }
            // Persist migrated per-profile map back to UserDefaults
            defaults.set(loadedProfiles, forKey: perProfileDatastoreKey)
        }
        
        // Reset in-memory maps before populating parsed rules
        self.rawContentByProfile = loadedProfiles
        self.rulesByProfile = [:]
        self.regexListByProfile = [:]
        
        // Parse raw text into regex objects for every stored profile
        for (profileId, content) in loadedProfiles {
            let (rules, regexes) = parseContent(content)
            self.rulesByProfile[profileId] = rules
            self.regexListByProfile[profileId] = regexes
        }
        
        // Calculate total active rules across all profiles for logging
        let totalRules = rulesByProfile.values.map(\.count).reduce(0, +)
        AppLogger.shared.info("Loaded whitelists for \(loadedProfiles.count) profile(s) (\(totalRules) total rules)")
        #if DEBUG
        // Log per-profile summary in debug builds
        for (pid, rules) in rulesByProfile {
            let active = isProfileCleaningEnabled(profileId: pid)
            AppLogger.shared.debug("Profile '\(pid)': \(rules.count) rule(s), cleaningEnabled=\(active)")
        }
        #endif
    }
    
    /// Returns the raw multiline whitelist string for a given profile ID.
    public func rawContent(for profileId: String) -> String {
        // Return stored string or empty string if profile has no rules yet
        return rawContentByProfile[profileId] ?? ""
    }
    
    /// Returns the array of compiled rule strings for a given profile ID.
    public func rules(for profileId: String) -> [String] {
        // Return parsed rule list or empty array if none configured
        return rulesByProfile[profileId] ?? []
    }
    
    /// Returns whether cookie and cache cleaning is active for the specified profile ID (defaults to true).
    public func isProfileCleaningEnabled(profileId: String) -> Bool {
        // Unconfigured profiles default to active cleaning (true)
        return profileCleaningEnabled[profileId] ?? true
    }
    
    /// Enables or disables cookie and cache cleaning for a specific profile and persists to UserDefaults.
    public func setProfileCleaningEnabled(_ enabled: Bool, for profileId: String) {
        // Update in-memory activation state for the profile
        profileCleaningEnabled[profileId] = enabled
        // Persist updated dictionary to UserDefaults and synchronize cross-process
        let defaults = UserDefaults.standard
        defaults.set(profileCleaningEnabled, forKey: profileCleaningEnabledKey)
        defaults.synchronize()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        
        #if DEBUG
        // Log debug state change for profile activation toggle
        AppLogger.shared.debug("Updated profileCleaningEnabled[\(profileId)] = \(enabled)")
        #endif
        AppLogger.shared.info("\(enabled ? "✅ Activated" : "⏸️ Deactivated") cleaning for profile '\(profileId)'")
    }
    
    /// Updates and persists the raw whitelist content for a specific Safari profile ID.
    public func updateWhitelist(content: String, for profileId: String = "default") {
        // Store raw content and re-parse regex patterns for the target profile
        self.rawContentByProfile[profileId] = content
        let (rules, regexes) = parseContent(content)
        self.rulesByProfile[profileId] = rules
        self.regexListByProfile[profileId] = regexes
        
        // Save updated profile map to UserDefaults
        let defaults = UserDefaults.standard
        defaults.set(self.rawContentByProfile, forKey: perProfileDatastoreKey)
        if profileId == "default" {
            // Keep legacy key in sync when updating the default profile
            defaults.set(content, forKey: legacyDatastoreKey)
        }
        // Flush preferences to disk for daemon access
        defaults.synchronize()
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        
        #if DEBUG
        // Log debug details of compiled regex count for the updated profile
        AppLogger.shared.debug("Saved whitelist for profile '\(profileId)' with \(regexes.count) compiled regex(es)")
        #endif
        AppLogger.shared.info("Applied and saved \(rules.count) whitelist rule(s) for profile '\(profileId)'")
    }
    
    /// Appends an exact-domain regex rule to the specified profile's whitelist.
    public func addRule(forDomain domain: String, profileId: String = "default") {
        // Build subdomain-safe anchored regex pattern for the domain
        let newRule = "(^|\\.)\(NSRegularExpression.escapedPattern(for: domain))$"
        var current = rawContent(for: profileId)
        // Ensure trailing newline before appending new rule
        if !current.hasSuffix("\n") && !current.isEmpty {
            current += "\n"
        }
        current += "\(newRule)\n"
        #if DEBUG
        // Log rule addition in debug mode
        AppLogger.shared.debug("Appending rule '\(newRule)' to profile '\(profileId)'")
        #endif
        // Save updated whitelist content for the profile
        updateWhitelist(content: current, for: profileId)
    }
    
    /// Backward-compatible helper that updates the "default" profile whitelist.
    public func updateWhitelist(content: String) {
        // Forward update call to default profile
        updateWhitelist(content: content, for: "default")
    }
    
    /// Parses multiline whitelist text into valid rule strings and compiled NSRegularExpression objects.
    private func parseContent(_ content: String) -> ([String], [NSRegularExpression]) {
        var newRules: [String] = []
        var newRegexList: [NSRegularExpression] = []
        
        // Split content by newline and evaluate each non-comment line
        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip blank lines and comment lines starting with '#'
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            
            do {
                // Compile regex pattern and append to valid lists
                let regex = try NSRegularExpression(pattern: line)
                newRules.append(line)
                newRegexList.append(regex)
            } catch {
                // Report malformed regex pattern to the in-app console
                AppLogger.shared.error("Invalid regex rule '\(line)': \(error.localizedDescription)")
            }
        }
        
        return (newRules, newRegexList)
    }
    
    /// Evaluates whether a domain string matches any compiled regex rule in the specified profile's whitelist.
    ///
    /// - Parameters:
    ///   - test: The candidate domain or URL host string (e.g., ".github.com" or "apple.com").
    ///   - profileId: The target Safari profile identifier (e.g., "default" or UUID).
    /// - Returns: True if any compiled regex rule matches the candidate domain, false otherwise.
    public func isWhitelisted(test: String, profileId: String = "default") -> Bool {
        // Strip leading/trailing whitespace and null characters from candidate domain
        let clean = test.trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
        // Guard against empty input strings
        guard !clean.isEmpty else { return false }
        
        // Prepare normalized version without leading dot (e.g., ".apple.com" -> "apple.com")
        let cleanWithoutDot = clean.hasPrefix(".") ? String(clean.dropFirst()) : clean
        
        // Retrieve compiled regex array for the given profile ID, falling back to "default" if profile not yet customized
        let regexList = regexListByProfile[profileId] ?? regexListByProfile["default"] ?? []
        // Return false if no rules are available for evaluation
        guard !regexList.isEmpty else { return false }
        
        // Check each regex for a match against either raw domain or normalized domain without leading dot
        for regex in regexList {
            // Compute UTF-16 ranges for both candidate representations
            let rangeFull = NSRange(location: 0, length: clean.utf16.count)
            let rangeClean = NSRange(location: 0, length: cleanWithoutDot.utf16.count)
            
            // Check match against the full candidate string
            if regex.firstMatch(in: clean, options: [], range: rangeFull) != nil {
                #if DEBUG
                // Log debug trace of successful whitelist match
                AppLogger.shared.debug("🛡️ Whitelist match for domain '\(clean)' in profile '\(profileId)' using pattern '\(regex.pattern)'")
                #endif
                return true
            }
            
            // Check match against normalized string without leading dot (supports anchored ^...$ regexes)
            if regex.firstMatch(in: cleanWithoutDot, options: [], range: rangeClean) != nil {
                #if DEBUG
                // Log debug trace of successful whitelist match via dot-stripped normalization
                AppLogger.shared.debug("🛡️ Whitelist match for stripped domain '\(cleanWithoutDot)' in profile '\(profileId)' using pattern '\(regex.pattern)'")
                #endif
                return true
            }
        }
        
        // Candidate did not match any active regex rules
        return false
    }
}
