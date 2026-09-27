import Foundation

public struct CleaningResult: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let cookiesBefore: Int
    public let cookiesKept: Int
    public let cookiesDeleted: Int
    public let bytesFreed: Int64
    public let cacheFilesRemoved: Int
    public let scanFilesRemoved: Int
    public let duration: TimeInterval
    public let isSuccess: Bool
    public let errorMessage: String?
    
    public var formattedBytesFreed: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytesFreed)
    }
    
    public init(
        timestamp: Date = Date(),
        cookiesBefore: Int,
        cookiesKept: Int,
        cookiesDeleted: Int,
        bytesFreed: Int64,
        cacheFilesRemoved: Int,
        scanFilesRemoved: Int,
        duration: TimeInterval,
        isSuccess: Bool = true,
        errorMessage: String? = nil
    ) {
        self.timestamp = timestamp
        self.cookiesBefore = cookiesBefore
        self.cookiesKept = cookiesKept
        self.cookiesDeleted = cookiesDeleted
        self.bytesFreed = bytesFreed
        self.cacheFilesRemoved = cacheFilesRemoved
        self.scanFilesRemoved = scanFilesRemoved
        self.duration = duration
        self.isSuccess = isSuccess
        self.errorMessage = errorMessage
    }
}
