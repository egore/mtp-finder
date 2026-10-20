import Foundation

/// Talks to the unsandboxed helper that owns the USB device.
public final class MTPClient: NSObject, MTPEventsProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    public var onDevicesChanged: (@Sendable () -> Void)?

    public override init() {
        super.init()
    }

    public func devices() async throws -> [MTPDeviceSummary] {
        guard case .devices(let list) = try await send(.devices) else {
            throw MTPError.remote("Bad response")
        }
        return list
    }

    public func storages(device: String) async throws -> [MTPStorage] {
        guard case .storages(let list) = try await send(.storages(device: device)) else {
            throw MTPError.remote("Bad response")
        }
        return list
    }

    public func list(device: String, storage: UInt32, parent: UInt32) async throws -> [MTPEntry] {
        let response = try await send(.list(device: device, storage: storage, parent: parent))
        guard case .entries(let list) = response else {
            throw MTPError.remote("Bad response")
        }
        return list
    }

    public func entry(device: String, id: UInt32) async throws -> MTPEntry {
        guard case .entry(let entry) = try await send(.entry(device: device, id: id)) else {
            throw MTPError.remote("Bad response")
        }
        return entry
    }

    public func download(device: String, id: UInt32, to url: URL) async throws {
        _ = try await send(.download(device: device, id: id, destination: url.path))
    }

    public func upload(
        device: String,
        from url: URL,
        name: String,
        storage: UInt32,
        parent: UInt32
    ) async throws -> MTPEntry {
        let request = MTPRequest.upload(
            device: device, source: url.path, name: name, storage: storage, parent: parent
        )
        guard case .entry(let entry) = try await send(request) else {
            throw MTPError.remote("Bad response")
        }
        return entry
    }

    public func makeFolder(
        device: String,
        name: String,
        storage: UInt32,
        parent: UInt32
    ) async throws -> MTPEntry {
        let request = MTPRequest.makeFolder(device: device, name: name, storage: storage, parent: parent)
        guard case .entry(let entry) = try await send(request) else {
            throw MTPError.remote("Bad response")
        }
        return entry
    }

    public func delete(device: String, id: UInt32) async throws {
        _ = try await send(.delete(device: device, id: id))
    }

    public func rename(device: String, id: UInt32, name: String) async throws {
        _ = try await send(.rename(device: device, id: id, name: name))
    }

    public func subscribe() {
        proxy()?.subscribe()
    }

    public func devicesChanged() {
        onDevicesChanged?()
    }

    private func send(_ request: MTPRequest) async throws -> MTPResponse {
        let payload = try JSONEncoder().encode(request)

        return try await withCheckedThrowingContinuation { continuation in
            let failure: (Error) -> Void = { continuation.resume(throwing: $0) }
            guard let proxy = proxy(onError: failure) else {
                continuation.resume(throwing: MTPError.remote("Helper unavailable"))
                return
            }

            proxy.send(payload) { data, message in
                if let message {
                    continuation.resume(throwing: MTPError.remote(message))
                    return
                }
                guard let data, let response = try? JSONDecoder().decode(MTPResponse.self, from: data) else {
                    continuation.resume(throwing: MTPError.remote("Bad response"))
                    return
                }
                continuation.resume(returning: response)
            }
        }
    }

    private func proxy(onError: ((Error) -> Void)? = nil) -> MTPHelperProtocol? {
        let connection = currentConnection()
        let object = connection.remoteObjectProxyWithErrorHandler { error in
            onError?(error)
        }
        return object as? MTPHelperProtocol
    }

    private func currentConnection() -> NSXPCConnection {
        lock.lock()
        defer { lock.unlock() }

        if let connection {
            return connection
        }

        let new = NSXPCConnection(machServiceName: MTPService.machName, options: [])
        new.remoteObjectInterface = NSXPCInterface(with: MTPHelperProtocol.self)
        new.exportedInterface = NSXPCInterface(with: MTPEventsProtocol.self)
        new.exportedObject = self
        new.setCodeSigningRequirement(MTPService.codeRequirement)
        new.invalidationHandler = { [weak self] in self?.reset() }
        new.interruptionHandler = { [weak self] in self?.reset() }
        new.resume()

        connection = new
        return new
    }

    private func reset() {
        lock.lock()
        connection = nil
        lock.unlock()
    }
}
