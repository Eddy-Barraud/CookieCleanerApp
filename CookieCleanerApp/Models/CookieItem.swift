import Foundation

public struct CookieItem: Identifiable, Sendable {
    public let id = UUID()
    public let url: String
    public let name: String
    public let path: String
    public let valueSize: Int
    public let creation: Date?
    public let expiration: Date?
    public let isWhitelisted: Bool
    public let isSecure: Bool
    public let isHTTPOnly: Bool
    public let profileName: String
    
    public var cleanDomain: String {
        var d = url
        if d.hasPrefix(".") {
            d.removeFirst()
        }
        return d
    }
    
    public init(
        url: String,
        name: String,
        path: String,
        valueSize: Int,
        creation: Date?,
        expiration: Date?,
        isWhitelisted: Bool,
        isSecure: Bool,
        isHTTPOnly: Bool,
        profileName: String = "Default"
    ) {
        self.url = url
        self.name = name
        self.path = path
        self.valueSize = valueSize
        self.creation = creation
        self.expiration = expiration
        self.isWhitelisted = isWhitelisted
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.profileName = profileName
    }
}
