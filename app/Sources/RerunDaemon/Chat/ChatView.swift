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
        .background(.clear)
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
            Image(systemName: "text.bubble")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
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

                    if viewModel.isProcessing {
                        TypingIndicatorBubble()
                            .id("typing")
                            .transition(.opacity)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.messages.last?.content) {
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: viewModel.isProcessing) {
                if viewModel.isProcessing {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if let last = viewModel.messages.last {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var modelReady: Bool {
        if case .ready = viewModel.modelState { return true }
        return false
    }

    private var inputPlaceholder: String {
        switch viewModel.modelState {
        case .idle:
            return "Preparing AI model\u{2026}"
        case .downloading(let progress):
            let pct = Int(progress * 100)
            return "Downloading AI model\u{2026} \(pct)%"
        case .ready:
            return "Ask anything..."
        case .failed:
            return "AI model download failed"
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(inputPlaceholder, text: $viewModel.inputText)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .onSubmit { viewModel.send() }
                .disabled(!modelReady || viewModel.isProcessing || viewModel.isStreaming)

            if viewModel.isProcessing || viewModel.isStreaming {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
