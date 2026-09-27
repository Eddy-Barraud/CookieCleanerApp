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
            profiles.append(SafariProfile(id: "default", name: "Default Profile", cookieURL: defaultURL))
        }
        
        // 2. Custom Profiles in WebsiteDataStore (macOS Sonoma / Sequoia / Safari 17+)
        let dataStorePath = "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore".expandingTildeInPath
        if let subdirs = try? FileManager.default.contentsOfDirectory(atPath: dataStorePath) {
            for dir in subdirs {
                let candidateURL = URL(fileURLWithPath: "\(dataStorePath)/\(dir)/Cookies/Cookies.binarycookies")
                if FileManager.default.fileExists(atPath: candidateURL.path) {
                    let displayName = profileNames[dir.uppercased()] ?? profileNames[dir.lowercased()] ?? "Profile (\(dir.prefix(8)))"
                    profiles.append(SafariProfile(id: dir, name: displayName, cookieURL: candidateURL))
                }
            }
        }
        
        // 3. Fallback: Profiles directory
        let legacyPath = "~/Library/Containers/com.apple.Safari/Data/Library/Safari/Profiles".expandingTildeInPath
        if let subdirs = try? FileManager.default.contentsOfDirectory(atPath: legacyPath) {
            for dir in subdirs {
                let candidateURL = URL(fileURLWithPath: "\(legacyPath)/\(dir)/Cookies/Cookies.binarycookies")
                if FileManager.default.fileExists(atPath: candidateURL.path) && !profiles.contains(where: { $0.cookieURL == candidateURL }) {
                    let displayName = profileNames[dir.uppercased()] ?? profileNames[dir.lowercased()] ?? "Profile (\(dir.prefix(8)))"
                    profiles.append(SafariProfile(id: dir, name: displayName, cookieURL: candidateURL))
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
    
    public func loadCookies(whitelist: WhitelistManager = .shared) throws -> [CookieItem] {
        var allItems: [CookieItem] = []
        let profiles = Self.discoverProfiles()
        self.discoveredProfiles = profiles
        
        for profile in profiles {
            guard let data = try? Data(contentsOf: profile.cookieURL),
                  let binaryCookies = try? BinaryDataDecoder().decode(BinaryCookies.self, from: data) else {
                continue
            }
            
            for page in binaryCookies.pages {
                for cookie in page.cookies {
                    let domain = (cookie.url ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                    let name = (cookie.name ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                    let path = (cookie.path ?? "/").trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                    let isWhitelisted = whitelist.isWhitelisted(test: domain)
                    
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
    
    public func cleanCookies(whitelist: WhitelistManager = .shared) async -> CleaningResult {
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
        
        for profile in profiles {
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
                    let matches = whitelist.isWhitelisted(test: domain)
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
        
        if encounteredError != nil && totalCookiesBefore == 0 {
            let failedResult = CleaningResult(
                cookiesBefore: 0, cookiesKept: 0, cookiesDeleted: 0,
                bytesFreed: 0, cacheFilesRemoved: 0, scanFilesRemoved: 0,
                duration: Date().timeIntervalSince(startTime),
                isSuccess: false, errorMessage: encounteredError
            )
            self.lastResult = failedResult
            return failedResult
        }
        
        // Cache directories
        var totalCacheFilesRemoved = 0
        let fileManager = FileManager.default
        
        var dirsToErase = Self.dirsToErase
        let dataStorePath = "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore".expandingTildeInPath
        if let subdirs = try? fileManager.contentsOfDirectory(atPath: dataStorePath) {
            for dir in subdirs {
                let profileCaches = "\(dataStorePath)/\(dir)/Caches"
                if fileManager.fileExists(atPath: profileCaches) {
                    dirsToErase.append(profileCaches)
                }
            }
        }
        
        for dir in dirsToErase {
            guard fileManager.fileExists(atPath: dir) else { continue }
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
                    totalBytesFreed += itemSize
                    totalCacheFilesRemoved += 1
                } catch {}
            }
        }
        
        // Scan directories
        var totalScanFilesRemoved = 0
        for dir in Self.dirsToScan {
            guard fileManager.fileExists(atPath: dir) else { continue }
            let enumerator = fileManager.enumerator(atPath: dir)
            var itemsToRemove: [String] = []
            while let item = enumerator?.nextObject() as? String {
                let cleanItem = item.trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
                if !whitelist.isWhitelisted(test: cleanItem) {
                    itemsToRemove.append(item)
                }
            }
            
            for item in itemsToRemove.reversed() {
                let fullPath = (dir as NSString).appendingPathComponent(item)
                let itemSize = fileManager.fileSize(atPath: fullPath)
                do {
                    try fileManager.removeItem(atPath: fullPath)
                    totalBytesFreed += itemSize
                    totalScanFilesRemoved += 1
                } catch {}
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        let result = CleaningResult(
            cookiesBefore: totalCookiesBefore,
            cookiesKept: totalCookiesKept,
            cookiesDeleted: totalCookiesDeleted,
            bytesFreed: totalBytesFreed,
            cacheFilesRemoved: totalCacheFilesRemoved,
            scanFilesRemoved: totalScanFilesRemoved,
            duration: duration,
            isSuccess: encounteredError == nil,
            errorMessage: encounteredError
        )
        
        self.lastResult = result
        AppLogger.shared.success("🏁 Cleanup finished in \(String(format: "%.2f", duration))s: \(totalCookiesDeleted) cookies deleted, \(result.formattedBytesFreed) freed across \(profiles.count) profile(s).")
        
        CumulativeStatsManager.shared.recordCleaning(result: result)
        _ = try? loadCookies(whitelist: whitelist)
        
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
        
        // Cache wipe
        let fileManager = FileManager.default
        var totalCacheFilesRemoved = 0
        for dir in Self.dirsToErase {
            guard fileManager.fileExists(atPath: dir) else { continue }
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
                    totalBytesFreed += itemSize
                    totalCacheFilesRemoved += 1
                } catch {}
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        let result = CleaningResult(
            cookiesBefore: totalCookiesBefore,
            cookiesKept: 0,
            cookiesDeleted: totalCookiesBefore,
            bytesFreed: totalBytesFreed,
            cacheFilesRemoved: totalCacheFilesRemoved,
            scanFilesRemoved: 0,
            duration: duration,
            isSuccess: encounteredError == nil,
            errorMessage: encounteredError
        )
        
        self.lastResult = result
        AppLogger.shared.success("💣 Flush complete: \(totalCookiesBefore) cookies purged, \(result.formattedBytesFreed) freed.")
        CumulativeStatsManager.shared.recordCleaning(result: result)
        _ = try? loadCookies()
        
        return result
    }
}
