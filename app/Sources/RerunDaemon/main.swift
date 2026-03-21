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

let db: DatabaseManager
do {
    let path = try DatabaseManager.defaultPath()
    db = try DatabaseManager(path: path)
} catch {
    fputs("Failed to initialize database: \(error.localizedDescription)\n", stderr)
    exit(1)
}

let orchestrator = CaptureOrchestrator()
let exclusionManager = ExclusionManager(db: db)
let daemon = CaptureDaemon(orchestrator: orchestrator, db: db, exclusionManager: exclusionManager)

print("Rerun daemon v\(Rerun.version) starting...")
Task { @MainActor in
    do {
        try await daemon.start()
    } catch {
        fputs("Failed to start daemon: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

RunLoop.main.run()
