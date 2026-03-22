import AppKit
import RerunCore

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var daemon: CaptureDaemon?
    private var statsTimer: Timer?
    private var chatPanel: ChatPanel?
    private var modelManager: ModelManager?
    private let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
        ?? ProcessInfo.processInfo.processName

    func setup(daemon: CaptureDaemon) {
        self.daemon = daemon

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "eye.circle", accessibilityDescription: appName)
        item.button?.toolTip = appName
        let menu = buildMenu()
        menu.delegate = self
        item.menu = menu
        self.statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Status header
        let ax = AccessibilityExtractor.isAccessibilityGranted
        let sr = OCRExtractor.isScreenRecordingGranted
        let statusText = ax ? "\(appName): Capturing" : "\(appName): Missing Accessibility permission"
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if !ax || !sr {
            let permItem = NSMenuItem(title: "Open Privacy Settings…", action: #selector(openPrivacySettings), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Pause / Resume
        let pauseURL = RerunHome.pauseFileURL()
        let isPaused = FileManager.default.fileExists(atPath: pauseURL.path)
        if isPaused {
            let item = NSMenuItem(title: "Resume Capturing", action: #selector(resumeCapture), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "Pause Capturing", action: #selector(pauseCapture), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let chatItem = NSMenuItem(title: "Chat\u{2026}", action: #selector(toggleChat), keyEquivalent: "")
        chatItem.target = self
        menu.addItem(chatItem)

        // Model status
        if let modelManager {
            switch modelManager.state {
            case .idle:
                break
            case .downloading(let progress):
                let pct = Int(progress * 100)
                let item = NSMenuItem(title: "AI Model: Downloading \(pct)%", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            case .ready:
                break
            case .failed:
                menu.addItem(NSMenuItem.separator())
                let item = NSMenuItem(title: "AI Model: Download Failed", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
                let retry = NSMenuItem(title: "Retry Download\u{2026}", action: #selector(retryModelDownload), keyEquivalent: "")
                retry.target = self
                menu.addItem(retry)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit \(appName)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
    }

    @objc private func pauseCapture() {
        let pauseURL = RerunHome.pauseFileURL()
        let dir = pauseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: pauseURL.path, contents: nil)
        statusItem?.menu = buildMenu()
    }

    @objc private func resumeCapture() {
        let pauseURL = RerunHome.pauseFileURL()
        try? FileManager.default.removeItem(at: pauseURL)
        statusItem?.menu = buildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in buildMenu().items {
            menu.addItem(item.copy() as! NSMenuItem)
        }
    }

    func setChatPanel(_ panel: ChatPanel) {
        self.chatPanel = panel
    }

    func setModelManager(_ manager: ModelManager) {
        self.modelManager = manager
    }

    @objc private func toggleChat() {
        chatPanel?.toggle()
    }

    @objc private func retryModelDownload() {
        Task { await modelManager?.retry() }
    }

    @objc private func quitApp() {
        daemon?.stop()
        try? FileManager.default.removeItem(at: RerunHome.pidFileURL())
        NSApplication.shared.terminate(nil)
    }
}
