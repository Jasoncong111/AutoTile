import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tiler = WindowTiler()
    private var statusItem: NSStatusItem!
    private var restoreItem: NSMenuItem!
    private var statusLabelItem: NSMenuItem!
    private var lastSignature = ""
    private var lastLayoutSnapshot = WindowLayoutSnapshot(entries: [])
    private var didPromptForAccessibility = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        maybePromptForAccessibility()
        refreshPermissionStatus(promptIfNeeded: false)
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "AutoTile"
            if let image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "窗整") {
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageLeading
            }
        }

        let menu = NSMenu()

        statusLabelItem = NSMenuItem(title: "正在检查权限...", action: nil, keyEquivalent: "")
        statusLabelItem.isEnabled = false
        menu.addItem(statusLabelItem)
        menu.addItem(.separator())

        let tileNowItem = NSMenuItem(title: "平铺窗口", action: #selector(tileNow), keyEquivalent: "t")
        tileNowItem.target = self
        menu.addItem(tileNowItem)

        let showDesktopItem = NSMenuItem(title: "显示桌面", action: #selector(showDesktop), keyEquivalent: "d")
        showDesktopItem.target = self
        menu.addItem(showDesktopItem)

        restoreItem = NSMenuItem(title: "恢复上一次布局", action: #selector(restorePreviousLayout), keyEquivalent: "r")
        restoreItem.target = self
        restoreItem.isEnabled = false
        menu.addItem(restoreItem)

        let promptItem = NSMenuItem(title: "重新请求辅助功能权限", action: #selector(promptPermission), keyEquivalent: "p")
        promptItem.target = self
        menu.addItem(promptItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func refreshPermissionStatus(promptIfNeeded: Bool) {
        let trusted = AccessibilityPermissions.isTrusted(prompt: promptIfNeeded)
        statusLabelItem.title = trusted ? "辅助功能权限：已开启" : "辅助功能权限：未开启"
    }

    private func showMessage(title: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func maybePromptForAccessibility() {
        guard !didPromptForAccessibility else {
            return
        }
        didPromptForAccessibility = true
        _ = AccessibilityPermissions.isTrusted(prompt: true)
    }

    private func performTile(reason: String) {
        do {
            DebugLog.clear()
            DebugLog.write("performTile reason=\(reason)")
            let snapshot = try tiler.captureLayoutForActiveScreen()
            if !snapshot.isEmpty {
                lastLayoutSnapshot = snapshot
                restoreItem.isEnabled = true
                DebugLog.write("captured previous layout entries=\(snapshot.entries.count)")
            }
            let tiledCount = try tiler.tileWindowsOnActiveScreen()
            lastSignature = tiler.currentSignature()
            statusLabelItem.title = "\(reason)：已处理 \(tiledCount) 个窗口"
            DebugLog.write("tile completed count=\(tiledCount)")
            if tiledCount == 0 {
                showMessage(
                    title: "没有找到可整理的窗口",
                    detail: "当前屏幕上没有找到可移动、可调整大小的窗口。"
                )
            }
        } catch {
            statusLabelItem.title = "整理失败：\(error.localizedDescription)"
            DebugLog.write("tile failed error=\(error.localizedDescription)")
            showMessage(title: "整理失败", detail: error.localizedDescription)
        }
    }

    @objc
    private func tileNow() {
        guard AccessibilityPermissions.isTrusted(prompt: false) else {
            refreshPermissionStatus(promptIfNeeded: false)
            openAccessibilitySettings()
            showMessage(
                title: "需要辅助功能权限",
                detail: "请先在 系统设置 -> 隐私与安全性 -> 辅助功能 中开启窗口整理，然后重新打开应用。"
            )
            return
        }
        performTile(reason: "平铺完成")
    }

    @objc
    private func showDesktop() {
        guard AccessibilityPermissions.isTrusted(prompt: false) else {
            refreshPermissionStatus(promptIfNeeded: false)
            openAccessibilitySettings()
            showMessage(
                title: "需要辅助功能权限",
                detail: "请先在 系统设置 -> 隐私与安全性 -> 辅助功能 中开启窗口整理，然后重新打开应用。"
            )
            return
        }

        do {
            let snapshot = try tiler.captureLayoutForActiveScreen()
            if !snapshot.isEmpty {
                lastLayoutSnapshot = snapshot
                restoreItem.isEnabled = true
            }
            let count = try tiler.showDesktopOnActiveScreen()
            lastSignature = tiler.currentSignature()
            statusLabelItem.title = "显示桌面：已退下 \(count) 个窗口"
        } catch {
            statusLabelItem.title = "显示桌面失败：\(error.localizedDescription)"
            showMessage(title: "显示桌面失败", detail: error.localizedDescription)
        }
    }

    @objc
    private func restorePreviousLayout() {
        guard AccessibilityPermissions.isTrusted(prompt: false) else {
            refreshPermissionStatus(promptIfNeeded: false)
            openAccessibilitySettings()
            showMessage(
                title: "需要辅助功能权限",
                detail: "请先在 系统设置 -> 隐私与安全性 -> 辅助功能 中开启窗口整理。"
            )
            return
        }

        guard !lastLayoutSnapshot.isEmpty else {
            statusLabelItem.title = "没有可恢复的布局"
            restoreItem.isEnabled = false
            showMessage(
                title: "没有可恢复的布局",
                detail: "请先使用一次平铺窗口或显示桌面。"
            )
            return
        }

        let restoredCount = tiler.restoreLayout(lastLayoutSnapshot)
        lastSignature = tiler.currentSignature()
        statusLabelItem.title = "已恢复 \(restoredCount) 个窗口"
    }

    @objc
    private func promptPermission() {
        didPromptForAccessibility = false
        openAccessibilitySettings()
        maybePromptForAccessibility()
        refreshPermissionStatus(promptIfNeeded: false)
    }

    @objc
    private func quit() {
        NSApp.terminate(nil)
    }
}
