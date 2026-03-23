import AppKit
import SwiftUI
import RerunCore
import os

private let logger = Logger(subsystem: "com.rerun", category: "ChatPanel")

extension Notification.Name {
    static let chatPanelDidShow = Notification.Name("chatPanelDidShow")
}

@MainActor
final class ChatPanel {
    private let panel: NSPanel
    private let viewModel: ChatViewModel
    private var keyMonitor: Any?

    init(db: DatabaseManager, modelManager: ModelManager) {
        logger.notice("Creating ChatPanel")
        let engine = ChatEngine(db: db, modelManager: modelManager)
        viewModel = ChatViewModel(chatEngine: engine, modelManager: modelManager)
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
        panel.backgroundColor = .clear
        panel.isOpaque = false

        // Persist panel size across sessions
        panel.setFrameAutosaveName("RerunChatPanel")

        // Material background with SwiftUI content
        let chatView = ChatView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: chatView)

        let effectView = NSVisualEffectView()
        effectView.material = .sidebar
        effectView.state = .active
        effectView.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
        ])
        panel.contentView = effectView

        // Escape to dismiss
        panel.standardWindowButton(.closeButton)?.isHidden = true

        // Keyboard shortcuts
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.contains(.command) else { return event }
            switch event.charactersIgnoringModifiers {
            case "k", "n":
                self?.viewModel.newConversation()
                return nil
            case "a":
                NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
                return nil
            case "c":
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                return nil
            case "v":
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                return nil
            case "x":
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                return nil
            case "z":
                if event.modifierFlags.contains(.shift) {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
                return nil
            default:
                return event
            }
        }
    }

    func toggle() {
        logger.notice("toggle() called — currently visible: \(self.panel.isVisible)")
        if OnboardingPanel.isActive { return }
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
        NotificationCenter.default.post(name: .chatPanelDidShow, object: nil)
    }

    func hide() {
        logger.notice("hide()")
        viewModel.newConversation()
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
