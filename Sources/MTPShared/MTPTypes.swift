import Foundation

public enum MTPError: Error, LocalizedError {
    case noDevice
    case openFailed
    case locked
    case notFound(String)
    case transferFailed(String)
    case remote(String)

    public var errorDescription: String? {
        switch self {
        case .noDevice: return "No MTP device"
        case .openFailed: return "Cannot open device"
        case .locked: return "Device locked or not in File transfer mode"
        case .notFound(let what): return "Not found: \(what)"
        case .transferFailed(let what): return "Transfer failed: \(what)"
        case .remote(let message): return message
        }
    }
}

public struct MTPDeviceInfo: Codable, Sendable {
    public let busLocation: UInt32
    public let devNum: UInt8
    public let vendor: String
    public let product: String

    /// Location ID is tied to the physical port, unlike devNum.
    public var id: String { String(busLocation, radix: 16) }

    public init(busLocation: UInt32, devNum: UInt8, vendor: String, product: String) {
        self.busLocation = busLocation
        self.devNum = devNum
        self.vendor = vendor
        self.product = product
    }
}

public struct MTPStorage: Codable, Sendable {
    public let id: UInt32
    public let name: String
    public let capacity: UInt64
    public let freeSpace: UInt64

    public init(id: UInt32, name: String, capacity: UInt64, freeSpace: UInt64) {
        self.id = id
        self.name = name
        self.capacity = capacity
        self.freeSpace = freeSpace
    }
}

public struct MTPEntry: Codable, Sendable {
    public static let rootParent: UInt32 = 0xFFFF_FFFF

    public let id: UInt32
    public let parentID: UInt32
    public let storageID: UInt32
    public let name: String
    public let size: UInt64
    public let modified: Date
    public let isFolder: Bool

    public init(
        id: UInt32,
        parentID: UInt32,
        storageID: UInt32,
        name: String,
        size: UInt64,
        modified: Date,
        isFolder: Bool
    ) {
        self.id = id
        self.parentID = parentID
        self.storageID = storageID
        self.name = name
        self.size = size
        self.modified = modified
        self.isFolder = isFolder
    }
}
