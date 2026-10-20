import Foundation
@_exported import MTPShared
import MTPKit

let devices = try MTPDevices.detect()
if devices.isEmpty {
    print("No MTP devices. Unlock phone, set USB mode to File transfer.")
    exit(1)
}

if CommandLine.arguments.dropFirst().first == "selftest" {
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
