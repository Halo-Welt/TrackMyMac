import SwiftUI
import AppKit

/// Headless menu-bar-only app. No Dock icon, no main window.
/// Click the status item to toggle a popover containing the dashboard.
@main
struct TrackMyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // A "Settings" scene is the only Scene that doesn't auto-create a window
        // when the app launches. We don't actually use it.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let permsModel = PermissionsModel()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var permTimer: Timer?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SummaryJSONExporter.runIfNeeded() {
            return
        }

        // Force the app to never show in the Dock or Cmd-Tab.
        NSApp.setActivationPolicy(.accessory)

        // Trigger AX prompt early – this is necessary for CGEventTap & AXUIElement.
        Permissions.promptAccessibility()
        Permissions.promptScreenRecording()

        // Start core services (they no-op gracefully if not yet permitted).
        EventMonitor.shared.start()
        AppTracker.shared.start()
        ActivitySampler.shared.start()
        UpdateChecker.shared.startAutomaticChecks()

        installPopover()
        installStatusItem()
        installGlobalDismissMonitor()

        permTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !EventMonitor.shared.running {
                EventMonitor.shared.start()
            }
            self.permsModel.refresh()
            self.refreshStatusItemTitle()
        }
        RunLoop.main.add(permTimer!, forMode: .common)
        permsModel.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventMonitor.shared.stop()
        AppTracker.shared.stop()
        ActivitySampler.shared.stop()
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Popover

    private func installPopover() {
        let p = NSPopover()
        p.behavior = .transient   // auto-dismiss when clicking outside
        p.animates = true
        p.delegate = self
        p.contentSize = NSSize(width: 880, height: 620)
        p.contentViewController = NSHostingController(
            rootView: PopoverRootView(perms: permsModel)
        )
        popover = p
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
                                   accessibilityDescription: "TrackMyMac")
            button.imagePosition = .imageLeft
            button.target = self
            button.action = #selector(statusButtonClicked(_:))
            // accept both left and right click
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        refreshStatusItemTitle()
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)
        if isRightClick {
            showContextMenu(sender)
            return
        }
        togglePopover(sender)
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(sender)
        }
    }

    private func showPopover(_ sender: NSStatusBarButton) {
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        let header = NSMenuItem(title: "TrackMyMac v\(UpdateChecker.shared.currentVersion)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date()).timeIntervalSince1970
        let s = Database.shared.summary(from: start, to: Date().timeIntervalSince1970)
        menu.addItem(withTitle: "今日按键: \(s.keys)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "今日点击: \(s.clicks)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: "今日活跃: \(formatDuration(s.activeSec))", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        let revealItem = NSMenuItem(title: "在 Finder 显示数据库", action: #selector(revealDB), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)
        let updateItem = NSMenuItem(title: "检查更新…", action: #selector(checkUpdate), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(updateItem)
        let openSettings = NSMenuItem(title: "打开权限设置…", action: #selector(openPermissionsSettings), keyEquivalent: ",")
        openSettings.target = self
        menu.addItem(openSettings)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 TrackMyMac",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        // Show as menu, not popover
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset so next left-click toggles popover again
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    private func refreshStatusItemTitle() {
        guard let button = statusItem?.button else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date()).timeIntervalSince1970
        let s = Database.shared.summary(from: start, to: Date().timeIntervalSince1970)
        button.title = " \(formatDuration(s.activeSec))"
    }

    // MARK: - Global click outside dismissal (also handles right-click anywhere)

    private func installGlobalDismissMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.popover.isShown else { return }
            self.popover.performClose(nil)
        }
    }

    // MARK: - Menu actions

    @objc private func revealDB() {
        NSWorkspace.shared.activateFileViewerSelecting([Paths.databaseURL])
    }

    @objc private func checkUpdate() {
        UpdateChecker.shared.check(silent: false)
    }

    @objc private func openPermissionsSettings() {
        Permissions.openInputMonitoringSettings()
    }
}

/// Root view shown inside the popover.
struct PopoverRootView: View {
    @ObservedObject var perms: PermissionsModel
    @State private var showOnboarding: Bool = false

    var body: some View {
        ZStack {
            DashboardView(perms: perms)
            if showOnboarding {
                Color.black.opacity(0.35).ignoresSafeArea()
                OnboardingView(perms: perms) { showOnboarding = false }
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(NSColor.windowBackgroundColor))
                            .shadow(radius: 20)
                    )
            }
        }
        .frame(width: 880, height: 620)
        .onAppear {
            perms.refresh()
            if !perms.allGranted { showOnboarding = true }
        }
    }
}
