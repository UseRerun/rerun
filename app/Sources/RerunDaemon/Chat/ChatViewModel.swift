import SwiftUI
import os

private let logger = Logger(subsystem: "com.rerun", category: "ChatViewModel")

@Observable
@MainActor
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isProcessing: Bool = false
    var isStreaming: Bool = false
    private var responseTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private let responseProvider: (@Sendable (String) async -> ChatStreamResponse)?

    init(chatEngine: ChatEngine? = nil) {
        if let chatEngine {
            self.responseProvider = { text in
                await chatEngine.processStreaming(text)
            }
        } else {
            self.responseProvider = nil
        }
    }

    init(responseProvider: @escaping @Sendable (String) async -> ChatStreamResponse) {
        self.responseProvider = responseProvider
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessing, !isStreaming else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        inputText = ""
        isProcessing = true

        responseTask?.cancel()
        let requestID = UUID()
        activeRequestID = requestID
        responseTask = Task { @MainActor in
            guard let responseProvider else {
                await Task.yield()
                guard !Task.isCancelled, activeRequestID == requestID else { return }
                let echo = ChatMessage(role: .assistant, content: "Echo: \(text)")
                messages.append(echo)
                isProcessing = false
                finishRequestIfCurrent(requestID)
                return
            }

            let streamResponse = await responseProvider(text)

            guard !Task.isCancelled, activeRequestID == requestID else { return }

            // Append assistant message with sources immediately
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: streamResponse.fallbackContent ?? "",
                sources: streamResponse.sources,
                summaryDebug: streamResponse.summaryDebug
            )
            messages.append(assistantMessage)
            isProcessing = false

            // If we have a token stream, consume it
            if let tokenStream = streamResponse.tokenStream {
                isStreaming = true
                let assistantMessageID = assistantMessage.id
                var accumulated = ""

                do {
                    for try await token in tokenStream {
                        guard !Task.isCancelled, activeRequestID == requestID else { break }
                        accumulated.append(token)
                        guard updateMessage(id: assistantMessageID, content: accumulated) else { break }
                    }
                } catch {
                    logger.error("Streaming failed: \(error.localizedDescription)")
                    if accumulated.isEmpty {
                        _ = updateMessage(
                            id: assistantMessageID,
                            content: streamResponse.recoveryContent ?? "Something went wrong generating a response."
                        )
                    }
                }

                // Trim final content
                if !accumulated.isEmpty {
                    _ = updateMessage(
                        id: assistantMessageID,
                        content: accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }

                if activeRequestID == requestID {
                    isStreaming = false
                }
            }

            finishRequestIfCurrent(requestID)
        }
    }

    func newConversation() {
        responseTask?.cancel()
        responseTask = nil
        activeRequestID = nil
        messages.removeAll()
        inputText = ""
        isProcessing = false
        isStreaming = false
    }

    @discardableResult
    private func updateMessage(id: UUID, content: String) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return false
        }
        messages[index].content = content
        return true
    }

    private func finishRequestIfCurrent(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil
        responseTask = nil
    }
}
