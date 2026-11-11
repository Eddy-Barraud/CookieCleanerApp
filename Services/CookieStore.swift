import Foundation
import Cocoa
import Observation
import SQLite3

public enum PermissionStatus: Equatable, Sendable {
    case unknown
    case granted
    case fileNotFound
    case denied(String)
    
    public var isGranted: Bool {
        if case .granted = self { return true }
        return false
    }
    
    public var displayText: String {
        switch self {
        case .unknown:
            return "Checking permissions..."
        case .granted:
            return "Full Disk Access Granted"
        case .fileNotFound:
            return "Cookies file not found"
        case .denied(let message):
            return "Access Denied: \(message)"
        }
    }
}

@Observable
@MainActor
public final class CookieStore {
    public static let shared = CookieStore()
    
    public static let primaryCookiesURL: URL = URL(
        fileURLWithPath: "~/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies".expandingTildeInPath
    )
    
    public static func fetchProfileNames() -> [String: String] {
        var namesByUUID: [String: String] = [:]
        let dbPath = "~/Library/Containers/com.apple.Safari/Data/Library/Safari/SafariTabs.db".expandingTildeInPath
        var db: OpaquePointer?
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            var stmt: OpaquePointer?
            let query = "SELECT title, external_uuid FROM bookmarks WHERE type = 1 AND subtype = 2;"
            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let titleCol = sqlite3_column_text(stmt, 0),
                       let uuidCol = sqlite3_column_text(stmt, 1) {
                        let title = String(cString: titleCol)
                        let uuid = String(cString: uuidCol)
                        namesByUUID[uuid.uppercased()] = title
                        namesByUUID[uuid.lowercased()] = title
                    }
                }
                sqlite3_finalize(stmt)
            }
            sqlite3_close(db)
        }
        return namesByUUID
    }
    
    public static func discoverProfiles() -> [SafariProfile] {
        var profiles: [SafariProfile] = []
        let profileNames = fetchProfileNames()
        
        // 1. Default Profile
        let defaultURL = primaryCookiesURL
        if FileManager.default.fileExists(atPath: defaultURL.path) {
            var profile = SafariProfile(id: "default", name: "Default Profile", cookieURL: defaultURL)
            profile.cacheSizeBytes = profile.calculateCacheSize()
            profiles.append(profile)
        }
        
        // 2. Custom Profiles in WebsiteDataStore (macOS Sonoma / Sequoia / Safari 17+)
        let dataStorePath = "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore".expandingTildeInPath
        if let subdirs = try? FileManager.default.contentsOfDirectory(atPath: dataStorePath) {
            for dir in subdirs {
                // Skip the "Default" data store directory to prevent duplicate profile registration
                if dir.lowercased() == "default" { continue }
                let candidateURL = URL(fileURLWithPath: "\(dataStorePath)/\(dir)/Cookies/Cookies.binarycookies")
                if FileManager.default.fileExists(atPath: candidateURL.path) && !profiles.contains(where: { $0.cookieURL == candidateURL || $0.id == dir }) {
                    let displayName = profileNames[dir.uppercased()] ?? profileNames[dir.lowercased()] ?? "Profile (\(dir.prefix(8)))"
                    var profile = SafariProfile(id: dir, name: displayName, cookieURL: candidateURL)
                    profile.cacheSizeBytes = profile.calculateCacheSize()
                    profiles.append(profile)
                }
            }
        }
        
        // 3. Fallback: Profiles directory
        let legacyPath = "~/Library/Containers/com.apple.Safari/Data/Library/Safari/Profiles".expandingTildeInPath
        if let subdirs = try? FileManager.default.contentsOfDirectory(atPath: legacyPath) {
            for dir in subdirs {
                if dir.lowercased() == "default" { continue }
                let candidateURL = URL(fileURLWithPath: "\(legacyPath)/\(dir)/Cookies/Cookies.binarycookies")
                if FileManager.default.fileExists(atPath: candidateURL.path) && !profiles.contains(where: { $0.cookieURL == candidateURL || $0.id == dir }) {
                    let displayName = profileNames[dir.uppercased()] ?? profileNames[dir.lowercased()] ?? "Profile (\(dir.prefix(8)))"
                    var profile = SafariProfile(id: dir, name: displayName, cookieURL: candidateURL)
                    profile.cacheSizeBytes = profile.calculateCacheSize()
                    profiles.append(profile)
                }
            }
        }
        
        return profiles
    }
    
    public static let dirsToErase: [String] = [
        "~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari",
        "~/Library/Containers/com.apple.Safari/Data/Library/Caches/WebKit",
        "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData"
    ].map { $0.expandingTildeInPath }
    
    public static let dirsToScan: [String] = [
        "~/Library/Safari/LocalStorage",
        "~/Library/Safari/Databases/___IndexedDB/v1",
        "~/Library/WebKit/MediaKeys",
        "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/MediaKeys"
    ].map { $0.expandingTildeInPath }
    
    /// Extract domain or hostname from web storage and IndexedDB file/folder names.
    ///
    /// Scans path components to isolate the origin identifier (e.g. `https_apple.com_0`),
    /// stripping scheme prefixes, port/partition suffixes, and storage file extensions.
    /// Returns `nil` for internal database metadata and container directories (`v1`, `___IndexedDB`, etc.).
    ///
    /// - Parameter storageItemName: The relative item path or directory name (e.g. `v1/https_apple.com_0/sqlite.db` or `https_github.com_0.localstorage`)
    /// - Returns: The extracted domain host string (e.g. `apple.com`), or nil if non-origin/metadata.
    public static func extractDomain(from storageItemName: String) -> String? {
        let cleanPath = storageItemName.trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
        guard !cleanPath.isEmpty else { return nil }
        
        let components = cleanPath.components(separatedBy: "/")
        
        // Scan each path component to locate the origin container
        for component in components {
            var comp = component.trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
            guard !comp.isEmpty else { continue }
            
            // Strip common non-origin web storage file extensions
            let nonDomainExtensions: Set<String> = [
                "localstorage", "localstorage-wal", "localstorage-shm",
                "sqlite", "sqlite3", "sqlite-wal", "sqlite-shm",
                "db", "db-wal", "db-shm", "wal", "shm", "binary", "plist", "lock", "blob"
            ]
            let ext = (comp as NSString).pathExtension.lowercased()
            if nonDomainExtensions.contains(ext) {
                comp = (comp as NSString).deletingPathExtension
            }
            if comp.hasSuffix(".localstorage-wal") { comp = String(comp.dropLast(16)) }
            if comp.hasSuffix(".localstorage-shm") { comp = String(comp.dropLast(16)) }
            if comp.hasSuffix(".sqlite-wal") { comp = String(comp.dropLast(11)) }
            if comp.hasSuffix(".sqlite-shm") { comp = String(comp.dropLast(11)) }
            if comp.hasSuffix(".db-wal") { comp = String(comp.dropLast(7)) }
            if comp.hasSuffix(".db-shm") { comp = String(comp.dropLast(7)) }
            
            let hasSchemePrefix = comp.hasPrefix("https_") || comp.hasPrefix("http_")
            
            // Strip trailing port/partition index like "_0", "_8080", "_443"
            if let lastUnderscore = comp.lastIndex(of: "_") {
                let suffix = comp[comp.index(after: lastUnderscore)...]
                if Int(suffix) != nil {
                    comp = String(comp[..<lastUnderscore])
                }
            }
            
            // Strip scheme prefixes
            if comp.hasPrefix("https_") {
                comp = String(comp.dropFirst(6))
            } else if comp.hasPrefix("http_") {
                comp = String(comp.dropFirst(5))
            }
            
            // Normalize leading dots
            while comp.hasPrefix(".") {
                comp = String(comp.dropFirst())
            }
            
            guard !comp.isEmpty else { continue }
            
            // Ignore WebKit internal container / system folder names
            let ignoredNames: Set<String> = [
                "v1", "v0", "___indexeddb", ".ds_store", "databases", "storage",
                "media", "cache", "indexeddb", "website_data", "generalstorage",
                "localstorage", "webstorage"
            ]
            if ignoredNames.contains(comp.lowercased()) {
                continue
            }
            
            // Valid origin: must either have possessed a scheme prefix or contain a dot (domain name)
            if hasSchemePrefix || comp.contains(".") {
                return comp
            }
        }
        
        return nil
    }
    
    /// Collect all profile and general cache directories to erase for given profiles
    public static func allCacheDirectories(for profiles: [SafariProfile]? = nil) -> [String] {
        var result = Set<String>()
        let targetProfiles = profiles ?? discoverProfiles()
        
        // General Safari caches (only if "default" is among target profiles)
        if targetProfiles.contains(where: { $0.id == "default" }) {
            let generalCaches = [
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari",
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/WebKit",
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.WebKit.Networking",
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.WebKit.WebContent",
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.WebKit.GPU",
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari.SearchHelper",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData",
                "~/Library/Caches/com.apple.Safari",
                "~/Library/Caches/com.apple.WebKit.Networking",
                "~/Library/Caches/com.apple.WebKit.WebContent",
                "~/Library/Caches/com.apple.WebKit.GPU"
            ].map { $0.expandingTildeInPath }
            result.formUnion(generalCaches)
        }
        
        // Profile specific directories
        for profile in targetProfiles {
            result.formUnion(profile.cacheDirectories)
        }
        
        return Array(result)
    }
    
    /// Collect all profile and general storage directories (LocalStorage, IndexedDB, etc.)
    public static func allStorageDirectories(for profiles: [SafariProfile]? = nil) -> [String] {
        var result = Set<String>()
        let targetProfiles = profiles ?? discoverProfiles()
        
        // Base storage directories (only if "default" is among target profiles)
        if targetProfiles.contains(where: { $0.id == "default" }) {
            let baseStorages = [
                "~/Library/Safari/LocalStorage",
                "~/Library/Containers/com.apple.Safari/Data/Library/Safari/LocalStorage",
                "~/Library/Safari/Databases/___IndexedDB/v1",
                "~/Library/Containers/com.apple.Safari/Data/Library/Safari/Databases/___IndexedDB/v1",
                "~/Library/Containers/com.apple.Safari/Data/Library/Safari/Databases",
                "~/Library/WebKit/MediaKeys",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/MediaKeys"
            ].map { $0.expandingTildeInPath }
            result.formUnion(baseStorages)
        }
        
        for profile in targetProfiles {
            result.formUnion(profile.storageDirectories)
        }
        
        return Array(result)
    }
    
    public private(set) var permissionStatus: PermissionStatus = .unknown
    public private(set) var isCleaning: Bool = false
    public private(set) var lastResult: CleaningResult?
    public private(set) var loadedCookies: [CookieItem] = []
    public private(set) var discoveredProfiles: [SafariProfile] = []
    
    private init() {
        _ = checkPermissions()
    }
    
    @discardableResult
    public func checkPermissions() -> PermissionStatus {
        let cookiePath = Self.primaryCookiesURL.path
        let fileManager = FileManager.default
        
        AppLogger.shared.info("Checking access to '\(cookiePath)'...")
        
        if !fileManager.fileExists(atPath: cookiePath) {
            let parentDir = (cookiePath as NSString).deletingLastPathComponent
            if fileManager.fileExists(atPath: parentDir) {
                if fileManager.isReadableFile(atPath: parentDir) {
                    let status = PermissionStatus.fileNotFound
                    self.permissionStatus = status
                    AppLogger.shared.warning("Cookies file not found, but directory is readable.")
                    return status
                }
            }
        }
        
        do {
            let data = try Data(contentsOf: Self.primaryCookiesURL)
            self.permissionStatus = .granted
            AppLogger.shared.success("Full Disk Access verified! Read \(data.count) bytes from Cookies.binarycookies")
            return .granted
        } catch {
            let nsError = error as NSError
            let underlyingCode = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
            let isPermError = (nsError.domain == NSCocoaErrorDomain && (nsError.code == 257 || nsError.code == 513))
                || underlyingCode == Int(EPERM)
            
            let message: String
            if isPermError {
                message = "Operation not permitted. macOS requires Full Disk Access (FDA)."
                AppLogger.shared.error("❌ Permission Denied: App lacks Full Disk Access to read Safari cookies.")
            } else {
                message = error.localizedDescription
                AppLogger.shared.error("❌ Could not read cookies file: \(error.localizedDescription)")
            }
            
            let status = PermissionStatus.denied(message)
            self.permissionStatus = status
            return status
        }
    }
    
    public func loadCookies(whitelist: WhitelistManager? = nil) throws -> [CookieItem] {
        let whitelist = whitelist ?? WhitelistManager.shared
        whitelist.reloadFromDefaults()
        var allItems: [CookieItem] = []
        let profiles = Self.discoverProfiles()
        self.discoveredProfiles = profiles
        
        for profile in profiles {
            guard let data = try? Data(contentsOf: profile.cookieURL),
                  let binaryCookies = try? BinaryDataDecoder().decode(BinaryCookies.self, from: data) else {
                continue
            }
            
            let isProfileCleaningEnabled = whitelist.isProfileCleaningEnabled(profileId: profile.id)
            
            for page in binaryCookies.pages {
                for cookie in page.cookies {
                    let domain = (cookie.url ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                    let name = (cookie.name ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                    let path = (cookie.path ?? "/").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                    let isRuleWhitelisted = whitelist.isWhitelisted(test: domain, profileId: profile.id)
                    let isWhitelisted = !isProfileCleaningEnabled || isRuleWhitelisted
                    
                    allItems.append(CookieItem(
                        profileId: profile.id,
                        profileName: profile.name,
                        url: domain,
                        name: name,
                        path: path,
                        valueSize: cookie.value?.count ?? 0,
                        creation: cookie.creation,
                        expiration: cookie.expiration,
                        isWhitelisted: isWhitelisted,
                        isProfileCleaningEnabled: isProfileCleaningEnabled,
                        isSecure: cookie.flags.contains(.isSecure),
                        isHTTPOnly: cookie.flags.contains(.isHTTPOnly)
                    ))
                }
            }
        }
        
        self.loadedCookies = allItems
        let kept = allItems.filter { $0.isWhitelisted }.count
        let toDelete = allItems.filter { !$0.isWhitelisted }.count
        AppLogger.shared.info("Loaded \(allItems.count) total cookies across \(profiles.count) profile(s) (\(kept) kept, \(toDelete) to delete)")
        return allItems
    }
    
    public func cleanCookies(whitelist: WhitelistManager? = nil) async -> CleaningResult {
        let whitelist = whitelist ?? WhitelistManager.shared
        whitelist.reloadFromDefaults()
        CumulativeStatsManager.shared.reloadFromDefaults()
        
        guard !isCleaning else {
            return CleaningResult(
                cookiesBefore: 0, cookiesKept: 0, cookiesDeleted: 0,
                bytesFreed: 0, cacheFilesRemoved: 0, scanFilesRemoved: 0,
                duration: 0, isSuccess: false, errorMessage: "Cleaning already in progress"
            )
        }
        
        isCleaning = true
        defer { isCleaning = false }
        
        let startTime = Date()
        AppLogger.shared.info("🧹 Starting cookie & cache cleanup routine...")
        
        var totalCookiesBefore = 0
        var totalCookiesKept = 0
        var totalCookiesDeleted = 0
        var totalBytesFreed: Int64 = 0
        var encounteredError: String? = nil
        
        let profiles = Self.discoverProfiles()
        self.discoveredProfiles = profiles
        
        var enabledProfiles: [SafariProfile] = []
        
        for profile in profiles {
            let profileEnabled = whitelist.isProfileCleaningEnabled(profileId: profile.id)
            if !profileEnabled {
                AppLogger.shared.info("⏭️ Skipping profile '\(profile.name)' (cleaning deactivated for this profile)")
                if let cookiesData = try? Data(contentsOf: profile.cookieURL),
                   let binaryCookies = try? BinaryDataDecoder().decode(BinaryCookies.self, from: cookiesData) {
                    var count = 0
                    for page in binaryCookies.pages { count += page.cookies.count }
                    totalCookiesBefore += count
                    totalCookiesKept += count
                }
                continue
            }
            
            enabledProfiles.append(profile)
            
            #if DEBUG
            AppLogger.shared.debug("Processing profile '\(profile.name)' at: \(profile.cookieURL.path)")
            #endif
            
            let cookiesData: Data
            let binaryCookies: BinaryCookies
            do {
                cookiesData = try Data(contentsOf: profile.cookieURL)
                binaryCookies = try BinaryDataDecoder().decode(BinaryCookies.self, from: cookiesData)
                self.permissionStatus = .granted
            } catch {
                let errorMsg = error.localizedDescription
                AppLogger.shared.error("❌ Failed to read '\(profile.name)': \(errorMsg)")
                encounteredError = errorMsg
                _ = checkPermissions()
                continue
            }
            
            var cookiesBefore = 0
            for page in binaryCookies.pages {
                cookiesBefore += page.cookies.count
            }
            totalCookiesBefore += cookiesBefore
            
            var keptCount = 0
            var deletedCount = 0
            for (pageIndex, page) in binaryCookies.pages.enumerated() {
                let originalCount = page.cookies.count
                page.cookies = page.cookies.filter { cookie in
                    let domain = (cookie.url ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                    let matches = whitelist.isWhitelisted(test: domain, profileId: profile.id)
                    #if DEBUG
                    let cookieDesc = "'\(cookie.name ?? "unnamed")' (domain: \(domain))"
                    if matches {
                        AppLogger.shared.debug("  [\(profile.name) P\(pageIndex)] 🛡️ KEEP: \(cookieDesc)")
                    } else {
                        AppLogger.shared.debug("  [\(profile.name) P\(pageIndex)] 🗑️ REMOVE: \(cookieDesc)")
                    }
                    #endif
                    return matches
                }
                keptCount += page.cookies.count
                deletedCount += (originalCount - page.cookies.count)
            }
            totalCookiesKept += keptCount
            totalCookiesDeleted += deletedCount
            
            do {
                let encoder = BinaryDataEncoder()
                let encodedData = try encoder.encode(binaryCookies)
                let beforeSize = Int64(cookiesData.count)
                let afterSize = Int64(encodedData.count)
                if beforeSize > afterSize {
                    totalBytesFreed += (beforeSize - afterSize)
                }
                
                try encodedData.write(to: profile.cookieURL, options: .atomic)
                AppLogger.shared.success("💾 Saved cleaned '\(profile.name)' (\(encodedData.count) bytes written)")
            } catch {
                let errorMsg = "Failed to write back cookies to \(profile.name): \(error.localizedDescription)"
                AppLogger.shared.error("❌ \(errorMsg)")
                encounteredError = errorMsg
            }
        }
        
        // If FDA is completely unavailable and no cookies could be read across any profile, fail early
        if permissionStatus != .granted && totalCookiesBefore == 0 && encounteredError != nil {
            let failedResult = CleaningResult(
                cookiesBefore: 0, cookiesKept: 0, cookiesDeleted: 0,
                bytesFreed: 0, cacheFilesRemoved: 0, scanFilesRemoved: 0,
                duration: Date().timeIntervalSince(startTime),
                isSuccess: false, errorMessage: encounteredError
            )
            self.lastResult = failedResult
            return failedResult
        }
        
        // Cache and App Data Cleaning
        var totalCacheFilesRemoved = 0
        var totalScanFilesRemoved = 0
        var profileCachesRemoved = 0
        
        let shouldClearProfileCaches = CumulativeStatsManager.shared.clearProfileCachesEnabled
        
        if !enabledProfiles.isEmpty {
            let dirsToErase = shouldClearProfileCaches ? Self.allCacheDirectories(for: enabledProfiles) : (enabledProfiles.contains(where: { $0.id == "default" }) ? Self.dirsToErase : [])
            
            if shouldClearProfileCaches {
                AppLogger.shared.info("📦 Clearing app data cache & storage across \(enabledProfiles.count) active Safari profile(s)...")
            }
            
            let (cacheFreed, cacheCount) = eraseDirectories(dirsToErase)
            totalBytesFreed += cacheFreed
            totalCacheFilesRemoved += cacheCount
            
            let (storageFreed, storageCount) = scanAndCleanStorageDirectories(for: enabledProfiles, whitelist: whitelist)
            totalBytesFreed += storageFreed
            totalScanFilesRemoved += storageCount
            
            // Always aggregate total profile cache and storage files removed
            profileCachesRemoved = cacheCount + storageCount
            if profileCachesRemoved > 0 {
                // Log summary of purged cache and web storage entries
                AppLogger.shared.success("✨ Removed \(profileCachesRemoved) profile cache & storage files (\(ByteCountFormatter.string(fromByteCount: cacheFreed + storageFreed, countStyle: .file)) freed)")
            }
        } else {
            AppLogger.shared.info("All profiles are deactivated for cleaning. No cookies or caches modified.")
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        let result = CleaningResult(
            cookiesBefore: totalCookiesBefore,
            cookiesKept: totalCookiesKept,
            cookiesDeleted: totalCookiesDeleted,
            bytesFreed: totalBytesFreed,
            cacheFilesRemoved: totalCacheFilesRemoved,
            scanFilesRemoved: totalScanFilesRemoved,
            profileCachesRemoved: profileCachesRemoved,
            duration: duration,
            isSuccess: encounteredError == nil,
            errorMessage: encounteredError
        )
        
        self.lastResult = result
        AppLogger.shared.success("🏁 Cleanup finished in \(String(format: "%.2f", duration))s: \(totalCookiesDeleted) cookies deleted, \(result.formattedBytesFreed) freed across \(profiles.count) profile(s) (\(enabledProfiles.count) active).")
        
        CumulativeStatsManager.shared.recordCleaning(result: result)
        _ = try? loadCookies(whitelist: whitelist)
        
        // Refresh profile cache sizes after cleaning
        self.discoveredProfiles = Self.discoverProfiles()
        
        return result
    }
    
    @discardableResult
    public func deleteCookies(byIDs ids: Set<UUID>) async -> Int {
        let targets = loadedCookies.filter { ids.contains($0.id) }
        return await deleteCookies(items: targets)
    }
    
    @discardableResult
    public func deleteCookies(items: [CookieItem]) async -> Int {
        guard !items.isEmpty else { return 0 }
        guard !isCleaning else { return 0 }
        
        isCleaning = true
        defer { isCleaning = false }
        
        var totalDeleted = 0
        var totalBytesFreed: Int64 = 0
        let profiles = Self.discoverProfiles()
        self.discoveredProfiles = profiles
        
        let itemsByProfile = Dictionary(grouping: items, by: { $0.profileId })
        
        struct TargetKey: Hashable {
            let domain: String
            let name: String
            let path: String
        }
        
        for (profileId, targetItems) in itemsByProfile {
            guard let profile = profiles.first(where: { $0.id == profileId }) else { continue }
            
            do {
                let cookiesData = try Data(contentsOf: profile.cookieURL)
                let binaryCookies = try BinaryDataDecoder().decode(BinaryCookies.self, from: cookiesData)
                
                let targetKeys = Set(targetItems.map { TargetKey(domain: $0.url, name: $0.name, path: $0.path) })
                
                var deletedInProfile = 0
                for page in binaryCookies.pages {
                    let originalCount = page.cookies.count
                    page.cookies.removeAll { cookie in
                        let domain = (cookie.url ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                        let name = (cookie.name ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                        let path = (cookie.path ?? "/").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                        return targetKeys.contains(TargetKey(domain: domain, name: name, path: path))
                    }
                    deletedInProfile += (originalCount - page.cookies.count)
                }
                
                if deletedInProfile > 0 {
                    let encoder = BinaryDataEncoder()
                    let encodedData = try encoder.encode(binaryCookies)
                    let beforeSize = Int64(cookiesData.count)
                    let afterSize = Int64(encodedData.count)
                    if beforeSize > afterSize {
                        totalBytesFreed += (beforeSize - afterSize)
                    }
                    try encodedData.write(to: profile.cookieURL, options: .atomic)
                    AppLogger.shared.success("Deleted \(deletedInProfile) cookie(s) from '\(profile.name)'")
                    totalDeleted += deletedInProfile
                }
            } catch {
                AppLogger.shared.error("Failed to delete cookies from '\(profile.name)': \(error.localizedDescription)")
            }
        }
        
        if totalDeleted > 0 {
            let result = CleaningResult(
                cookiesBefore: loadedCookies.count,
                cookiesKept: loadedCookies.count - totalDeleted,
                cookiesDeleted: totalDeleted,
                bytesFreed: totalBytesFreed,
                cacheFilesRemoved: 0,
                scanFilesRemoved: 0,
                duration: 0.05,
                isSuccess: true,
                errorMessage: nil
            )
            CumulativeStatsManager.shared.recordCleaning(result: result)
            _ = try? loadCookies(whitelist: WhitelistManager.shared)
        }
        
        return totalDeleted
    }
    
    public func flushAllCookies() async -> CleaningResult {
        guard !isCleaning else {
            return CleaningResult(
                cookiesBefore: 0, cookiesKept: 0, cookiesDeleted: 0,
                bytesFreed: 0, cacheFilesRemoved: 0, scanFilesRemoved: 0,
                duration: 0, isSuccess: false, errorMessage: "Cleaning already in progress"
            )
        }
        
        isCleaning = true
        defer { isCleaning = false }
        
        let startTime = Date()
        AppLogger.shared.warning("🚨 Flushing ALL cookies across all profiles...")
        
        var totalCookiesBefore = 0
        var totalBytesFreed: Int64 = 0
        var encounteredError: String? = nil
        
        let profiles = Self.discoverProfiles()
        self.discoveredProfiles = profiles
        
        for profile in profiles {
            do {
                let cookiesData = try Data(contentsOf: profile.cookieURL)
                let binaryCookies = try BinaryDataDecoder().decode(BinaryCookies.self, from: cookiesData)
                
                for page in binaryCookies.pages {
                    totalCookiesBefore += page.cookies.count
                    page.cookies.removeAll()
                }
                
                let encoder = BinaryDataEncoder()
                let encodedData = try encoder.encode(binaryCookies)
                let beforeSize = Int64(cookiesData.count)
                let afterSize = Int64(encodedData.count)
                if beforeSize > afterSize {
                    totalBytesFreed += (beforeSize - afterSize)
                }
                
                try encodedData.write(to: profile.cookieURL, options: .atomic)
                AppLogger.shared.success("💾 Flushed all cookies from '\(profile.name)'")
            } catch {
                let errorMsg = "Failed to flush \(profile.name): \(error.localizedDescription)"
                AppLogger.shared.error("❌ \(errorMsg)")
                encounteredError = errorMsg
            }
        }
        
        // Cache and Storage wipe across all profiles
        var totalCacheFilesRemoved = 0
        let allCaches = Self.allCacheDirectories(for: profiles)
        let (cacheFreed, cacheCount) = eraseDirectories(allCaches)
        totalBytesFreed += cacheFreed
        totalCacheFilesRemoved += cacheCount
        
        let allStorages = Self.allStorageDirectories(for: profiles)
        let (storageFreed, storageCount) = eraseDirectories(allStorages)
        totalBytesFreed += storageFreed
        totalCacheFilesRemoved += storageCount
        
        let duration = Date().timeIntervalSince(startTime)
        let result = CleaningResult(
            cookiesBefore: totalCookiesBefore,
            cookiesKept: 0,
            cookiesDeleted: totalCookiesBefore,
            bytesFreed: totalBytesFreed,
            cacheFilesRemoved: totalCacheFilesRemoved,
            scanFilesRemoved: 0,
            profileCachesRemoved: totalCacheFilesRemoved,
            duration: duration,
            isSuccess: encounteredError == nil,
            errorMessage: encounteredError
        )
        
        self.lastResult = result
        AppLogger.shared.success("💣 Flush complete: \(totalCookiesBefore) cookies purged, \(result.formattedBytesFreed) freed.")
        CumulativeStatsManager.shared.recordCleaning(result: result)
        _ = try? loadCookies()
        
        self.discoveredProfiles = Self.discoverProfiles()
        
        return result
    }
    
    @discardableResult
    public func clearProfileAppDataCaches(whitelist: WhitelistManager? = nil) async -> CleaningResult {
        let whitelist = whitelist ?? WhitelistManager.shared
        whitelist.reloadFromDefaults()
        CumulativeStatsManager.shared.reloadFromDefaults()
        
        guard !isCleaning else {
            return CleaningResult(
                cookiesBefore: 0, cookiesKept: 0, cookiesDeleted: 0,
                bytesFreed: 0, cacheFilesRemoved: 0, scanFilesRemoved: 0,
                profileCachesRemoved: 0, duration: 0, isSuccess: false, errorMessage: "Cleaning already in progress"
            )
        }
        
        isCleaning = true
        defer { isCleaning = false }
        
        let startTime = Date()
        AppLogger.shared.info("🧼 Clearing app data caches & storage across active Safari profiles...")
        
        let profiles = Self.discoverProfiles()
        self.discoveredProfiles = profiles
        let enabledProfiles = profiles.filter { whitelist.isProfileCleaningEnabled(profileId: $0.id) }
        
        var totalFreed: Int64 = 0
        var cacheCount = 0
        var storageCount = 0
        
        if !enabledProfiles.isEmpty {
            let allCaches = Self.allCacheDirectories(for: enabledProfiles)
            let (cFreed, cCount) = eraseDirectories(allCaches)
            cacheCount = cCount
            totalFreed += cFreed
            
            let (sFreed, sCount) = scanAndCleanStorageDirectories(for: enabledProfiles, whitelist: whitelist)
            storageCount = sCount
            totalFreed += sFreed
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let totalFiles = cacheCount + storageCount
        
        let result = CleaningResult(
            cookiesBefore: loadedCookies.count,
            cookiesKept: loadedCookies.count,
            cookiesDeleted: 0,
            bytesFreed: totalFreed,
            cacheFilesRemoved: cacheCount,
            scanFilesRemoved: storageCount,
            profileCachesRemoved: totalFiles,
            duration: duration,
            isSuccess: true,
            errorMessage: nil
        )
        
        self.lastResult = result
        AppLogger.shared.success("🏁 Profile app data cache cleanup finished: \(totalFiles) files removed, \(result.formattedBytesFreed) freed across \(enabledProfiles.count) active profile(s).")
        CumulativeStatsManager.shared.recordCleaning(result: result)
        
        self.discoveredProfiles = Self.discoverProfiles()
        
        return result
    }
    
    @discardableResult
    private func eraseDirectories(_ dirs: [String]) -> (bytesFreed: Int64, filesRemoved: Int) {
        let fileManager = FileManager.default
        var totalFreed: Int64 = 0
        var totalRemoved = 0
        
        for dir in dirs {
            guard fileManager.fileExists(atPath: dir) else { continue }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: dir, isDirectory: &isDir) else { continue }
            
            if isDir.boolValue {
                let enumerator = fileManager.enumerator(atPath: dir)
                var itemsToRemove: [String] = []
                while let item = enumerator?.nextObject() as? String {
                    itemsToRemove.append(item)
                }
                
                for item in itemsToRemove.reversed() {
                    let fullPath = (dir as NSString).appendingPathComponent(item)
                    let itemSize = fileManager.fileSize(atPath: fullPath)
                    do {
                        try fileManager.removeItem(atPath: fullPath)
                        totalFreed += itemSize
                        totalRemoved += 1
                    } catch {}
                }
            } else {
                let itemSize = fileManager.fileSize(atPath: dir)
                do {
                    try fileManager.removeItem(atPath: dir)
                    totalFreed += itemSize
                    totalRemoved += 1
                } catch {}
            }
        }
        
        return (totalFreed, totalRemoved)
    }
    
    /// Scans per-profile LocalStorage, IndexedDB, and WebKit storage directories, removing files not matching that profile's whitelist.
    @discardableResult
    private func scanAndCleanStorageDirectories(for profiles: [SafariProfile], whitelist: WhitelistManager) -> (bytesFreed: Int64, filesRemoved: Int) {
        let fileManager = FileManager.default
        var totalFreed: Int64 = 0
        var totalRemoved = 0
        
        // Iterate through each active Safari profile
        for profile in profiles {
            // Collect profile-specific storage directories
            var profileDirs = Set(profile.storageDirectories)
            if profile.id == "default" {
                // Include top-level Safari storage paths when cleaning the default profile
                profileDirs.formUnion(Self.dirsToScan)
            }
            
            #if DEBUG
            // Log storage scan start for the current profile in debug mode
            AppLogger.shared.debug("Scanning \(profileDirs.count) storage director(ies) for profile '\(profile.name)' (\(profile.id))")
            #endif
            
            // Enumerate each storage directory belonging to the profile
            for dir in profileDirs {
                guard fileManager.fileExists(atPath: dir) else { continue }
                let enumerator = fileManager.enumerator(atPath: dir)
                var itemsToRemove: [String] = []
                while let item = enumerator?.nextObject() as? String {
                    // Normalize item path and extract embedded domain identifier
                    let cleanItem = item.trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                    
                    // Only remove storage entries that resolve to an identifiable domain/origin not present in the profile whitelist.
                    // Internal WebKit container structures and metadata files (e.g. "v1", "___IndexedDB", "indexeddb.lock", "Databases.db")
                    // return nil from extractDomain and are safely preserved so whitelisted sites keep their web storage.
                    if let extractedDomain = Self.extractDomain(from: cleanItem) {
                        let isWhitelisted = whitelist.isWhitelisted(test: extractedDomain, profileId: profile.id)
                        if !isWhitelisted {
                            itemsToRemove.append(item)
                        }
                    }
                }
                
                // Delete queued storage entries in reverse order (deepest children first)
                for item in itemsToRemove.reversed() {
                    let fullPath = (dir as NSString).appendingPathComponent(item)
                    let itemSize = fileManager.fileSize(atPath: fullPath)
                    do {
                        try fileManager.removeItem(atPath: fullPath)
                        totalFreed += itemSize
                        totalRemoved += 1
                    } catch {}
                }
            }
        }
        
        return (totalFreed, totalRemoved)
    }
}
