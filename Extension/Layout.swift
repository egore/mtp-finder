import FileProvider
import Foundation
import MTPShared

/// Maps File Provider containers to MTP (storage, parent) pairs.
/// A single storage is flattened into the domain root.
final class Layout: @unchecked Sendable {
    private static let storageTTL: TimeInterval = 30
    private static let noParent: UInt32 = 0

    struct Location {
        let storage: UInt32
        let parent: UInt32
    }

    let client: MTPClient
    let device: String

    private let lock = NSLock()
    private var cached: (date: Date, storages: [MTPStorage])?

    init(client: MTPClient, device: String) {
        self.client = client
        self.device = device
    }

    func storages() async throws -> [MTPStorage] {
        if let hit = cachedStorages() {
            return hit
        }

        let fresh = try await client.storages(device: device)
        store(fresh)
        return fresh
    }

    private func cachedStorages() -> [MTPStorage]? {
        lock.lock()
        defer { lock.unlock() }

        guard let cached, Date().timeIntervalSince(cached.date) < Self.storageTTL else {
            return nil
        }
        return cached.storages
    }

    private func store(_ storages: [MTPStorage]) {
        lock.lock()
        cached = (Date(), storages)
        lock.unlock()
    }

    func location(of container: NSFileProviderItemIdentifier) async throws -> Location {
        if container == .rootContainer {
            let list = try await storages()
            guard list.count == 1 else {
                throw NSFileProviderError(.noSuchItem)
            }
            return Location(storage: list[0].id, parent: MTPEntry.rootParent)
        }

        switch ItemID.parse(container) {
        case .storage(let id):
            return Location(storage: id, parent: MTPEntry.rootParent)
        case .object(let id):
            let entry = try await client.entry(device: device, id: id)
            return Location(storage: entry.storageID, parent: id)
        case nil:
            throw NSFileProviderError(.noSuchItem)
        }
    }

    func item(for entry: MTPEntry) async throws -> MTPItem {
        MTPItem(entry: entry, parent: try await parentID(of: entry))
    }

    func children(of container: NSFileProviderItemIdentifier) async throws -> [MTPItem] {
        if container == .rootContainer {
            let list = try await storages()
            if list.count != 1 {
                return list.map { MTPItem(storage: $0) }
            }
        }

        let location = try await location(of: container)
        let entries = try await client.list(
            device: device, storage: location.storage, parent: location.parent
        )
        return entries.map { MTPItem(entry: $0, parent: container) }
    }

    private func parentID(of entry: MTPEntry) async throws -> NSFileProviderItemIdentifier {
        guard entry.parentID == Self.noParent || entry.parentID == MTPEntry.rootParent else {
            return ItemID.object(entry.parentID)
        }
        return try await storages().count == 1 ? .rootContainer : ItemID.storage(entry.storageID)
    }
}
