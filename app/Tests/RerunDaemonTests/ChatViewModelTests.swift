import Testing
@testable import RerunDaemon

@Suite("ChatViewModel")
struct ChatViewModelTests {
    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() && ContinuousClock.now < deadline {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    @MainActor
    @Test func newConversationClearsPendingReply() async throws {
        let viewModel = ChatViewModel()
        viewModel.inputText = "stripe endpoint"
        viewModel.send()

        #expect(viewModel.messages.count == 1)
        #expect(viewModel.isProcessing)

        viewModel.newConversation()

        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.inputText.isEmpty)
        #expect(viewModel.isProcessing == false)

        try await Task.sleep(for: .milliseconds(350))

        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.isProcessing == false)
    }

    @MainActor
    @Test func newConversationDuringStreamingIgnoresLateTokens() async throws {
        var continuation: AsyncThrowingStream<String, Error>.Continuation?
        let stream = AsyncThrowingStream<String, Error> { continuation = $0 }
        let viewModel = ChatViewModel(responseProvider: { _ in
            ChatStreamResponse(
                sources: [],
                summaryDebug: nil,
                fallbackContent: nil,
                recoveryContent: "Recovered summary",
                tokenStream: stream
            )
        })

        viewModel.inputText = "What was I doing?"
        viewModel.send()

        try await waitUntil {
            viewModel.isStreaming && viewModel.messages.count == 2
        }

        continuation?.yield("Hello")
        try await waitUntil {
            viewModel.messages.last?.content == "Hello"
        }

        viewModel.newConversation()
        continuation?.yield(" world")
        continuation?.finish()

        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.isProcessing == false)
        #expect(viewModel.isStreaming == false)
    }

    @MainActor
    @Test func streamFailureUsesRecoveryContent() async throws {
        struct StreamFailure: Error {}

        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.finish(throwing: StreamFailure())
        }
        let viewModel = ChatViewModel(responseProvider: { _ in
            ChatStreamResponse(
                sources: [],
                summaryDebug: nil,
                fallbackContent: nil,
                recoveryContent: "Recovered summary",
                tokenStream: stream
            )
        })

        viewModel.inputText = "What was I doing?"
        viewModel.send()

        try await waitUntil {
            viewModel.messages.count == 2 && viewModel.isProcessing == false && viewModel.isStreaming == false
        }

        #expect(viewModel.messages.last?.content == "Recovered summary")
    }
}
