import RerunCore
import Foundation
import AppKit

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

// MARK: - Daemon Startup

let db: DatabaseManager
do {
    let path = try DatabaseManager.defaultPath()
    db = try DatabaseManager(path: path)
} catch {
    fputs("Failed to initialize database: \(error.localizedDescription)\n", stderr)
    exit(1)
}

let orchestrator = CaptureOrchestrator()
let daemon = CaptureDaemon(orchestrator: orchestrator, db: db)

print("Rerun daemon v\(Rerun.version) starting...")
daemon.start()

RunLoop.main.run()
