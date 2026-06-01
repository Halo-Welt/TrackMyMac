import Foundation
import AppKit
import UserNotifications

/// Polls GitHub Releases and notifies when a newer version is available.
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// Owner / repo for the canonical release feed.
    static let repoOwner = "Halo-Welt"
    static let repoName = "TrackMyMac"

    private var timer: Timer?
    private let session = URLSession(configuration: .ephemeral)
    private let userDefaults = UserDefaults.standard
    private let skipKey = "updateChecker.skipVersion"
    private let lastCheckKey = "updateChecker.lastCheck"

    /// 24h periodic check + once at launch (after 30s).
    func startAutomaticChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.check(silent: true)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.check(silent: true)
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Manually triggered check (e.g. menu item).
    /// `silent`: don't show "you're already up to date" alerts.
    func check(silent: Bool, completion: ((Result<ReleaseInfo, Error>) -> Void)? = nil) {
        let url = URL(string: "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("TrackMyMac-UpdateChecker", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            self.userDefaults.set(Date().timeIntervalSince1970, forKey: self.lastCheckKey)

            if let error = error {
                Log.error("Update check failed: \(error)")
                DispatchQueue.main.async {
                    completion?(.failure(error))
                    if !silent { self.showError(error.localizedDescription) }
                }
                return
            }
            guard let data = data,
                  let info = try? JSONDecoder().decode(ReleaseInfo.self, from: data) else {
                DispatchQueue.main.async {
                    if !silent { self.showError("解析 GitHub 响应失败") }
                    completion?(.failure(NSError(domain: "UpdateChecker", code: -1)))
                }
                return
            }
            DispatchQueue.main.async {
                completion?(.success(info))
                self.handle(info: info, silent: silent)
            }
        }
        task.resume()
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var lastCheckedAt: Date? {
        let v = userDefaults.double(forKey: lastCheckKey)
        return v > 0 ? Date(timeIntervalSince1970: v) : nil
    }

    // MARK: - Logic

    private func handle(info: ReleaseInfo, silent: Bool) {
        let latest = info.normalizedTag
        let current = currentVersion
        let skipped = userDefaults.string(forKey: skipKey)

        if Self.compareVersions(latest, current) <= 0 {
            if !silent { showInfo("已是最新版本", body: "当前版本：\(current)") }
            return
        }
        if skipped == latest {
            if !silent { showInfo("有新版本可用", body: "你已选择跳过 \(latest)。点击菜单栏 → 检查更新 重新提示。") }
            return
        }
        promptUpdate(latest: latest, current: current, info: info)
    }

    private func promptUpdate(latest: String, current: String, info: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "TrackMyMac \(latest) 可用"
        alert.informativeText = "当前版本：\(current)\n\n更新说明：\n\(info.body?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(800) ?? "(无)")"
        alert.addButton(withTitle: "前往下载")
        alert.addButton(withTitle: "稍后提醒")
        alert.addButton(withTitle: "跳过此版本")
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        switch resp {
        case .alertFirstButtonReturn:
            if let asset = info.dmgAsset, let url = URL(string: asset.browser_download_url) {
                NSWorkspace.shared.open(url)
            } else if let url = URL(string: info.html_url) {
                NSWorkspace.shared.open(url)
            }
        case .alertThirdButtonReturn:
            userDefaults.set(latest, forKey: skipKey)
        default:
            break
        }
    }

    private func showInfo(_ title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showError(_ msg: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "检查更新失败"
        alert.informativeText = msg
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    /// Compare semver-like strings. Returns -1/0/1.
    static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber && $0 != "." })
                .joined(separator: ".")
                .split(separator: ".")
                .map { Int($0) ?? 0 }
        }
        let a = parts(lhs)
        let b = parts(rhs)
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
    }
}

struct ReleaseInfo: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String
    let assets: [Asset]

    var normalizedTag: String {
        tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name
    }

    var dmgAsset: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }
}

struct Asset: Decodable {
    let name: String
    let browser_download_url: String
    let size: Int
}
