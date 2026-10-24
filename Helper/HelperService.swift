import Foundation
import MTPKit
import MTPShared
import os

final class HelperService: NSObject, NSXPCListenerDelegate, MTPHelperProtocol {
    private let log = Logger(subsystem: "com.cbrill.mtpfinder", category: "helper")
    private let lock = NSLock()
    private var sessions: [String: MTPSession] = [:]
    private var names: [String: String] = [:]
    private var subscribers: [NSXPCConnection] = []

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: MTPHelperProtocol.self)
        connection.exportedObject = self
        connection.remoteObjectInterface = NSXPCInterface(with: MTPEventsProtocol.self)
        connection.setCodeSigningRequirement(MTPService.codeRequirement)
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let self, let connection else {
                return
            }
            self.lock.lock()
            self.subscribers.removeAll { $0 === connection }
            self.lock.unlock()
        }
        connection.resume()
        return true
    }

    func subscribe() {
        guard let connection = NSXPCConnection.current() else {
            return
        }
        lock.lock()
        subscribers.append(connection)
        lock.unlock()
    }

    func send(_ request: Data, reply: @escaping (Data?, String?) -> Void) {
        do {
            let decoded = try JSONDecoder().decode(MTPRequest.self, from: request)
            let response = try handle(decoded)
            reply(try JSONEncoder().encode(response), nil)
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func usbChanged() {
        let present = Set((try? MTPDevices.detect())?.map(\.id) ?? [])

        lock.lock()
        for id in sessions.keys where !present.contains(id) {
            sessions[id] = nil
            names[id] = nil
        }
        let targets = subscribers
        lock.unlock()

        for connection in targets {
            (connection.remoteObjectProxy as? MTPEventsProtocol)?.devicesChanged()
        }
    }

    private func handle(_ request: MTPRequest) throws -> MTPResponse {
        switch request {
        case .devices:
            return .devices(summaries())
        case .storages(let device):
            return .storages(try withSession(device) { try $0.storages() })
        case .list(let device, let storage, let parent):
            return .entries(try withSession(device) { try $0.list(storageID: storage, parent: parent) })
        case .entry(let device, let id):
            return .entry(try withSession(device) { try $0.entry(id: id) })
        case .download(let device, let id, let destination):
            try withSession(device) { try $0.download(id: id, to: URL(fileURLWithPath: destination)) }
            return .done
        case .upload(let device, let source, let name, let storage, let parent):
            let entry = try withSession(device) {
                try $0.upload(
                    from: URL(fileURLWithPath: source), name: name, storageID: storage, parent: parent
                )
            }
            return .entry(entry)
        case .makeFolder(let device, let name, let storage, let parent):
            let entry = try withSession(device) {
                try $0.makeFolder(name: name, storageID: storage, parent: parent)
            }
            return .entry(entry)
        case .delete(let device, let id):
            try withSession(device) { try $0.delete(id: id) }
            return .done
        case .rename(let device, let id, let name):
            try withSession(device) { try $0.rename(id: id, to: name) }
            return .done
        }
    }

    private func summaries() -> [MTPDeviceSummary] {
        let infos = (try? MTPDevices.detect()) ?? []

        return infos.map { info in
            _ = try? session(info.id)

            lock.lock()
            let name = names[info.id]
            lock.unlock()

            return MTPDeviceSummary(id: info.id, name: name ?? "\(info.vendor) \(info.product)")
        }
    }

    /// Another process opening the phone, a replug or a lock invalidates the
    /// cached session without any notification. Drop it so the next request
    /// reopens instead of failing until the helper restarts.
    private func withSession<T>(_ id: String, _ body: (MTPSession) throws -> T) throws -> T {
        do {
            return try body(try session(id))
        } catch let error as MTPError where error.invalidatesSession {
            log.notice("Session for device \(id, privacy: .public) lost (\(error.localizedDescription, privacy: .public)), reopening")
            dropSession(id)
            do {
                return try body(try session(id))
            } catch let retryError as MTPError where retryError.invalidatesSession {
                dropSession(id)
                throw retryError
            }
        }
    }

    private func dropSession(_ id: String) {
        lock.lock()
        sessions[id] = nil
        lock.unlock()
    }

    private func session(_ id: String) throws -> MTPSession {
        lock.lock()
        defer { lock.unlock() }

        if let existing = sessions[id] {
            return existing
        }
        guard let info = try MTPDevices.detect().first(where: { $0.id == id }) else {
            throw MTPError.noDevice
        }

        let opened = try MTPSession(info: info)
        sessions[id] = opened
        names[id] = opened.friendlyName()
        return opened
    }
}

private extension MTPError {
    var invalidatesSession: Bool {
        switch self {
        case .locked, .openFailed:
            return true
        default:
            return false
        }
    }
}
