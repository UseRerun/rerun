import Testing
@testable import RerunDaemon

@Suite("ChatViewModel")
struct ChatViewModelTests {
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
}
