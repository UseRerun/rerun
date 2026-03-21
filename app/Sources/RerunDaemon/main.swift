import RerunCore
import Foundation
import AppKit
import Dispatch
import ServiceManagement

// Quick AX diagnostic if --test-ax flag is passed
if CommandLine.arguments.contains("--test-ax") {
    print("Accessibility granted: \(AccessibilityExtractor.isAccessibilityGranted)")

    let extractor = AccessibilityExtractor()
    if let result = extractor.extract() {
        print("App: \(result.appName)")
        print("Bundle ID: \(result.bundleId ?? "nil")")
        print("Window: \(result.windowTitle ?? "nil")")
        print("URL: \(result.url ?? "nil")")
        print("Source: \(result.source.rawValue)")
        print("Needs OCR: \(result.needsOCRFallback)")
        print("Text length: \(result.text.count) chars")
        if !result.text.isEmpty {
            print("Text preview: \(String(result.text.prefix(500)))")
        }
    } else {
        print("No result (no focused window or no permission)")
    }
    exit(0)
}

// Quick OCR diagnostic if --test-ocr flag is passed
if CommandLine.arguments.contains("--test-ocr") {
    print("Screen Recording granted: \(OCRExtractor.isScreenRecordingGranted)")

    Task {
        let extractor = OCRExtractor()
        if let result = await extractor.extract() {
            print("App: \(result.appName)")
            print("Bundle ID: \(result.bundleId ?? "nil")")
            print("Source: \(result.source.rawValue)")
            print("Text length: \(result.text.count) chars")
            if !result.text.isEmpty {
                print("Text preview: \(String(result.text.prefix(500)))")
            }
        } else {
            print("No result (no permission, no window, or OCR found no text)")
        }
        exit(0)
    }
    RunLoop.main.run()
}

// Full capture pipeline diagnostic if --test-capture flag is passed
if CommandLine.arguments.contains("--test-capture") {
    print("Accessibility granted: \(AccessibilityExtractor.isAccessibilityGranted)")
    print("Screen Recording granted: \(OCRExtractor.isScreenRecordingGranted)")

    Task {
        let orchestrator = CaptureOrchestrator()
        if let result = await orchestrator.capture() {
            print("App: \(result.appName)")
            print("Bundle ID: \(result.bundleId ?? "nil")")
            print("Window: \(result.windowTitle ?? "nil")")
            print("URL: \(result.url ?? "nil")")
            print("Source: \(result.source.rawValue)")
            print("Text length: \(result.text.count) chars")
            if !result.text.isEmpty {
                print("Text preview: \(String(result.text.prefix(500)))")
            }
        } else {
            print("No result from either AX or OCR")
        }
        exit(0)
    }
    RunLoop.main.run()
}

// Embedding diagnostic if --test-embed flag is passed
if CommandLine.arguments.contains("--test-embed") {
    print("NLContextualEmbedding available: \(EmbeddingGenerator.isAvailable)")

    Task {
        let orchestrator = CaptureOrchestrator()
        guard let result = await orchestrator.capture() else {
            print("No capture result — cannot test embedding")
            exit(1)
        }
        print("Captured \(result.text.count) chars from \(result.appName)")

        let generator = EmbeddingGenerator()
        let start = CFAbsoluteTimeGetCurrent()
        if let embedding = generator.embed(result.text) {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            print("Embedding dimension: \(embedding.count)")
            print("Generation time: \(String(format: "%.0f", elapsed))ms")
            print("First 5 values: \(embedding.prefix(5).map { String(format: "%.4f", $0) })")
            print("Non-zero values: \(embedding.filter { $0 != 0 }.count)/\(embedding.count)")

            // Test round-trip through sqlite-vec
            let path = NSTemporaryDirectory() + "rerun-embed-test-\(UUID().uuidString).db"
            do {
                let db = try DatabaseManager(path: path)
                let capture = Capture(
                    timestamp: ISO8601DateFormatter().string(from: Date()),
                    appName: result.appName,
                    textSource: result.source.rawValue,
                    captureTrigger: "test",
                    textContent: result.text,
                    textHash: "test"
                )
                try await db.insertCapture(capture)
                try await db.insertEmbedding(captureId: capture.id, embedding: embedding)
                let similar = try await db.findSimilar(to: embedding, limit: 1)
                print("sqlite-vec round-trip: \(similar.count == 1 ? "OK" : "FAILED") (distance: \(similar.first?.distance ?? -1))")
            } catch {
                print("sqlite-vec round-trip FAILED: \(error)")
            }
            try? FileManager.default.removeItem(atPath: path)
        } else {
            print("Embedding generation returned nil")
        }
        exit(0)
    }
    RunLoop.main.run()
}

// MARK: - Daemon Startup

let profile = RerunProfile.current()
let db: DatabaseManager
do {
    let path = try DatabaseManager.defaultPath(profile: profile)
    db = try DatabaseManager(path: path)
} catch {
    fputs("Failed to initialize database: \(error.localizedDescription)\n", stderr)
    exit(1)
}

let orchestrator = CaptureOrchestrator()
let exclusionManager = ExclusionManager(db: db)
let daemon = CaptureDaemon(orchestrator: orchestrator, db: db, exclusionManager: exclusionManager)

// Write PID file
let pidURL = RerunHome.pidFileURL()
let pidDir = pidURL.deletingLastPathComponent()
try? FileManager.default.createDirectory(at: pidDir, withIntermediateDirectories: true)
try? "\(ProcessInfo.processInfo.processIdentifier)".write(to: pidURL, atomically: true, encoding: .utf8)

// Signal handling for graceful shutdown
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)

let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)

let shutdown: @MainActor () -> Void = {
    daemon.stop()
    try? FileManager.default.removeItem(at: RerunHome.pidFileURL())
    exit(0)
}

sigterm.setEventHandler {
    MainActor.assumeIsolated { shutdown() }
}
sigint.setEventHandler {
    MainActor.assumeIsolated { shutdown() }
}
sigterm.resume()
sigint.resume()

print("Rerun daemon v\(Rerun.version) starting [profile: \(profile)]...")
Task { @MainActor in
    do {
        try await daemon.start()
    } catch {
        fputs("Failed to start daemon: \(error.localizedDescription)\n", stderr)
        try? FileManager.default.removeItem(at: RerunHome.pidFileURL())
        exit(1)
    }
}

if let appVariant = RerunAppVariant.variant(bundleIdentifier: Bundle.main.bundleIdentifier) {
    if appVariant == .production {
        // Running inside production .app bundle — register as login item for auto-start
        let service = SMAppService.mainApp
        if service.status != .enabled {
            do {
                try service.register()
                print("Registered as login item")
            } catch {
                fputs("Login item registration failed: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    // Use NSApplication for proper macOS app identity (no Dock icon)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    // Prompt for permissions if not yet granted
    AccessibilityExtractor.requestAccessibilityIfNeeded()
    OCRExtractor.requestScreenRecordingIfNeeded()

    // Menu bar status item
    let statusBar = StatusBarController()
    statusBar.setup(daemon: daemon)

    // Chat panel + global hotkey
    let chatPanel = ChatPanel()
    statusBar.setChatPanel(chatPanel)

    let hotkeyManager = HotkeyManager { chatPanel.toggle() }
    hotkeyManager.start()

    app.run()
} else {
    // Running as bare binary (development / diagnostics)
    RunLoop.main.run()
}
