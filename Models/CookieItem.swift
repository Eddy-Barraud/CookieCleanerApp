import Foundation

public struct CookieItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let profileId: String
    public let profileName: String
    public let url: String
    public let name: String
    public let path: String
    public let valueSize: Int
    public let creation: Date?
    public let expiration: Date?
    public let isWhitelisted: Bool
    public let isSecure: Bool
    public let isHTTPOnly: Bool
    
    public var cleanDomain: String {
        var d = url
        if d.hasPrefix(".") {
            d.removeFirst()
        }
        return d
    }
    
    public init(
        id: UUID = UUID(),
        profileId: String = "default",
        profileName: String = "Default",
        url: String,
        name: String,
        path: String,
        valueSize: Int,
        creation: Date?,
        expiration: Date?,
        isWhitelisted: Bool,
        isSecure: Bool,
        isHTTPOnly: Bool
    ) {
        self.id = id
        self.profileId = profileId
        self.profileName = profileName
        self.url = url
        self.name = name
        self.path = path
        self.valueSize = valueSize
        self.creation = creation
        self.expiration = expiration
        self.isWhitelisted = isWhitelisted
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
    }
}
