import Foundation
import os

@MainActor
final class ThermalMonitor {
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal
    var onStateChange: ((ProcessInfo.ThermalState) -> Void)?
    private var observer: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.rerun", category: "ThermalMonitor")

    func start() {
        thermalState = ProcessInfo.processInfo.thermalState
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleChange()
            }
        }
        logger.info("ThermalMonitor started — state: \(self.thermalState.rawValue)")
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    private func handleChange() {
        let newState = ProcessInfo.processInfo.thermalState
        if newState != thermalState {
            let old = thermalState
            thermalState = newState
            logger.info("Thermal state changed: \(old.rawValue) → \(newState.rawValue)")
            onStateChange?(newState)
        }
    }
}
