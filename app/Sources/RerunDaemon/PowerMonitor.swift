import Foundation
import IOKit.ps
import os

@MainActor
final class PowerMonitor {
    enum PowerState: String, Sendable {
        case ac, battery, lowPower
    }

    private(set) var state: PowerState = .ac
    var onStateChange: ((PowerState) -> Void)?
    private var timer: Timer?
    private let logger = Logger(subsystem: "com.rerun", category: "PowerMonitor")

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        logger.info("PowerMonitor started — state: \(self.state.rawValue)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let newState = detectPowerState()
        if newState != state {
            let old = state
            state = newState
            logger.info("Power state changed: \(old.rawValue) → \(newState.rawValue)")
            onStateChange?(newState)
        }
    }

    private func detectPowerState() -> PowerState {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return .lowPower
        }

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              let first = sources.first else {
            return .ac
        }

        let desc = IOPSGetPowerSourceDescription(snapshot, first as CFTypeRef)?.takeUnretainedValue() as? [String: Any]
        if let powerSource = desc?[kIOPSPowerSourceStateKey] as? String,
           powerSource == kIOPSBatteryPowerValue {
            return .battery
        }

        return .ac
    }
}
