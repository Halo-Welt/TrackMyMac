import Foundation
import AppKit
import ApplicationServices

/// Tracks active application changes and the focused window title.
final class AppTracker {
    static let shared = AppTracker()
    private var currentSessionId: Int64?
    private var currentBundle: String?
    private var currentName: String?
    private var currentTitle: String?
    private var titleTimer: Timer?

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(didActivate(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(willTerminate(_:)),
                           name: NSWorkspace.willPowerOffNotification, object: nil)
        // Title polling (window titles change without app activation events)
        titleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshFocused()
        }
        RunLoop.main.add(titleTimer!, forMode: .common)
        refreshFocused(force: true)
    }

    func stop() {
        titleTimer?.invalidate()
        if let id = currentSessionId {
            Database.shared.endAppSession(id: id, ts: Date().timeIntervalSince1970)
            currentSessionId = nil
        }
    }

    @objc private func didActivate(_ note: Notification) {
        refreshFocused(force: true)
    }

    @objc private func willTerminate(_ note: Notification) {
        if let id = currentSessionId {
            Database.shared.endAppSession(id: id, ts: Date().timeIntervalSince1970)
        }
    }

    private func refreshFocused(force: Bool = false) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let bundle = app.bundleIdentifier
        let name = app.localizedName
        let title = focusedWindowTitle(for: app.processIdentifier)

        if force || bundle != currentBundle || name != currentName || title != currentTitle {
            let now = Date().timeIntervalSince1970
            if let id = currentSessionId {
                Database.shared.endAppSession(id: id, ts: now)
            }
            currentSessionId = Database.shared.startAppSession(ts: now, bundleId: bundle, appName: name, windowTitle: title)
            currentBundle = bundle
            currentName = name
            currentTitle = title
            Log.debug("App switch: \(name ?? "?") | \(title ?? "?")")
        }
    }

    private func focusedWindowTitle(for pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused)
        guard res == .success, let window = focused else { return nil }
        var title: CFTypeRef?
        let res2 = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
        guard res2 == .success else { return nil }
        return title as? String
    }
}
