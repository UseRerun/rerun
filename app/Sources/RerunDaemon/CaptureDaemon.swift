import Foundation
import AppKit
import CryptoKit
import os
import RerunCore

@MainActor
final class CaptureDaemon {
    // MARK: - Dependencies
    private let orchestrator: CaptureOrchestrator
    private let db: DatabaseManager
    private let exclusionManager: ExclusionManager
    private let logger = Logger(subsystem: "com.rerun", category: "CaptureDaemon")

    // MARK: - Monitors
    private let powerMonitor = PowerMonitor()
    private let thermalMonitor = ThermalMonitor()

    // MARK: - Timers & State
    private var captureTimer: Timer?
    private var statsTimer: Timer?
    private var todayMdTimer: Timer?
    private var indexMdTimer: Timer?
    private var pauseState = CapturePauseState()
    private var isCaptureInProgress = false

    // MARK: - Stats
    private var totalCaptures = 0
    private var deduplicatedCount = 0
    private var appSwitchCaptures = 0
    private var timerCaptures = 0
    private var accessibilityCaptures = 0
    private var ocrCaptures = 0
    private var startTime = Date()

    // MARK: - Constants
    private let baseCaptureInterval: TimeInterval = 10.0
    private var currentCaptureInterval: TimeInterval = 10.0
    private let idleThreshold: TimeInterval = 30.0
    private let statsInterval: TimeInterval = 300.0
    private let todayMdInterval: TimeInterval = 1800.0   // 30 min
    private let indexMdInterval: TimeInterval = 3600.0    // 1 hour

    init(orchestrator: CaptureOrchestrator, db: DatabaseManager, exclusionManager: ExclusionManager) {
        self.orchestrator = orchestrator
        self.db = db
        self.exclusionManager = exclusionManager
    }

    // MARK: - Public API

    func start() async throws {
        try await exclusionManager.loadExclusions()
        startTime = Date()
        logger.info("Starting daemon v\(Rerun.version)")
        logger.info("Accessibility: \(AccessibilityExtractor.isAccessibilityGranted)")
        logger.info("Screen Recording: \(OCRExtractor.isScreenRecordingGranted)")

        powerMonitor.onStateChange = { [weak self] _ in self?.updateCaptureInterval() }
        thermalMonitor.onStateChange = { [weak self] _ in self?.updateCaptureInterval() }
        powerMonitor.start()
        thermalMonitor.start()

        observeNotifications()
        startCaptureTimer()
        startStatsTimer()
        generateAgentFiles()
        startAgentFileTimers()

        logger.info("Daemon started — capturing every \(self.currentCaptureInterval)s")
    }

    func stop() {
        captureTimer?.invalidate()
        captureTimer = nil
        statsTimer?.invalidate()
        statsTimer = nil
        todayMdTimer?.invalidate()
        todayMdTimer = nil
        indexMdTimer?.invalidate()
        indexMdTimer = nil
        powerMonitor.stop()
        thermalMonitor.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.info("Daemon stopped")
    }

    func pause() {
        pauseState.pauseManual()
        logger.info("Capture paused (manual)")
    }

    func resume() {
        pauseState.resumeManual()
        logger.info("Capture resumed (manual)")
    }

    // MARK: - Core Capture

    private func performCapture(trigger: String) {
        guard !isCaptureInProgress, !pauseState.isPaused else { return }
        guard !FileManager.default.fileExists(atPath: RerunHome.pauseFileURL().path) else { return }
        guard thermalMonitor.thermalState != .critical else {
            logger.debug("Thermal critical, skipping capture")
            return
        }

        if isIdle {
            logger.debug("Idle, skipping capture")
            return
        }

        isCaptureInProgress = true

        Task {
            defer { isCaptureInProgress = false }

            do {
                try await exclusionManager.refresh()
            } catch {
                logger.error("Failed to refresh exclusions: \(error.localizedDescription)")
                return
            }

            // Pre-capture exclusion check (bundle ID only — skip extraction entirely)
            let frontmostBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if await exclusionManager.shouldExcludeApp(bundleId: frontmostBundleId) {
                logger.debug("Excluded app: \(frontmostBundleId ?? "nil")")
                return
            }

            if !AccessibilityExtractor.isAccessibilityGranted,
               DefaultExclusions.requiresAccessibilityMetadata(bundleId: frontmostBundleId) {
                logger.warning("Skipping browser capture without Accessibility metadata: \(frontmostBundleId ?? "nil")")
                return
            }

            guard let result = await orchestrator.capture() else {
                logger.debug("No capture result")
                return
            }

            // Post-capture exclusion check (URL, private browsing windows)
            if await exclusionManager.shouldExclude(bundleId: result.bundleId, url: result.url, windowTitle: result.windowTitle) {
                logger.debug("Excluded after capture: \(result.appName)")
                return
            }

            // SHA-256 dedup
            let hashDigest = SHA256.hash(data: Data(result.text.utf8))
            let hash = hashDigest.map { String(format: "%02x", $0) }.joined()

            let latestHash = try? await db.latestHashForApp(result.appName)
            if latestHash == hash {
                deduplicatedCount += 1
                logger.debug("Dedup: skipped \(result.appName)")
                return
            }

            // Build and store capture
            let now = ISO8601DateFormatter().string(from: Date())
            var capture = Capture(
                timestamp: now,
                appName: result.appName,
                bundleId: result.bundleId,
                windowTitle: result.windowTitle,
                url: result.url,
                textSource: result.source.rawValue,
                captureTrigger: trigger,
                textContent: result.text,
                textHash: hash
            )

            // Write markdown file
            do {
                let writer = MarkdownWriter()
                capture.markdownPath = try writer.write(capture)
            } catch {
                logger.error("Markdown write failed; capture skipped: \(error.localizedDescription)")
                return
            }

            do {
                try await db.insertCapture(capture)
                totalCaptures += 1
                if trigger == "app_switch" {
                    appSwitchCaptures += 1
                } else {
                    timerCaptures += 1
                }
                if result.source == .accessibility {
                    accessibilityCaptures += 1
                } else {
                    ocrCaptures += 1
                }
                logger.info("Captured \(result.appName) via \(result.source.rawValue) [\(trigger)] \(result.text.count) chars")

                // Generate embedding async, non-blocking
                if EmbeddingGenerator.isAvailable {
                    let captureId = capture.id
                    let text = capture.textContent
                    let database = db
                    Task.detached {
                        let generator = EmbeddingGenerator()
                        if let embedding = generator.embed(text) {
                            try? await database.insertEmbedding(captureId: captureId, embedding: embedding)
                        }
                    }
                }
            } catch {
                logger.error("SQLite index insert failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Idle Detection

    private var isIdle: Bool {
        let mouse = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let key = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let click = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
        return min(mouse, key, click) > idleThreshold
    }

    // MARK: - Timers

    private func startCaptureTimer() {
        captureTimer?.invalidate()
        captureTimer = Timer.scheduledTimer(withTimeInterval: currentCaptureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performCapture(trigger: "timer")
            }
        }
    }

    private func startStatsTimer() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: statsInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.logStats()
            }
        }
    }

    private func logStats() {
        Task {
            let excluded = await exclusionManager.excludedCount

            // Dedup rate
            let totalAttempts = totalCaptures + deduplicatedCount
            let dedupRate = totalAttempts > 0 ? Int(Double(deduplicatedCount) / Double(totalAttempts) * 100) : 0

            // Captures per hour
            let uptime = Date().timeIntervalSince(startTime)
            let perHour = uptime > 0 ? Double(totalCaptures) / (uptime / 3600) : 0

            // Storage sizes
            let dbSize = Self.fileSize(atPath: (try? DatabaseManager.defaultPath()) ?? "")
            let capturesSize = Self.directorySize(at: RerunHome.capturesURL())

            logger.info("Stats: \(self.totalCaptures) captures (\(self.appSwitchCaptures) app_switch, \(self.timerCaptures) timer | \(self.accessibilityCaptures) a11y, \(self.ocrCaptures) ocr), \(self.deduplicatedCount) deduped (\(dedupRate)%), \(excluded) excluded | \(String(format: "%.1f", perHour))/hr | db \(Self.formatBytes(dbSize)) captures \(Self.formatBytes(capturesSize)) | power: \(self.powerMonitor.state.rawValue) thermal: \(self.thermalMonitor.thermalState.rawValue)")
        }
    }

    // MARK: - Adaptive Interval

    private func updateCaptureInterval() {
        let powerMultiplier: TimeInterval = switch powerMonitor.state {
        case .ac: 1.0
        case .battery: 3.0
        case .lowPower: 6.0
        }

        let thermalMultiplier: TimeInterval = switch thermalMonitor.thermalState {
        case .nominal, .fair: 1.0
        case .serious: 3.0
        case .critical: 1.0  // doesn't matter — performCapture skips on critical
        @unknown default: 1.0
        }

        let newInterval = baseCaptureInterval * max(powerMultiplier, thermalMultiplier)
        if newInterval != currentCaptureInterval {
            currentCaptureInterval = newInterval
            startCaptureTimer()
            logger.info("Capture interval adjusted to \(newInterval)s (power: \(self.powerMonitor.state.rawValue), thermal: \(self.thermalMonitor.thermalState.rawValue))")
        }
    }

    // MARK: - Size Helpers

    private static func fileSize(atPath path: String) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return size
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0fKB", kb) }
        let mb = kb / 1024
        return String(format: "%.1fMB", mb)
    }

    // MARK: - Agent Files

    private func startAgentFileTimers() {
        todayMdTimer = Timer.scheduledTimer(withTimeInterval: todayMdInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.generateTodayMd()
            }
        }
        indexMdTimer = Timer.scheduledTimer(withTimeInterval: indexMdInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.generateIndexMd()
            }
        }
    }

    private func generateAgentFiles() {
        let database = db
        Task.detached {
            let gen = AgentFileGenerator()
            try? await gen.generateTodayMd(db: database)
            try? await gen.generateIndexMd(db: database)
        }
    }

    private func generateTodayMd() {
        let database = db
        Task.detached {
            try? await AgentFileGenerator().generateTodayMd(db: database)
        }
    }

    private func generateIndexMd() {
        let database = db
        Task.detached {
            try? await AgentFileGenerator().generateIndexMd(db: database)
        }
    }

    // MARK: - Notification Observers

    private func observeNotifications() {
        let ws = NSWorkspace.shared.notificationCenter

        ws.addObserver(
            self, selector: #selector(handleAppSwitch(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        ws.addObserver(
            self, selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification, object: nil
        )
        ws.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        ws.addObserver(
            self, selector: #selector(handleSleep),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil
        )
        ws.addObserver(
            self, selector: #selector(handleWake),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil
        )
    }

    @objc private func handleAppSwitch(_ notification: Notification) {
        performCapture(trigger: "app_switch")
        startCaptureTimer()
    }

    @objc private func handleSleep() {
        pauseState.pauseSystem()
        logger.info("Paused: sleep/session inactive")
    }

    @objc private func handleWake() {
        pauseState.resumeSystem()
        if pauseState.isPaused {
            logger.info("Wake/session active; manual pause still enabled")
        } else {
            logger.info("Resumed: wake/session active")
        }
    }
}
