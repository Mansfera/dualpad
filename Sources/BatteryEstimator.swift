import Foundation

/// Time left for the controller battery. The controller reports its level in tenths only, so this
/// watches for the moments it crosses a 10% boundary and works out the rate between them.
struct BatteryEstimator {
    typealias Charge = DualSenseReader.Charge

    /// Moments the level crossed a 10% boundary while the charging state stayed the same.
    /// The first entry is only a starting point: it's not known where inside its step the level was.
    private(set) var steps: [(time: TimeInterval, percent: Int)] = []
    private(set) var stepsCharge = Charge.unknown

    /// The controller reports its level in tenths only, so a rate needs two boundary crossings
    /// (about 20% of use). Before that, nil.
    struct Estimate {
        /// Seconds until empty (or until full while charging), at the rate seen so far.
        let seconds: TimeInterval
        let toFull: Bool
        /// How long 0–100% lasts at that rate; only while on battery.
        let fullChargeRuntime: TimeInterval?
    }

    /// How many more 10% steps are needed before there's an estimate.
    var stepsUntilEstimate: Int { max(0, 3 - steps.count) }

    mutating func record(raw: Int, charge: Charge, at time: TimeInterval) {
        if charge != stepsCharge {
            steps = []
            stepsCharge = charge
        }
        switch charge {
        case .onBattery:
            // Moving down from raw+1 to raw means it just passed (raw+1) × 10%. Ignore flicker back up.
            let percent = (raw + 1) * 10
            if let last = steps.last, percent >= last.percent { return }
            steps.append((time, percent))
        case .charging:
            let percent = raw * 10
            if let last = steps.last, percent <= last.percent { return }
            steps.append((time, percent))
        default:
            break
        }
    }

    func estimate(now: TimeInterval) -> Estimate? {
        let crossings = steps.dropFirst()
        guard crossings.count >= 2, let first = crossings.first, let last = crossings.last,
              last.time > first.time else { return nil }
        let rate = Double(abs(last.percent - first.percent)) / (last.time - first.time) // % per second
        guard rate > 0 else { return nil }
        let elapsed = now - last.time
        switch stepsCharge {
        case .onBattery:
            // Somewhere inside the current step, never below its floor (the controller would have said so).
            let level = max(Double(last.percent) - rate * elapsed, Double(last.percent - 10))
            return Estimate(seconds: level / rate, toFull: false, fullChargeRuntime: 100 / rate)
        case .charging:
            let level = min(Double(last.percent) + rate * elapsed, Double(last.percent + 10))
            return Estimate(seconds: (100 - level) / rate, toFull: true, fullChargeRuntime: nil)
        default:
            return nil
        }
    }
}
