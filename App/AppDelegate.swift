import AppKit
import FileProvider
import MTPShared
import ServiceManagement

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = MTPClient()
    private var statusItem: NSStatusItem?
    private var devices: [MTPDeviceSummary] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "iphone.gen3", accessibilityDescription: "MTP")
        rebuildMenu()

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.rebuildMenu()
            }
        }

        client.onDevicesChanged = { [weak self] in
            Task { await self?.sync() }
        }

        Task {
            await registerHelper()
            client.subscribe()
            if CommandLine.arguments.contains("--reset") {
                reset()
                return
            }
            await sync()
        }
    }

    private func registerHelper() async {
        let service = SMAppService.agent(plistName: MTPService.helperPlist)
        try? await service.unregister()
        do {
            try service.register()
        } catch {
            NSLog("Helper register failed: \(error)")
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func sync() async {
        do {
            devices = try await client.devices()
        } catch {
            NSLog("Device list failed: \(error)")
            devices = []
        }

        await syncDomains()
        await MainActor.run { rebuildMenu() }
    }

    private func syncDomains() async {
        let existing = (try? await NSFileProviderManager.domains()) ?? []
        let wanted = Set(devices.map(\.id))

        for domain in existing where !wanted.contains(domain.identifier.rawValue) {
            try? await NSFileProviderManager.remove(domain)
        }

        let known = Set(existing.map(\.identifier.rawValue))
        for device in devices where !known.contains(device.id) {
            let domain = NSFileProviderDomain(
                identifier: NSFileProviderDomainIdentifier(device.id),
                displayName: device.name
            )
            do {
                try await NSFileProviderManager.add(domain)
            } catch {
                NSLog("Add domain failed: \(error)")
            }
        }
    }

    private func conflictingApps() -> [String] {
        NSWorkspace.shared.runningApplications
            .compactMap(\.localizedName)
            .filter(MTPService.conflictingProcesses.contains)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let conflicts = Set(conflictingApps()).sorted()
        if !conflicts.isEmpty {
            menu.addItem(withTitle: "⚠︎ \(conflicts.joined(separator: ", ")) is running", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Quit it, only one program can use the phone", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
        }
        if devices.isEmpty {
            menu.addItem(withTitle: "No devices", action: nil, keyEquivalent: "")
        }
        for device in devices {
            menu.addItem(withTitle: device.name, action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(withTitle: "Reset", action: #selector(reset), keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = [#selector(refresh), #selector(reset)].contains($0.action) ? self : nil }
        statusItem?.menu = menu
    }

    @objc private func reset() {
        Task {
            for domain in (try? await NSFileProviderManager.domains()) ?? [] {
                try? await NSFileProviderManager.remove(domain)
            }
            await sync()
        }
    }

    @objc private func refresh() {
        Task { await sync() }
    }
}
