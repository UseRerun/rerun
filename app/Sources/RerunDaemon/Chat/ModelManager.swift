import Foundation
import MLXLLM
import MLXLMCommon
import Hub
import os
import RerunCore

private let logger = Logger(subsystem: "com.rerun", category: "ModelManager")

/// Manages the LLM model lifecycle: download, load, and retry.
/// Downloads from Hugging Face on launch, resumes interrupted downloads automatically.
/// Model stored in ~/Library/Application Support/Rerun/models/
actor ModelManager {

    enum ModelState: Sendable {
        case idle
        case downloading(progress: Double)
        case ready
        case failed(message: String)
    }

    /// Observable state for UI (menu bar, chat). MainActor-isolated so SwiftUI/AppKit can read directly.
    @MainActor private(set) var state: ModelState = .idle {
        didSet { onStateChange?(state) }
    }

    /// Callback fired on MainActor whenever state changes. Used by ChatViewModel for reactive updates.
    @MainActor var onStateChange: ((ModelState) -> Void)?

    private let modelId = "mlx-community/phi-4-4bit"
    private var container: ModelContainer?
    private var isLoading = false

    private var modelsDirectory: URL {
        RerunHome.appSupportURL().appendingPathComponent("models")
    }

    /// Kick off model download in background. Safe to call multiple times.
    func startDownload() {
        guard !isLoading, container == nil else { return }
        isLoading = true
        Task {
            do {
                _ = try await loadModel()
            } catch {
                // Error already logged and state set in loadModel
            }
            isLoading = false
        }
    }

    /// Returns container if already loaded. Non-blocking — returns nil if still downloading.
    func getContainerIfReady() -> ModelContainer? {
        container
    }

    /// Retry after failure. Resets state and starts fresh download.
    func retry() {
        container = nil
        isLoading = false
        startDownload()
    }

    private func loadModel() async throws -> ModelContainer {
        if let container { return container }

        await MainActor.run { state = .downloading(progress: 0) }

        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

            let hub = HubApi(downloadBase: modelsDirectory)
            let config = ModelConfiguration(id: modelId)

            logger.notice("Loading model \(self.modelId)...")
            let loaded = try await LLMModelFactory.shared.loadContainer(
                hub: hub,
                configuration: config
            ) { progress in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.state = .downloading(progress: progress.fractionCompleted)
                }
            }

            self.container = loaded
            await MainActor.run { state = .ready }
            logger.notice("Model ready")
            return loaded
        } catch {
            await MainActor.run { state = .failed(message: error.localizedDescription) }
            logger.error("Model download failed: \(error.localizedDescription)")
            throw error
        }
    }
}
