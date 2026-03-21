import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.messages.isEmpty {
                emptyState
            } else {
                messageList
            }
            Divider()
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatPanelDidShow)) { _ in
            isInputFocused = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Rerun Chat")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Ask about anything you've seen on your screen")
                .font(.body)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask anything...", text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .onSubmit { viewModel.send() }
                .disabled(viewModel.isProcessing)

            if viewModel.isProcessing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
