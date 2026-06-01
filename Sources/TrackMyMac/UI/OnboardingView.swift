import SwiftUI
import AppKit

final class PermissionsModel: ObservableObject {
    @Published var accessibility: Bool = false
    @Published var screenRecording: Bool = false
    /// We don't have a direct preflight for Input Monitoring, infer from event tap status.
    @Published var inputMonitoringInferred: Bool = false

    var allGranted: Bool { accessibility && screenRecording && inputMonitoringInferred }

    func refresh() {
        accessibility = Permissions.accessibilityGranted
        screenRecording = Permissions.screenRecordingGranted
        inputMonitoringInferred = EventMonitor.shared.running
    }
}

struct OnboardingView: View {
    @ObservedObject var perms: PermissionsModel
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 30))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("欢迎使用 TrackMyMac").font(.title2.bold())
                    Text("为采集键鼠与窗口数据，需要授予以下权限。所有数据仅保存在本机。")
                        .foregroundStyle(.secondary)
                }
            }
            permissionRow(
                title: "辅助功能 (Accessibility)",
                detail: "用于读取当前活动应用的窗口标题",
                granted: perms.accessibility,
                action: { Permissions.openAccessibilitySettings() }
            )
            permissionRow(
                title: "输入监控 (Input Monitoring)",
                detail: "用于全局键鼠事件计数（密码字段会自动跳过）",
                granted: perms.inputMonitoringInferred,
                action: { Permissions.openInputMonitoringSettings() }
            )
            permissionRow(
                title: "屏幕录制 (Screen Recording)",
                detail: "用于精确读取浏览器/编辑器窗口标题",
                granted: perms.screenRecording,
                action: { Permissions.openScreenRecordingSettings() }
            )

            HStack(spacing: 10) {
                Button("重新检测") { perms.refresh() }
                Spacer()
                Button("进入仪表盘") { onContinue() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560)
    }

    private func permissionRow(title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.seal.fill" : "circle.dashed")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? "已授予" : "去设置") { action() }
                .disabled(granted)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}
