import Foundation
import Observation

@Observable
@MainActor
public final class WhitelistManager {
    public static let shared = WhitelistManager()
    
    private let datastoreKey = "CookieCleaner.whitelistContent"
    
    public private(set) var rawContent: String = ""
    public private(set) var rules: [String] = []
    
    @ObservationIgnored
    private var regexList: [NSRegularExpression] = []
    
    public init() {
        loadWhitelist()
    }
    
    public func loadWhitelist() {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: datastoreKey), !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.rawContent = stored
            parseContent(stored)
            AppLogger.shared.info("Loaded \(rules.count) whitelist rule(s) from datastore")
            return
        }
        
        // Seed from existing file on disk if available, otherwise use defaults
        let candidatePaths: [String] = [
            "~/gitclones/cookie-cleaner/WHITELIST".expandingTildeInPath,
            "../WHITELIST".expandingTildeInPath,
            "~/Library/Application Support/CookieCleaner/WHITELIST".expandingTildeInPath
        ]
        
        var initialContent: String?
        for path in candidatePaths {
            if FileManager.default.fileExists(atPath: path),
               let content = try? String(contentsOfFile: path, encoding: .utf8),
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                initialContent = content
                AppLogger.shared.info("Migrated initial whitelist rules from '\(path)' into datastore")
                break
            }
        }
        
        let contentToUse = initialContent ?? """
        (^|\\.)github\\.com$
        (^|\\.)trevalim\\.fr$
        (^|\\.)trevalim\\.cloudflareaccess\\.com$
        (^|\\.)sncf-connect\\.com$
        (^|\\.)monidentifiant\\.sncf$
        (^|\\.)digiposte\\.fr$
        (^|\\.)boursobank\\.com$
        (^|\\.)uca\\.fr$
        """
        
        self.rawContent = contentToUse
        defaults.set(contentToUse, forKey: datastoreKey)
        parseContent(contentToUse)
        AppLogger.shared.info("Initialized whitelist with \(rules.count) rule(s)")
    }
    
    public func updateWhitelist(content: String) {
        self.rawContent = content
        parseContent(content)
        UserDefaults.standard.set(content, forKey: datastoreKey)
        AppLogger.shared.info("Applied and saved \(rules.count) whitelist rule(s) to datastore")
    }
    
    private func parseContent(_ content: String) {
        var newRules: [String] = []
        var newRegexList: [NSRegularExpression] = []
        
        let lines = content.components(separatedBy: .newlines)
        for rawLine in lines {
            // Trim both whitespaces AND newlines / carriage returns
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            
            do {
                let regex = try NSRegularExpression(pattern: line)
                newRules.append(line)
                newRegexList.append(regex)
            } catch {
                AppLogger.shared.error("Invalid regex rule '\(line)': \(error.localizedDescription)")
            }
        }
        
        self.rules = newRules
        self.regexList = newRegexList
    }
    
    public func isWhitelisted(test: String) -> Bool {
        // Strip null terminators (\0), spaces, tabs, and newlines that may be present in decoded binary cookies
        let clean = test.trimmingCharacters(in: CharacterSet(charactersIn: "\0 \t\r\n"))
        guard !clean.isEmpty else { return false }
        
        for regex in regexList {
            let range = NSRange(location: 0, length: clean.utf16.count)
            if regex.firstMatch(in: clean, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }
}
