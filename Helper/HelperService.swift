import Foundation
import MTPKit
import MTPShared

final class HelperService: NSObject, NSXPCListenerDelegate, MTPHelperProtocol {
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
            return .storages(try session(device).storages())
        case .list(let device, let storage, let parent):
            return .entries(try session(device).list(storageID: storage, parent: parent))
        case .entry(let device, let id):
            return .entry(try session(device).entry(id: id))
        case .download(let device, let id, let destination):
            try session(device).download(id: id, to: URL(fileURLWithPath: destination))
            return .done
        case .upload(let device, let source, let name, let storage, let parent):
            let entry = try session(device).upload(
                from: URL(fileURLWithPath: source), name: name, storageID: storage, parent: parent
            )
            return .entry(entry)
        case .makeFolder(let device, let name, let storage, let parent):
            let entry = try session(device).makeFolder(name: name, storageID: storage, parent: parent)
            return .entry(entry)
        case .delete(let device, let id):
            try session(device).delete(id: id)
            return .done
        case .rename(let device, let id, let name):
            try session(device).rename(id: id, to: name)
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
