import Foundation
import Security

public enum MTPRequest: Codable, Sendable {
    case devices
    case storages(device: String)
    case list(device: String, storage: UInt32, parent: UInt32)
    case entry(device: String, id: UInt32)
    case download(device: String, id: UInt32, destination: String)
    case upload(device: String, source: String, name: String, storage: UInt32, parent: UInt32)
    case makeFolder(device: String, name: String, storage: UInt32, parent: UInt32)
    case delete(device: String, id: UInt32)
    case rename(device: String, id: UInt32, name: String)
}

public struct MTPDeviceSummary: Codable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum MTPResponse: Codable, Sendable {
    case devices([MTPDeviceSummary])
    case storages([MTPStorage])
    case entries([MTPEntry])
    case entry(MTPEntry)
    case done
}

@objc public protocol MTPHelperProtocol {
    func send(_ request: Data, reply: @escaping (Data?, String?) -> Void)
    func subscribe()
}

@objc public protocol MTPEventsProtocol {
    func devicesChanged()
}

public enum MTPService {
    /// Read from our own signature so the team is configured in one place only.
    /// Empty when unsigned, which makes `codeRequirement` match nothing.
    public static let teamID: String = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else {
            return ""
        }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String ?? ""
    }()
    public static let groupID = "\(teamID).com.cbrill.mtpfinder"
    public static let machName = "\(groupID).helper"
    public static let helperPlist = "com.cbrill.mtpfinder.helper.plist"
    public static let helperProcess = "MTPHelper"

    /// MTP allows a single session. These also open the phone and, when they
    /// exit uncleanly, leave a session behind that locks everyone else out.
    public static let conflictingProcesses = ["Android File Transfer", "Android File Transfer Agent"]

    public static var codeRequirement: String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    public static func transferDirectory() throws -> URL {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else {
            throw MTPError.remote("App group unavailable")
        }
        let dir = group.appendingPathComponent("Transfers/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
