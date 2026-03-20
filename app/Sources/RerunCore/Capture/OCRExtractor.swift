import ScreenCaptureKit
import Vision
import AppKit
import os

/// Extracts text from the focused window using ScreenCaptureKit screenshot + Vision OCR.
///
/// Fallback capture mechanism — used when Accessibility API returns insufficient text.
/// The screenshot is captured and discarded after OCR; it is never persisted.
public final class OCRExtractor: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.rerun", category: "OCRExtractor")

    /// Minimum confidence for OCR text recognition results.
    private let minimumConfidence: Float

    public init(minimumConfidence: Float = 0.3) {
        self.minimumConfidence = minimumConfidence
    }

    // MARK: - Permission

    /// Check if Screen Recording permission is granted.
    public static var isScreenRecordingGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Request Screen Recording permission (shows system prompt if not yet granted).
    @discardableResult
    public static func requestScreenRecordingIfNeeded() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Public API

    /// Extract text from the currently focused window via screenshot + OCR.
    ///
    /// Returns `nil` if no focused window, no permission, or OCR produces no text.
    public func extract() async -> CaptureResult? {
        let start = CFAbsoluteTimeGetCurrent()

        guard Self.isScreenRecordingGranted else {
            Self.logger.warning("Screen Recording permission not granted")
            return nil
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = frontApp.localizedName ?? "Unknown"
        let bundleId = frontApp.bundleIdentifier
        let pid = frontApp.processIdentifier

        guard let image = await captureWindow(pid: pid) else { return nil }

        let text = recognizeText(in: image)
        // image goes out of scope here — never persisted

        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Self.logger.info("OCR completed in \(elapsedMs)ms, \(text.count) chars")

        guard !text.isEmpty else { return nil }

        return CaptureResult(
            text: text,
            appName: appName,
            bundleId: bundleId,
            source: .ocr
        )
    }

    // MARK: - Screenshot

    private func captureWindow(pid: pid_t) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            let window = content.windows.first { window in
                window.owningApplication?.processID == pid &&
                window.isOnScreen &&
                window.windowLayer == 0 &&
                window.frame.width > 0 &&
                window.frame.height > 0
            }

            guard let targetWindow = window else {
                Self.logger.debug("No visible window found for PID \(pid)")
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
            let config = SCStreamConfiguration()
            let scale = Int(NSScreen.main?.backingScaleFactor ?? 2.0)
            config.width = Int(targetWindow.frame.width) * scale
            config.height = Int(targetWindow.frame.height) * scale
            config.showsCursor = false

            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            Self.logger.error("Screenshot capture failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - OCR

    private func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image)

        do {
            try handler.perform([request])
        } catch {
            Self.logger.error("OCR failed: \(error.localizedDescription)")
            return ""
        }

        guard let observations = request.results else { return "" }

        let minConf = self.minimumConfidence
        return observations
            .compactMap { observation -> String? in
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= minConf else { return nil }
                return candidate.string
            }
            .joined(separator: "\n")
    }
}
