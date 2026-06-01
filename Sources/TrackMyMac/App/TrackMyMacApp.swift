import SwiftUI
import AppKit

@main
struct TrackMyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("TrackMyMac") {
            RootView(perms: appDelegate.permsModel)
                .frame(minWidth: 880, minHeight: 620)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 TrackMyMac") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
    }
}

struct RootView: View {
    @ObservedObject var perms: PermissionsModel
    @State private var showOnboarding: Bool = false

    var body: some View {
        ZStack {
            DashboardView(perms: perms)
            if showOnboarding {
                Color.black.opacity(0.35).ignoresSafeArea()
                OnboardingView(perms: perms) {
                    showOnboarding = false
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.windowBackgroundColor)).shadow(radius: 20))
            }
        }
        .onAppear {
            perms.refresh()
            if !perms.allGranted { showOnboarding = true }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let permsModel = PermissionsModel()
    private var statusItem: NSStatusItem?
    private var permTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Trigger AX prompt early – this is necessary for CGEventTap & AXUIElement.
        Permissions.promptAccessibility()
        Permissions.promptScreenRecording()

        // Start core services (they no-op gracefully if not yet permitted).
        EventMonitor.shared.start()
        AppTracker.shared.start()
        ActivitySampler.shared.start()

        installMenuBar()
        UpdateChecker.shared.startAutomaticChecks()

        // Periodically refresh permission badges + retry tap if it failed.
        permTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !EventMonitor.shared.running {
                EventMonitor.shared.start()
            }
            self.permsModel.refresh()
            self.refreshMenuBarTitle()
        }
        RunLoop.main.add(permTimer!, forMode: .common)
        permsModel.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        EventMonitor.shared.stop()
        AppTracker.shared.stop()
        ActivitySampler.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar
        return false
    }

    // MARK: - Menu bar

    private func installMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent", accessibilityDescription: "TrackMyMac")
            button.imagePosition = .imageLeft
            button.title = ""
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "今日按键: -", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "今日点击: -", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "今日活跃: -", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开仪表盘", action: #selector(openDashboard), keyEquivalent: "d").target = self
        menu.addItem(withTitle: "在 Finder 显示数据库", action: #selector(revealDB), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "检查更新…", action: #selector(checkUpdate), keyEquivalent: "u")
            .target = self
        let aboutItem = menu.addItem(withTitle: "关于 / 版本：v\(UpdateChecker.shared.currentVersion)", action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 TrackMyMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        refreshMenuBarTitle()
    }

    private func refreshMenuBarTitle() {
        guard let menu = statusItem?.menu, menu.items.count >= 3 else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date()).timeIntervalSince1970
        let end = Date().timeIntervalSince1970
        let s = Database.shared.summary(from: start, to: end)
        menu.items[0].title = "今日按键: \(s.keys)"
        menu.items[1].title = "今日点击: \(s.clicks)"
        menu.items[2].title = "今日活跃: \(formatDuration(s.activeSec))"
        if let button = statusItem?.button {
            button.title = " \(formatDuration(s.activeSec))"
        }
    }

    @objc private func openDashboard() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title == "TrackMyMac" {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // If no window, ask AppKit to create one via the WindowGroup
        if let url = URL(string: "trackmymac://open") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func revealDB() {
        NSWorkspace.shared.activateFileViewerSelecting([Paths.databaseURL])
    }

    @objc private func checkUpdate() {
        UpdateChecker.shared.check(silent: false)
    }
}
