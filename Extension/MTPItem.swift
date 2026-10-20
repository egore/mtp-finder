import FileProvider
import MTPShared
import UniformTypeIdentifiers

enum ItemID {
    private static let storagePrefix = "s:"
    private static let objectPrefix = "o:"

    enum Kind {
        case storage(UInt32)
        case object(UInt32)
    }

    static func storage(_ id: UInt32) -> NSFileProviderItemIdentifier {
        .init("\(storagePrefix)\(id)")
    }

    static func object(_ id: UInt32) -> NSFileProviderItemIdentifier {
        .init("\(objectPrefix)\(id)")
    }

    static func parse(_ identifier: NSFileProviderItemIdentifier) -> Kind? {
        let raw = identifier.rawValue
        if raw.hasPrefix(storagePrefix), let id = UInt32(raw.dropFirst(storagePrefix.count)) {
            return .storage(id)
        }
        if raw.hasPrefix(objectPrefix), let id = UInt32(raw.dropFirst(objectPrefix.count)) {
            return .object(id)
        }
        return nil
    }
}

final class MTPItem: NSObject, NSFileProviderItem {
    // Bump when item metadata semantics change, to force a refresh.
    private static let metadataSchema = 2

    private let entry: MTPEntry?
    private let storage: MTPStorage?
    private let parent: NSFileProviderItemIdentifier
    private let rootName: String?

    init(rootName: String) {
        self.entry = nil
        self.storage = nil
        self.parent = .rootContainer
        self.rootName = rootName
    }

    init(entry: MTPEntry, parent: NSFileProviderItemIdentifier) {
        self.entry = entry
        self.storage = nil
        self.parent = parent
        self.rootName = nil
    }

    init(storage: MTPStorage) {
        self.entry = nil
        self.storage = storage
        self.parent = .rootContainer
        self.rootName = nil
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        if rootName != nil {
            return .rootContainer
        }
        if let entry {
            return ItemID.object(entry.id)
        }
        return ItemID.storage(storage?.id ?? 0)
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier { parent }

    var filename: String { entry?.name ?? storage?.name ?? rootName ?? "Storage" }

    var isFolder: Bool { entry?.isFolder ?? true }

    var contentType: UTType {
        if isFolder {
            return .folder
        }
        let ext = (filename as NSString).pathExtension
        return UTType(filenameExtension: ext) ?? .data
    }

    var capabilities: NSFileProviderItemCapabilities {
        guard let entry else {
            return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems]
        }
        if entry.isFolder {
            return [.allowsReading, .allowsContentEnumerating, .allowsAddingSubItems,
                    .allowsDeleting, .allowsRenaming]
        }
        return [.allowsReading, .allowsDeleting, .allowsRenaming]
    }

    var fileSystemFlags: NSFileProviderFileSystemFlags {
        var flags: NSFileProviderFileSystemFlags = [.userReadable, .userWritable]
        if isFolder {
            flags.insert(.userExecutable)
        }
        return flags
    }

    var documentSize: NSNumber? {
        guard let entry, !entry.isFolder else {
            return nil
        }
        return NSNumber(value: entry.size)
    }

    var contentModificationDate: Date? { entry?.modified }

    var itemVersion: NSFileProviderItemVersion {
        let seconds = Int(entry?.modified.timeIntervalSince1970 ?? 0)
        let content = Data("\(entry?.size ?? 0)-\(seconds)".utf8)
        let metadata = Data("\(filename)-\(seconds)-\(Self.metadataSchema)".utf8)
        return NSFileProviderItemVersion(contentVersion: content, metadataVersion: metadata)
    }
}
