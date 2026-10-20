import FileProvider
import MTPShared
import UniformTypeIdentifiers

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let domain: NSFileProviderDomain
    private let layout: Layout
    private let cache = ChangeCache()

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        self.layout = Layout(client: MTPClient(), device: domain.identifier.rawValue)
        super.init()
    }

    func invalidate() {}

    func item(
        for identifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        run(completionHandler) { [layout, domain] in
            if identifier == .rootContainer {
                return MTPItem(rootName: domain.displayName)
            }
            switch ItemID.parse(identifier) {
            case .object(let id):
                let entry = try await layout.client.entry(device: layout.device, id: id)
                return try await layout.item(for: entry)
            case .storage(let id):
                guard let storage = try await layout.storages().first(where: { $0.id == id }) else {
                    throw NSFileProviderError(.noSuchItem)
                }
                return MTPItem(storage: storage)
            case nil:
                throw NSFileProviderError(.noSuchItem)
            }
        }
    }

    func fetchContents(
        for itemIdentifier: NSFileProviderItemIdentifier,
        version requestedVersion: NSFileProviderItemVersion?,
        request: NSFileProviderRequest,
        completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        Task { [layout] in
            do {
                guard case .object(let id) = ItemID.parse(itemIdentifier) else {
                    throw NSFileProviderError(.noSuchItem)
                }
                let entry = try await layout.client.entry(device: layout.device, id: id)
                let destination = try MTPService.transferDirectory().appendingPathComponent(entry.name)

                try await layout.client.download(device: layout.device, id: id, to: destination)
                progress.completedUnitCount = 1
                completionHandler(destination, try await layout.item(for: entry), nil)
            } catch {
                completionHandler(nil, nil, error.forProvider)
            }
        }
        return progress
    }

    func createItem(
        basedOn itemTemplate: NSFileProviderItem,
        fields: NSFileProviderItemFields,
        contents url: URL?,
        options: NSFileProviderCreateItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        Task { [layout] in
            do {
                let location = try await layout.location(of: itemTemplate.parentItemIdentifier)
                let name = itemTemplate.filename
                let entry: MTPEntry

                if itemTemplate.contentType == .folder {
                    entry = try await layout.client.makeFolder(
                        device: layout.device, name: name, storage: location.storage, parent: location.parent
                    )
                } else {
                    guard let url else {
                        throw NSFileProviderError(.noSuchItem)
                    }
                    let staged = try MTPService.transferDirectory().appendingPathComponent(name)
                    try FileManager.default.copyItem(at: url, to: staged)
                    defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }

                    entry = try await layout.client.upload(
                        device: layout.device, from: staged, name: name,
                        storage: location.storage, parent: location.parent
                    )
                }

                progress.completedUnitCount = 1
                completionHandler(try await layout.item(for: entry), [], false, nil)
            } catch {
                completionHandler(nil, [], false, error.forProvider)
            }
        }
        return progress
    }

    func modifyItem(
        _ item: NSFileProviderItem,
        baseVersion version: NSFileProviderItemVersion,
        changedFields: NSFileProviderItemFields,
        contents newContents: URL?,
        options: NSFileProviderModifyItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let unsupported: NSFileProviderItemFields = [.contents, .parentItemIdentifier]

        Task { [layout] in
            do {
                guard case .object(let id) = ItemID.parse(item.itemIdentifier) else {
                    throw NSFileProviderError(.noSuchItem)
                }
                if !changedFields.intersection(unsupported).isEmpty {
                    throw CocoaError(.featureUnsupported)
                }
                if changedFields.contains(.filename) {
                    try await layout.client.rename(device: layout.device, id: id, name: item.filename)
                }

                let entry = try await layout.client.entry(device: layout.device, id: id)
                progress.completedUnitCount = 1
                completionHandler(try await layout.item(for: entry), [], false, nil)
            } catch {
                completionHandler(nil, [], false, error.forProvider)
            }
        }
        return progress
    }

    func deleteItem(
        identifier: NSFileProviderItemIdentifier,
        baseVersion version: NSFileProviderItemVersion,
        options: NSFileProviderDeleteItemOptions = [],
        request: NSFileProviderRequest,
        completionHandler: @escaping (Error?) -> Void
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        Task { [layout] in
            do {
                guard case .object(let id) = ItemID.parse(identifier) else {
                    throw NSFileProviderError(.noSuchItem)
                }
                try await layout.client.delete(device: layout.device, id: id)
                progress.completedUnitCount = 1
                completionHandler(nil)
            } catch {
                completionHandler(error.forProvider)
            }
        }
        return progress
    }

    func enumerator(
        for containerItemIdentifier: NSFileProviderItemIdentifier,
        request: NSFileProviderRequest
    ) throws -> NSFileProviderEnumerator {
        switch containerItemIdentifier {
        case .workingSet, .trashContainer:
            return EmptyEnumerator()
        default:
            return FolderEnumerator(container: containerItemIdentifier, layout: layout, cache: cache)
        }
    }

    private func run(
        _ completion: @escaping (NSFileProviderItem?, Error?) -> Void,
        work: @escaping () async throws -> NSFileProviderItem
    ) -> Progress {
        let progress = Progress(totalUnitCount: 1)

        Task {
            do {
                let item = try await work()
                progress.completedUnitCount = 1
                completion(item, nil)
            } catch {
                completion(nil, error.forProvider)
            }
        }
        return progress
    }
}
