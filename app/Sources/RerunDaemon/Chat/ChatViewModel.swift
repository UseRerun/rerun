import SwiftUI
import os

private let logger = Logger(subsystem: "com.rerun", category: "ChatViewModel")

@Observable
@MainActor
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isProcessing: Bool = false
    private var responseTask: Task<Void, Never>?

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        isProcessing = true

        responseTask?.cancel()
        responseTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            let echo = ChatMessage(role: .assistant, content: "Echo: \(text)")
            messages.append(echo)
            isProcessing = false
            responseTask = nil
        }
    }

    func newConversation() {
        responseTask?.cancel()
        responseTask = nil
        messages.removeAll()
        inputText = ""
        isProcessing = false
    }
}
