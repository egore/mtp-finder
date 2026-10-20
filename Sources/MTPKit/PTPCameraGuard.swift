import Foundation

/// macOS's ptpcamerad claims the phone's imaging interface and launchd
/// respawns it. Kill it right before opening the device.
enum PTPCameraGuard {
    static func clear() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-9", "-x", "ptpcamerad"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}
