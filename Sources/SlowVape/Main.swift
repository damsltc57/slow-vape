import AppKit
import AVFoundation
import SlowVapeCore
import SwiftUI
import UserNotifications

@main
enum SlowVapeApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppController()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppController: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var model: AppModel?
    private var window: NSWindow?
    private var alert: NSPanel?
    private var statusItem: NSStatusItem?
    private var statusItemLabel: String?
    private var timer: Task<Void, Never>?
    private var audio: AVAudioPlayer?
    private var alertIsDemo = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        let base = URL.applicationSupportDirectory.appending(path: "Slow Vape", directoryHint: .isDirectory)
        let model = AppModel(dataURL: base.appending(path: "history.json"))
        self.model = model
        model.presentAlert = { [weak self] limits in self?.showAlert(limits) }
        model.statusChanged = { [weak self] in self?.updateStatusItem() }
        installMainMenu()
        installStatusItem()
        let background = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !background || !model.setupComplete { showWindow() }
        if model.setupComplete && model.preferences.startCameraAtLaunch { model.start() }
        timer = Task { [weak model] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let model else { return }
                model.tick()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.cancel()
        model?.stop()
    }

    private func showWindow() {
        guard let model else { return }
        if window == nil {
            let main = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            main.title = "Slow Vape"
            main.minSize = NSSize(width: 820, height: 620)
            main.isReleasedWhenClosed = false
            main.center()
            main.contentView = NSHostingView(rootView: RootView(
                model: model, previewSound: { [weak self] volume in self?.playSound(volume) },
                previewAlert: { [weak self] in self?.showAlert([.hour], demo: true) }
            ).preferredColorScheme(.dark).environment(\.locale, L10n.locale))
            window = main
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.text("menu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.text("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let fileItem = NSMenuItem()
        let file = NSMenu(title: L10n.text("menu.file"))
        file.addItem(withTitle: L10n.text("menu.closeWindow"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = file
        menu.addItem(fileItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: L10n.text("menu.edit"))
        edit.addItem(withTitle: L10n.text("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L10n.text("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L10n.text("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L10n.text("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    @objc private func showDashboard() {
        model?.section = .dashboard
        showWindow()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(showDashboard)
        statusItem = item
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let model, let button = statusItem?.button else { return }
        let limitReached = model.isTracking && !model.reached.isEmpty
        let label = limitReached ? "Slow Vape · \(L10n.text("limits.reached"))" : model.isTracking
            ? "Slow Vape · \(L10n.text("camera.active"))" : "Slow Vape · \(model.cameraMessage)"
        guard statusItemLabel != label else { return }
        statusItemLabel = label

        if limitReached {
            button.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: label)
        } else if let mark = Brand.mark {
            let size = NSSize(width: 17, height: 17)
            let opacity = model.isTracking ? 1.0 : 0.55
            button.image = NSImage(size: size, flipped: false) { rect in
                mark.draw(in: rect, from: .zero, operation: .sourceOver, fraction: opacity)
                return true
            }
        } else {
            button.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: label)
        }
        button.image?.isTemplate = true
        button.setAccessibilityLabel(label)
        button.toolTip = label
    }

    private func showAlert(_ limits: Set<UsageLimit>, demo: Bool = false) {
        guard let model else { return }
        if alert == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 530, height: 348),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            panel.title = "Slow Vape"
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.level = .modalPanel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            alert = panel
        }
        guard let alert else { return }
        let wasVisible = alert.isVisible
        if wasVisible, demo && !alertIsDemo {
            alert.makeKeyAndOrderFront(nil)
            return
        }
        let shouldPlay = !wasVisible || (alertIsDemo && !demo)
        alertIsDemo = demo
        alert.contentView = NSHostingView(rootView: LimitAlertView(
            model: model, limits: limits, demo: demo, dismiss: { [weak alert] in alert?.close() }
        ).preferredColorScheme(.dark).environment(\.locale, L10n.locale))
        if !wasVisible { alert.center() }
        NSApp.activate(ignoringOtherApps: true)
        alert.makeKeyAndOrderFront(nil)
        alert.orderFrontRegardless()
        if shouldPlay { playSound(model.preferences.volume) }
        NSAccessibility.post(element: alert, notification: .announcementRequested, userInfo: [
            .announcement: demo ? L10n.text("alert.accessibilityPreview") : L10n.text("alert.accessibilityReached"),
            .priority: NSAccessibilityPriorityLevel.high.rawValue
        ])
    }

    private func playSound(_ volume: Double) {
        guard volume > 0, let url = Bundle.main.url(forResource: "LimitAlert", withExtension: "wav") else { return }
        audio?.stop()
        audio = try? AVAudioPlayer(contentsOf: url)
        audio?.volume = Float(volume)
        audio?.play()
    }
}
