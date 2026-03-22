import SwiftUI
import AppKit

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                messageBody

                if message.role == .assistant && !message.sources.isEmpty {
                    SourceCardsView(sources: message.sources)
                }

                Text(message.timestamp, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var messageBody: some View {
        bubbleText(message.content, role: message.role)
    }
}

private func bubbleText(_ content: String, role: MessageRole) -> some View {
    Text(content)
        .foregroundStyle(role == .user ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            role == .user
                ? AnyShapeStyle(Color.accentColor)
                : AnyShapeStyle(Color(.secondarySystemFill))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
}


struct SourceCardsView: View {
    let sources: [SourceReference]
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("\(sources.count) source\(sources.count == 1 ? "" : "s")")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(sources) { source in
                    SourceCardView(source: source)
                }
            }
        }
    }
}

struct SourceCardView: View {
    let source: SourceReference

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(source.appName)
                    .font(.caption)
                    .fontWeight(.medium)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(relativeTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let title = source.windowTitle {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let url = source.url {
                Button(url) {
                    if let u = URL(string: url) {
                        NSWorkspace.shared.open(u)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.blue)
                .lineLimit(1)
            }

            Text(source.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(8)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var relativeTimestamp: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: source.timestamp) else { return source.timestamp }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
