import CMTP
import Foundation
@_exported import MTPShared

/// One open MTP device. MTP allows a single session, so every call
/// is serialized on a private queue.
public final class MTPSession: @unchecked Sendable {
    private static let openAttempts = 5
    private static let retryDelay: TimeInterval = 0.3

    private let queue = DispatchQueue(label: "mtp.session")
    private var device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>?

    public init(info: MTPDeviceInfo) throws {
        for attempt in 0..<Self.openAttempts {
            PTPCameraGuard.clear()
            if let opened = Self.open(info) {
                device = opened
                return
            }
            if attempt < Self.openAttempts - 1 {
                Thread.sleep(forTimeInterval: Self.retryDelay)
            }
        }
        throw MTPError.openFailed
    }

    deinit {
        if let device {
            LIBMTP_Release_Device(device)
        }
    }

    public func friendlyName() -> String? {
        queue.sync {
            guard let device else {
                return nil
            }
            for getter in [LIBMTP_Get_Friendlyname, LIBMTP_Get_Modelname] {
                guard let raw = getter(device) else {
                    continue
                }
                defer { free(raw) }
                let name = String(cString: raw)
                if !name.isEmpty {
                    return name
                }
            }
            return nil
        }
    }

    public func storages() throws -> [MTPStorage] {
        try queue.sync {
            let device = try openDevice()
            guard LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED) >= 0 else {
                throw MTPError.locked
            }

            var result: [MTPStorage] = []
            var node = device.pointee.storage
            while let storage = node {
                result.append(MTPStorage(
                    id: storage.pointee.id,
                    name: storage.pointee.StorageDescription.map { String(cString: $0) } ?? "Storage",
                    capacity: storage.pointee.MaxCapacity,
                    freeSpace: storage.pointee.FreeSpaceInBytes
                ))
                node = storage.pointee.next
            }
            return result
        }
    }

    public func list(storageID: UInt32, parent: UInt32 = MTPEntry.rootParent) throws -> [MTPEntry] {
        try queue.sync {
            let device = try openDevice()
            var node = LIBMTP_Get_Files_And_Folders(device, storageID, parent)

            var result: [MTPEntry] = []
            while let file = node {
                result.append(Self.entry(from: file))
                let next = file.pointee.next
                LIBMTP_destroy_file_t(file)
                node = next
            }
            return result
        }
    }

    public func entry(id: UInt32) throws -> MTPEntry {
        try queue.sync {
            let device = try openDevice()
            guard let file = LIBMTP_Get_Filemetadata(device, id) else {
                throw MTPError.notFound("object \(id)")
            }
            defer { LIBMTP_destroy_file_t(file) }
            return Self.entry(from: file)
        }
    }

    public func download(id: UInt32, to url: URL) throws {
        try queue.sync {
            let device = try openDevice()
            guard LIBMTP_Get_File_To_File(device, id, url.path, nil, nil) == 0 else {
                throw MTPError.transferFailed("download \(id)")
            }
        }
    }

    public func upload(
        from url: URL,
        name: String,
        storageID: UInt32,
        parent: UInt32
    ) throws -> MTPEntry {
        try queue.sync {
            let device = try openDevice()
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let modified = (attributes[.modificationDate] as? Date) ?? Date()

            guard let file = LIBMTP_new_file_t() else {
                throw MTPError.transferFailed("alloc")
            }
            defer { LIBMTP_destroy_file_t(file) }

            file.pointee.filename = strdup(name)
            file.pointee.filesize = size
            file.pointee.modificationdate = time_t(modified.timeIntervalSince1970)
            file.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN
            file.pointee.parent_id = parent
            file.pointee.storage_id = storageID

            guard LIBMTP_Send_File_From_File(device, url.path, file, nil, nil) == 0 else {
                throw MTPError.transferFailed("upload \(name)")
            }
            return Self.entry(from: file)
        }
    }

    public func makeFolder(name: String, storageID: UInt32, parent: UInt32) throws -> MTPEntry {
        try queue.sync {
            let device = try openDevice()
            guard let cName = strdup(name) else {
                throw MTPError.transferFailed("alloc")
            }
            defer { free(cName) }

            let id = LIBMTP_Create_Folder(device, cName, parent, storageID)
            guard id != 0 else {
                throw MTPError.transferFailed("mkdir \(name)")
            }
            return MTPEntry(
                id: id,
                parentID: parent,
                storageID: storageID,
                name: name,
                size: 0,
                modified: Date(),
                isFolder: true
            )
        }
    }

    public func delete(id: UInt32) throws {
        try queue.sync {
            let device = try openDevice()
            guard LIBMTP_Delete_Object(device, id) == 0 else {
                throw MTPError.transferFailed("delete \(id)")
            }
        }
    }

    public func rename(id: UInt32, to name: String) throws {
        try queue.sync {
            let device = try openDevice()
            guard let cName = strdup(name) else {
                throw MTPError.transferFailed("alloc")
            }
            defer { free(cName) }

            guard LIBMTP_Set_Object_Filename(device, id, cName) == 0 else {
                throw MTPError.transferFailed("rename \(id)")
            }
        }
    }

    private static func open(_ info: MTPDeviceInfo) -> UnsafeMutablePointer<LIBMTP_mtpdevice_t>? {
        var raw: UnsafeMutablePointer<LIBMTP_raw_device_t>?
        var count: Int32 = 0
        guard LIBMTP_Detect_Raw_Devices(&raw, &count) == LIBMTP_ERROR_NONE, let raw else {
            return nil
        }
        defer { free(raw) }

        let match = (0..<Int(count)).first {
            raw[$0].bus_location == info.busLocation
        }
        guard let match else {
            return nil
        }
        return LIBMTP_Open_Raw_Device_Uncached(&raw[match])
    }

    private static func entry(from file: UnsafeMutablePointer<LIBMTP_file_t>) -> MTPEntry {
        MTPEntry(
            id: file.pointee.item_id,
            parentID: file.pointee.parent_id,
            storageID: file.pointee.storage_id,
            name: file.pointee.filename.map { String(cString: $0) } ?? "",
            size: file.pointee.filesize,
            modified: Date(timeIntervalSince1970: TimeInterval(file.pointee.modificationdate)),
            isFolder: file.pointee.filetype == LIBMTP_FILETYPE_FOLDER
        )
    }

    private func openDevice() throws -> UnsafeMutablePointer<LIBMTP_mtpdevice_t> {
        guard let device else {
            throw MTPError.openFailed
        }
        return device
    }
}
