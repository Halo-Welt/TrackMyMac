# TrackMyMac

> 本地化 macOS 使用情况监控工具：键盘 / 鼠标 / 应用 / 窗口标题 / 活跃时长，全部本地存储 + AES-GCM 加密，密码字段自动跳过。

[![Release](https://img.shields.io/github/v/release/Halo-Welt/TrackMyMac?display_name=tag)](https://github.com/Halo-Welt/TrackMyMac/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)](https://github.com/Halo-Welt/TrackMyMac/releases/latest)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange)](https://swift.org)

![dashboard](https://raw.githubusercontent.com/Halo-Welt/TrackMyMac/main/docs/dashboard.png)

---

## 下载

最新版：**[Releases 页面](https://github.com/Halo-Welt/TrackMyMac/releases/latest)** → 下载 `TrackMyMac-x.y.z.dmg`。

或在终端：

```bash
# 自动下载并安装到 /Applications
curl -L https://github.com/Halo-Welt/TrackMyMac/releases/latest/download/TrackMyMac-latest.dmg -o /tmp/TrackMyMac.dmg
hdiutil attach /tmp/TrackMyMac.dmg -nobrowse -mountpoint /tmp/TrackMyMac.vol
cp -R /tmp/TrackMyMac.vol/TrackMyMac.app /Applications/
hdiutil detach /tmp/TrackMyMac.vol
xattr -dr com.apple.quarantine /Applications/TrackMyMac.app
open /Applications/TrackMyMac.app
```

## 自动更新

- 启动后 30 秒首次检查，之后每 6 小时自动检查一次
- 发现新版本时弹窗提示"前往下载 / 稍后提醒 / 跳过此版本"
- 也可以通过菜单栏 → **检查更新…** 手动触发
- 更新源：本仓库的 GitHub Releases，不依赖任何第三方服务

## 功能

| 维度 | 说明 |
|---|---|
| **键盘** | 全局按键计数 + 8 类（字母/数字/符号/导航/功能/修饰/快捷键/空白）+ AES-GCM 加密原文 |
| **鼠标** | 左/右/中键点击、滚轮、移动距离 |
| **应用** | 前台 App 切换 → 起止时间序列 |
| **窗口** | 5 秒轮询当前焦点窗口标题（需要屏幕录制权限）|
| **时长** | 开机/亮屏（CGSession 锁屏判断）+ 活跃（HID idle < 60s）|
| **可视化** | 今天 / 7 天 / 30 天 / 365 天 切换 + 5 秒自动刷新 |
| **隐私** | secure input 自动跳过；DB 加 `isExcludedFromBackup`；Keychain 存密钥 |

## 首次启动需要的三个权限

1. **辅助功能 (Accessibility)** —— 读窗口标题
2. **输入监控 (Input Monitoring)** —— 全局键鼠
3. **屏幕录制 (Screen Recording)** —— 浏览器/编辑器精确标题

App 启动后会自动弹出引导面板，逐项跳到系统设置。**每勾一项后必须重启 App** 才生效（macOS 限制）。

> 由于使用 ad-hoc 签名（无 Apple 开发者账号），首次双击会被 Gatekeeper 拦下。在 Finder 里**右键 → 打开 → 打开**即可放行。或者运行下面的命令解除隔离属性：
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/TrackMyMac.app
> ```

## 数据存储

- 数据库：`~/Library/Application Support/TrackMyMac/tracker.db`（标准 SQLite，可直接 `sqlite3` 打开）
- 加密密钥：macOS Keychain，service `com.trackmymac.app`，account `db-key-v1`
- `keystrokes.cipher` 列是 AES-GCM 加密的字符明文；其余列是聚合统计明文
- 想清空：删除 `tracker.db` 文件

## 从源码构建

```bash
git clone https://github.com/Halo-Welt/TrackMyMac.git
cd TrackMyMac
bash Scripts/run.sh        # 一键编译并打开
# 或仅打包
bash Scripts/build_app.sh  # 产物在 build/dist/TrackMyMac.app
# 打包成 dmg
bash Scripts/make_dmg.sh   # 产物在 build/dist/TrackMyMac-<version>.dmg
```

依赖：

- macOS 14+
- Xcode Command Line Tools（不需要完整 Xcode）：`xcode-select --install`
- Swift 5.9 以上

## 项目结构

```
TrackMyMac/
├── Package.swift
├── Sources/TrackMyMac/
│   ├── App/TrackMyMacApp.swift        SwiftUI 入口 + AppDelegate + 菜单栏
│   ├── Core/
│   │   ├── EventMonitor.swift         CGEventTap 全局键鼠
│   │   ├── AppTracker.swift           前台 App + 窗口标题
│   │   ├── ActivitySampler.swift      idle / 屏幕开关 / 每分钟聚合
│   │   ├── KeyCategory.swift          按键分类
│   │   ├── Permissions.swift          权限检查与设置跳转
│   │   └── UpdateChecker.swift        GitHub Releases 自动更新
│   ├── Storage/Database.swift         SQLite + 表结构
│   ├── UI/
│   │   ├── DashboardView.swift        主仪表盘
│   │   ├── DashboardModel.swift       数据模型
│   │   └── OnboardingView.swift       首次引导
│   └── Utils/
│       ├── Crypto.swift               CryptoKit AES-GCM
│       └── Log.swift                  路径与日志
├── Resources/
│   ├── Info.plist
│   └── TrackMyMac.entitlements
└── Scripts/
    ├── build_app.sh                   编译 + 组 .app + ad-hoc 签名
    ├── make_dmg.sh                    .app → .dmg
    ├── release.sh                     一键打 dmg + gh release create
    ├── run.sh                         本地一键运行
    └── make_icon.py                   生成应用图标
```

## 路线图

- [x] 键鼠 / 应用 / 窗口标题 / 活跃时长采集
- [x] 加密存储 + 密码字段自动跳过
- [x] 仪表盘多周期切换
- [x] 菜单栏小图标
- [x] GitHub Releases 自动更新
- [ ] 开机自启（已链接 ServiceManagement）
- [ ] CSV / JSON 导出
- [ ] 键盘热力图
- [ ] 周报 / 月报推送通知

## License

MIT
