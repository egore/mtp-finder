import Foundation
@_exported import MTPShared
import MTPKit

func isRunning(_ name: String) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-x", name]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
    task.waitUntilExit()
    return task.terminationStatus == 0
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
let force = arguments.contains("--force")
arguments.removeAll { $0 == "--force" }

let holders = ([MTPService.helperProcess] + MTPService.conflictingProcesses).filter(isRunning)
if !holders.isEmpty && !force {
    fail("""
    Running: \(holders.joined(separator: ", ")). These may hold the phone. MTP allows one \
    session, so opening it here can lock the other program out until the phone is \
    replugged. Quit them (for MTPFinder also run pkill -x MTPHelper, launchd restarts it \
    without a session) and pass --force.
    """)
}

do {
    let devices = try MTPDevices.detect()
    if devices.isEmpty {
        fail("No MTP devices. Unlock phone, set USB mode to File transfer.")
    }

    if arguments.first == "selftest" {
        try selfTest(devices[0])
        exit(0)
    }

    for info in devices {
        print("\(info.vendor) \(info.product) [\(info.id)]")

        let session = try MTPSession(info: info)
        for storage in try session.storages() {
            print("  \(storage.name) (\(storage.id)) free \(storage.freeSpace / 1_000_000) MB")
            for entry in try session.list(storageID: storage.id) {
                print("    \(entry.isFolder ? "d" : "-") \(entry.size)\t\(entry.name)")
            }
        }
    }
} catch {
    fail("\(error.localizedDescription)")
}

func selfTest(_ info: MTPDeviceInfo) throws {
    let session = try MTPSession(info: info)
    let storage = try session.storages()[0]
    let local = FileManager.default.temporaryDirectory.appendingPathComponent("mtp-selftest.txt")
    try Data("hello mtp".utf8).write(to: local)

    let folder = try session.makeFolder(name: "mtpkit-selftest", storageID: storage.id, parent: MTPEntry.rootParent)
    let file = try session.upload(from: local, name: "a.txt", storageID: storage.id, parent: folder.id)
    try session.rename(id: file.id, to: "b.txt")

    let names = try session.list(storageID: storage.id, parent: folder.id).map(\.name)
    print("listed:", names)

    let back = FileManager.default.temporaryDirectory.appendingPathComponent("mtp-selftest-back.txt")
    try? FileManager.default.removeItem(at: back)
    try session.download(id: file.id, to: back)
    print("roundtrip:", try String(contentsOf: back))

    try session.delete(id: file.id)
    try session.delete(id: folder.id)
    print("cleaned up")
}
