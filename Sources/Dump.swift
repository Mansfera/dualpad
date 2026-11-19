import Foundation
import IOKit.hid

/// `DualPad --dump`: prints touchpad frames when they change, for checking the HID side alone.
enum Dump {
    static func run() {
        let reader = DualSenseReader()
        var last = ""
        reader.onControllersChanged = {
            print("controllers:", reader.controllers.map { "\($0.name) (\($0.transport))" })
        }
        reader.onFrame = { frame in
            let touches = frame.touches.map { "#\($0.id) \(Int($0.x)),\(Int($0.y))" }.joined(separator: "  ")
            let line = "pressed=\(frame.pressed ? 1 : 0)  \(touches)"
            if CommandLine.arguments.contains("--status"), let c = reader.controllers.first, c.reportCount % 250 == 1 {
                print("\(c.model) serial=\(c.serial ?? "-") battery=\(c.battery.map(String.init) ?? "-") charge=\(c.charge) reports=\(c.reportCount)")
            }
            if line != last {
                print(String(format: "%.3f ", frame.time) + line)
                last = line
            }
        }
        let result = reader.start()
        print("IOHIDManagerOpen:", result == kIOReturnSuccess ? "ok" : String(format: "0x%08x", result))
        setvbuf(stdout, nil, _IOLBF, 0)
        RunLoop.main.run()
    }
}
