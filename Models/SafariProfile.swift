import Foundation

public struct SafariProfile: Identifiable, Hashable, Sendable {
    public let id: String // "default" or UUID string
    public let name: String
    public let cookieURL: URL
    public var cacheSizeBytes: Int64
    
    public init(id: String, name: String, cookieURL: URL, cacheSizeBytes: Int64 = 0) {
        self.id = id
        self.name = name
        self.cookieURL = cookieURL
        self.cacheSizeBytes = cacheSizeBytes
    }
    
    /// Root directory for profile-specific WebKit data, if applicable
    public var profileDirectoryURL: URL? {
        if id == "default" {
            return URL(fileURLWithPath: "~/Library/Containers/com.apple.Safari/Data/Library".expandingTildeInPath)
        }
        // e.g. .../WebsiteDataStore/<UUID>/Cookies/Cookies.binarycookies -> .../WebsiteDataStore/<UUID>
        return cookieURL.deletingLastPathComponent().deletingLastPathComponent()
    }
    
    /// Pure cache directories for this specific profile
    public var cacheDirectories: [String] {
        var dirs: [String] = []
        if id == "default" {
            dirs.append(contentsOf: [
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari",
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/WebKit",
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.WebKit.Networking",
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.WebKit.WebContent",
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.WebKit.GPU",
                "~/Library/Containers/com.apple.Safari/Data/Library/Caches/com.apple.Safari.SearchHelper",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteData",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Default/Caches",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Default/Cache",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Default/Application Cache",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Default/DOMCache",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Default/ResourceLoadStatistics",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Default/ServiceWorkers",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Default/WebsiteData",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Default/GPUCache",
                "~/Library/Caches/com.apple.Safari",
                "~/Library/Caches/com.apple.WebKit.Networking",
                "~/Library/Caches/com.apple.WebKit.WebContent",
                "~/Library/Caches/com.apple.WebKit.GPU"
            ].map { $0.expandingTildeInPath })
        } else if let base = profileDirectoryURL?.path {
            dirs.append(contentsOf: [
                "\(base)/Caches",
                "\(base)/Cache",
                "\(base)/Application Cache",
                "\(base)/DOMCache",
                "\(base)/ResourceLoadStatistics",
                "\(base)/ServiceWorkers",
                "\(base)/WebsiteData",
                "\(base)/GPUCache",
                "\(base)/AlternativeServices.binary",
                "\(base)/HSTSCache.binary"
            ])
        }
        return dirs
    }
    
    /// Web storage directories for this profile (LocalStorage, IndexedDB, etc.)
    public var storageDirectories: [String] {
        var dirs: [String] = []
        if id == "default" {
            dirs.append(contentsOf: [
                "~/Library/Safari/LocalStorage",
                "~/Library/Containers/com.apple.Safari/Data/Library/Safari/LocalStorage",
                "~/Library/Safari/Databases/___IndexedDB/v1",
                "~/Library/Containers/com.apple.Safari/Data/Library/Safari/Databases/___IndexedDB/v1",
                "~/Library/Containers/com.apple.Safari/Data/Library/Safari/Databases",
                "~/Library/WebKit/MediaKeys",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/MediaKeys",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Default/LocalStorage",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Default/IndexedDB",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Default/GeneralStorage",
                "~/Library/Containers/com.apple.Safari/Data/Library/WebKit/WebsiteDataStore/Default/WebStorage"
            ].map { $0.expandingTildeInPath })
        } else if let base = profileDirectoryURL?.path {
            dirs.append(contentsOf: [
                "\(base)/LocalStorage",
                "\(base)/IndexedDB",
                "\(base)/Databases",
                "\(base)/WebStorage",
                "\(base)/GeneralStorage"
            ])
        }
        return dirs
    }
    
    public var formattedCacheSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: cacheSizeBytes)
    }
    
    public func calculateCacheSize() -> Int64 {
        let fileManager = FileManager.default
        var total: Int64 = 0
        for dir in cacheDirectories {
            guard fileManager.fileExists(atPath: dir) else { continue }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: dir, isDirectory: &isDir) {
                if isDir.boolValue {
                    total += fileManager.directorySize(atPath: dir)
                } else {
                    total += fileManager.fileSize(atPath: dir)
                }
            }
        }
        return total
    }
}
