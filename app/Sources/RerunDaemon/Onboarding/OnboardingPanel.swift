import AppKit
import SwiftUI
import RerunCore

@MainActor
final class OnboardingPanel: NSObject, NSWindowDelegate {
    static private(set) var isActive: Bool = false

    private let panel: NSPanel
    private let viewModel: OnboardingViewModel

    init(modelManager: ModelManager, appVariant: RerunAppVariant) {
        viewModel = OnboardingViewModel(modelManager: modelManager, appVariant: appVariant)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        super.init()
        panel.delegate = self

        let onboardingView = OnboardingView(viewModel: viewModel) { [weak self] dismissal in
            self?.dismiss(dismissal)
        }
        let hostingView = NSHostingView(rootView: onboardingView)

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
    }

    func showIfNeeded() {
        guard viewModel.shouldShowOnboarding else { return }

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            let x = frame.midX - size.width / 2
            let y = frame.midY - size.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        OnboardingPanel.isActive = true
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss(_ dismissal: OnboardingDismissal = .explicit) {
        OnboardingPanel.isActive = false
        if dismissal == .explicit {
            viewModel.dismissAppManagementPrompt()
        }
        viewModel.stopPolling()
        panel.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        dismiss()
    }
}
