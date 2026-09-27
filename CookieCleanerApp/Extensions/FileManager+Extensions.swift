import Foundation

public extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

public extension FileManager {
    func executeOnContentsOf(path: String, action: (_ item: String) -> Void) {
        let enumerator = self.enumerator(atPath: path)
        while let item = enumerator?.nextObject() as? String {
            action(item)
        }
    }
    
    func fileSize(atPath path: String) -> Int64 {
        guard let attrs = try? attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }
    
    func directorySize(atPath path: String) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = enumerator(atPath: path) else { return 0 }
        while let file = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(file)
            total += fileSize(atPath: fullPath)
        }
        return total
    }
}

public extension String {
    var expandingTildeInPath: String {
        return (self as NSString).expandingTildeInPath
    }
}
