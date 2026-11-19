import Foundation
import IOKit.hid

/// One finger on the touchpad, in raw pad units (x 0...1919, y 0...1079, origin top-left).
struct TouchPoint {
    let id: UInt8
    let x: Double
    let y: Double
}

/// The touchpad state from one input report.
struct PadFrame {
    let touches: [TouchPoint]
    let pressed: Bool
    let time: TimeInterval
}

/// Reads DualSense / DualSense Edge input reports straight from IOHID (USB and Bluetooth),
/// without seizing the device, so games and the system still see the controller.
final class DualSenseReader {
    enum Charge {
        case unknown
        case onBattery
        case charging
        case full
        case error
    }

    /// One connected controller. Status fields update with every full input report.
    final class Controller {
        let device: IOHIDDevice
        let name: String
        let transport: String
        let productID: Int
        /// The Bluetooth address over Bluetooth, the serial number over USB (when it reports one).
        let serial: String?
        let connectedAt = Date()
        let buffer: UnsafeMutablePointer<UInt8>
        fileprivate(set) var battery: Int?
        fileprivate(set) var charge = Charge.unknown
        /// Full input reports received so far; the model turns it into a rate.
        fileprivate(set) var reportCount = 0

        var model: String { productID == 0x0DF2 ? "DualSense Edge" : "DualSense" }

        fileprivate(set) var estimator = BatteryEstimator()
        func estimate(now: TimeInterval) -> BatteryEstimator.Estimate? { estimator.estimate(now: now) }
        var stepsUntilEstimate: Int { estimator.stepsUntilEstimate }

        init(device: IOHIDDevice, name: String, transport: String, productID: Int, serial: String?,
             buffer: UnsafeMutablePointer<UInt8>) {
            self.device = device
            self.name = name
            self.transport = transport
            self.productID = productID
            self.serial = serial
            self.buffer = buffer
        }
    }

    static let vendorID = 0x054C
    static let productIDs = [0x0CE6, 0x0DF2] // DualSense, DualSense Edge
    private static let bufferSize = 128

    var onFrame: ((PadFrame) -> Void)?
    var onControllersChanged: (() -> Void)?
    private(set) var controllers: [Controller] = []

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var lastFullModeRequest: [IOHIDDevice: TimeInterval] = [:]

    @discardableResult
    func start() -> IOReturn {
        let matches = Self.productIDs.map {
            [kIOHIDVendorIDKey: Self.vendorID, kIOHIDProductIDKey: $0] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<DualSenseReader>.fromOpaque(context!).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<DualSenseReader>.fromOpaque(context!).takeUnretainedValue().detach(device)
        }, context)
        // Common modes, so the touchpad keeps working while a menu is open.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        return IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ device: IOHIDDevice) {
        guard !controllers.contains(where: { $0.device == device }) else { return }
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "DualSense"
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "?"
        let productID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        let serial = (IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String)
            .flatMap { $0.isEmpty ? nil : $0.uppercased().replacingOccurrences(of: "-", with: ":") }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.bufferSize)
        controllers.append(Controller(device: device, name: name, transport: transport, productID: productID,
                                      serial: serial, buffer: buffer))
        IOHIDDeviceRegisterInputReportCallback(device, buffer, Self.bufferSize, { context, _, sender, _, _, report, length in
            let reader = Unmanaged<DualSenseReader>.fromOpaque(context!).takeUnretainedValue()
            let device = Unmanaged<IOHIDDevice>.fromOpaque(sender!).takeUnretainedValue()
            reader.handle(report: report, length: length, from: device)
        }, Unmanaged.passUnretained(self).toOpaque())
        requestFullReports(device)
        onControllersChanged?()
    }

    private func detach(_ device: IOHIDDevice) {
        guard let index = controllers.firstIndex(where: { $0.device == device }) else { return }
        controllers.remove(at: index).buffer.deallocate()
        lastFullModeRequest[device] = nil
        onControllersChanged?()
    }

    /// Over Bluetooth the DualSense sends short reports (no touchpad data) until someone reads
    /// feature report 0x05 (calibration); after that it sends full 0x31 reports.
    private func requestFullReports(_ device: IOHIDDevice) {
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastFullModeRequest[device], now - last < 2 { return }
        lastFullModeRequest[device] = now
        var buffer = [UInt8](repeating: 0, count: 64)
        buffer[0] = 0x05
        var length = CFIndex(buffer.count)
        IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 0x05, &buffer, &length)
    }

    private func handle(report: UnsafeMutablePointer<UInt8>, length: Int, from device: IOHIDDevice) {
        // The common input struct starts after the report id (USB 0x01) or id + sequence byte (BT 0x31).
        let base: Int
        if report[0] == 0x01 && length >= 64 {
            base = 1
        } else if report[0] == 0x31 && length >= 78 {
            base = 2
        } else {
            if report[0] == 0x01 { requestFullReports(device) } // Bluetooth simple mode
            return
        }
        if let controller = controllers.first(where: { $0.device == device }) {
            controller.reportCount += 1
            // Status byte: low nibble battery in tenths, high nibble charging state (as in Linux hid-playstation).
            let status = report[base + 52]
            let level = Int(status & 0x0F)
            switch status >> 4 {
            case 0x0: controller.charge = .onBattery; controller.battery = min(level * 10 + 5, 100)
            case 0x1: controller.charge = .charging; controller.battery = min(level * 10 + 5, 100)
            case 0x2: controller.charge = .full; controller.battery = 100
            default: controller.charge = .error; controller.battery = nil
            }
            controller.estimator.record(raw: level, charge: controller.charge, at: ProcessInfo.processInfo.systemUptime)
        }
        let pressed = report[base + 9] & 0x02 != 0 // buttons[2], bit 1: touchpad click
        var touches: [TouchPoint] = []
        for offset in [base + 32, base + 36] {
            let contact = report[offset]
            guard contact & 0x80 == 0 else { continue } // bit 7 set: no finger
            let x = Int(report[offset + 1]) | (Int(report[offset + 2] & 0x0F) << 8)
            let y = Int(report[offset + 2] >> 4) | (Int(report[offset + 3]) << 4)
            touches.append(TouchPoint(id: contact & 0x7F, x: Double(x), y: Double(y)))
        }
        onFrame?(PadFrame(touches: touches, pressed: pressed, time: ProcessInfo.processInfo.systemUptime))
    }
}
