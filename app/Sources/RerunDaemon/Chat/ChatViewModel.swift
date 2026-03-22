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
    private let chatEngine: ChatEngine?

    init(chatEngine: ChatEngine? = nil) {
        self.chatEngine = chatEngine
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        isProcessing = true

        responseTask?.cancel()
        responseTask = Task { @MainActor in
            guard let engine = chatEngine else {
                await Task.yield()
                guard !Task.isCancelled else { return }
                let echo = ChatMessage(role: .assistant, content: "Echo: \(text)")
                messages.append(echo)
                isProcessing = false
                responseTask = nil
                return
            }

            let response = await engine.process(text)

            guard !Task.isCancelled else { return }

            let message = ChatMessage(
                role: .assistant,
                content: response.content,
                sources: response.sources,
                summaryDebug: response.summaryDebug
            )
            messages.append(message)
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
