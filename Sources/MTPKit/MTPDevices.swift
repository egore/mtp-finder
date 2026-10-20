import CMTP
import Foundation
@_exported import MTPShared

public enum MTPDevices {
    private static let initOnce: Void = { LIBMTP_Init() }()

    public static func detect() throws -> [MTPDeviceInfo] {
        _ = initOnce

        var raw: UnsafeMutablePointer<LIBMTP_raw_device_t>?
        var count: Int32 = 0
        let status = LIBMTP_Detect_Raw_Devices(&raw, &count)

        if status == LIBMTP_ERROR_NO_DEVICE_ATTACHED {
            return []
        }
        guard status == LIBMTP_ERROR_NONE, let raw else {
            throw MTPError.noDevice
        }
        defer { free(raw) }

        return (0..<Int(count)).map { index in
            let device = raw[index]
            return MTPDeviceInfo(
                busLocation: device.bus_location,
                devNum: device.devnum,
                vendor: device.device_entry.vendor.map { String(cString: $0) } ?? "Unknown",
                product: device.device_entry.product.map { String(cString: $0) } ?? "Unknown"
            )
        }
    }
}
