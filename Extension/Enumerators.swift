import FileProvider
import Foundation

extension Error {
    /// File Provider only accepts its own, Cocoa and POSIX error domains.
    var forProvider: Error {
        let supported = [NSFileProviderErrorDomain, NSCocoaErrorDomain, NSPOSIXErrorDomain]
        if supported.contains((self as NSError).domain) {
            return self
        }
        return NSFileProviderError(.serverUnreachable)
    }
}

private func anchor() -> NSFileProviderSyncAnchor {
    NSFileProviderSyncAnchor(Data("\(Int(Date().timeIntervalSince1970 * 1000))".utf8))
}

final class EmptyEnumerator: NSObject, NSFileProviderEnumerator {
    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        observer.finishEnumerating(upTo: nil)
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: syncAnchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(anchor())
    }
}

/// Last seen child versions per container, to diff on the next poll.
final class ChangeCache: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [NSFileProviderItemIdentifier: [NSFileProviderItemIdentifier: Data]] = [:]

    func diff(
        container: NSFileProviderItemIdentifier,
        items: [MTPItem]
    ) -> (updated: [MTPItem], deleted: [NSFileProviderItemIdentifier]) {
        var current: [NSFileProviderItemIdentifier: Data] = [:]
        for item in items {
            current[item.itemIdentifier] = item.itemVersion.contentVersion + item.itemVersion.metadataVersion
        }

        lock.lock()
        defer { lock.unlock() }

        let previous = seen[container] ?? [:]
        seen[container] = current

        let updated = items.filter { previous[$0.itemIdentifier] != current[$0.itemIdentifier] }
        let deleted = previous.keys.filter { current[$0] == nil }
        return (updated, Array(deleted))
    }
}

final class FolderEnumerator: NSObject, NSFileProviderEnumerator {
    private let container: NSFileProviderItemIdentifier
    private let layout: Layout
    private let cache: ChangeCache

    init(container: NSFileProviderItemIdentifier, layout: Layout, cache: ChangeCache) {
        self.container = container
        self.layout = layout
        self.cache = cache
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        Task {
            do {
                let items = try await layout.children(of: container)
                _ = cache.diff(container: container, items: items)
                observer.didEnumerate(items)
                observer.finishEnumerating(upTo: nil)
            } catch {
                observer.finishEnumeratingWithError(error.forProvider)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from syncAnchor: NSFileProviderSyncAnchor) {
        Task {
            do {
                let items = try await layout.children(of: container)
                let changes = cache.diff(container: container, items: items)

                if !changes.updated.isEmpty {
                    observer.didUpdate(changes.updated)
                }
                if !changes.deleted.isEmpty {
                    observer.didDeleteItems(withIdentifiers: changes.deleted)
                }
                observer.finishEnumeratingChanges(upTo: anchor(), moreComing: false)
            } catch {
                observer.finishEnumeratingWithError(error.forProvider)
            }
        }
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(anchor())
    }
}
