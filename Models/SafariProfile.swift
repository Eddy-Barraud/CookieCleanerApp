import Foundation

public struct SafariProfile: Identifiable, Hashable, Sendable {
    public let id: String // "default" or UUID string
    public let name: String
    public let cookieURL: URL
    
    public init(id: String, name: String, cookieURL: URL) {
        self.id = id
        self.name = name
        self.cookieURL = cookieURL
    }
}
