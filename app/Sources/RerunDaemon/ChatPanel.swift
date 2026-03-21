import AppKit
import SwiftUI
import os

private let logger = Logger(subsystem: "com.rerun", category: "ChatPanel")

@MainActor
final class ChatPanel {
    private let panel: NSPanel

    init() {
        logger.notice("Creating ChatPanel")
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 480),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 400, height: 300)

        // Placeholder SwiftUI content — Phase 2 replaces this
        let placeholder = NSHostingView(rootView: ChatPlaceholderView())
        panel.contentView = placeholder

        // Escape to dismiss
        panel.standardWindowButton(.closeButton)?.isHidden = true
    }

    func toggle() {
        logger.notice("toggle() called — currently visible: \(self.panel.isVisible)")
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        logger.notice("show() — positioning and ordering front")
        positionOnActiveScreen()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        logger.notice("hide()")
        panel.orderOut(nil)
    }

    private func positionOnActiveScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame

        let panelSize = panel.frame.size
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.maxY - (screenFrame.height * 0.2) - panelSize.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

// Minimal placeholder view — replaced by ChatView in Phase 2
private struct ChatPlaceholderView: View {
    var body: some View {
        VStack {
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
}
