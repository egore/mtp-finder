import Foundation
import MTPShared

let service = HelperService()
let listener = NSXPCListener(machServiceName: MTPService.machName)
listener.setConnectionCodeSigningRequirement(MTPService.codeRequirement)
listener.delegate = service
listener.resume()

let watcher = USBWatcher { service.usbChanged() }
watcher.start()

RunLoop.main.run()
