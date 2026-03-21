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

    // MARK: - Timers & State
    private var captureTimer: Timer?
    private var statsTimer: Timer?
    private var isPaused = false
    private var isCaptureInProgress = false

    // MARK: - Stats
    private var totalCaptures = 0
    private var deduplicatedCount = 0
    private var appSwitchCaptures = 0
    private var timerCaptures = 0

    // MARK: - Constants
    private let captureInterval: TimeInterval = 10.0
    private let idleThreshold: TimeInterval = 30.0
    private let statsInterval: TimeInterval = 300.0

    init(orchestrator: CaptureOrchestrator, db: DatabaseManager, exclusionManager: ExclusionManager) {
        self.orchestrator = orchestrator
        self.db = db
        self.exclusionManager = exclusionManager
    }

    // MARK: - Public API

    func start() async throws {
        try await exclusionManager.loadExclusions()
        logger.info("Starting daemon v\(Rerun.version)")
        logger.info("Accessibility: \(AccessibilityExtractor.isAccessibilityGranted)")
        logger.info("Screen Recording: \(OCRExtractor.isScreenRecordingGranted)")

        observeNotifications()
        startCaptureTimer()
        startStatsTimer()

        logger.info("Daemon started — capturing every \(self.captureInterval)s")
    }

    func stop() {
        captureTimer?.invalidate()
        captureTimer = nil
        statsTimer?.invalidate()
        statsTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        logger.info("Daemon stopped")
    }

    func pause() {
        isPaused = true
        logger.info("Capture paused (manual)")
    }

    func resume() {
        isPaused = false
        logger.info("Capture resumed (manual)")
    }

    // MARK: - Core Capture

    private func performCapture(trigger: String) {
        guard !isCaptureInProgress, !isPaused else { return }

        if isIdle {
            logger.debug("Idle, skipping capture")
            return
        }

        isCaptureInProgress = true

        Task {
            defer { isCaptureInProgress = false }

            // Pre-capture exclusion check (bundle ID only — skip extraction entirely)
            let frontmostBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if await exclusionManager.shouldExcludeApp(bundleId: frontmostBundleId) {
                logger.debug("Excluded app: \(frontmostBundleId ?? "nil")")
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
                logger.info("Captured \(result.appName) via \(result.source.rawValue) [\(trigger)] \(result.text.count) chars")
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
        captureTimer = Timer.scheduledTimer(withTimeInterval: captureInterval, repeats: true) { [weak self] _ in
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
            logger.info("Stats: \(self.totalCaptures) captures (\(self.appSwitchCaptures) app_switch, \(self.timerCaptures) timer), \(self.deduplicatedCount) deduped, \(excluded) excluded")
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
        isPaused = true
        logger.info("Paused: sleep/session inactive")
    }

    @objc private func handleWake() {
        isPaused = false
        logger.info("Resumed: wake/session active")
    }
}
