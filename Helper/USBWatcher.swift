import Foundation
import IOKit
import IOKit.usb

/// Fires on any USB device arrival or removal, coalesced.
final class USBWatcher {
    private static let debounce: TimeInterval = 0.5

    private let onChange: () -> Void
    private var port: IONotificationPortRef?
    private var pending: DispatchWorkItem?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, .main)
        self.port = port

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            while case let service = IOIteratorNext(iterator), service != 0 {
                IOObjectRelease(service)
            }
            guard let context else {
                return
            }
            Unmanaged<USBWatcher>.fromOpaque(context).takeUnretainedValue().fire()
        }

        for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            IOServiceAddMatchingNotification(
                port, notification, IOServiceMatching("IOUSBHostDevice"), callback, context, &iterator
            )
            callback(context, iterator)
        }
    }

    private func fire() {
        pending?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: work)
    }
}
