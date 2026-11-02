import AppKit
import SwiftUI
import ServiceManagement
import Combine

final class IncomeStore: ObservableObject {
    @Published var settings: IncomeSettings
    @Published var now = Date()
    @Published var millionaireMode = false
    @Published var detailsHeight: CGFloat = 440
    @Published var detailsPresentationID = 0
    @Published var locked: Bool {
        didSet { UserDefaults.standard.set(locked, forKey: "positionLocked") }
    }
    let loadWarning: String?
    private var timer: Timer?
    init() {
        if let data = UserDefaults.standard.data(forKey: "incomeSettings") {
            do { settings = try JSONDecoder().decode(IncomeSettings.self, from: data).validated(); loadWarning = nil }
            catch { settings = IncomeSettings(); loadWarning = "旧设置无法读取，已使用演示值，请重新设置工资。" }
        } else { settings = IncomeSettings(); loadWarning = nil }
        locked = UserDefaults.standard.bool(forKey: "positionLocked")
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.now = Date() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    var displaySettings: IncomeSettings { millionaireMode ? settings.millionaireExperience : settings }
    var snapshot: IncomeSnapshot { IncomeMath.snapshot(displaySettings, now: now) }
    func toggleMillionaireMode() { millionaireMode.toggle(); now = Date() }
    func save(_ settings: IncomeSettings) throws {
        let valid = try settings.validated()
        let data = try JSONEncoder().encode(valid)
        UserDefaults.standard.set(data, forKey: "incomeSettings")
        self.settings = valid
        now = Date()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = IncomeStore()
    var settingsWindow: NSWindow?
    var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    private var lastAmount = ""
    private var lastCurrency = ""
    private var amountAnimator: StatusAmountAnimator?
    private var escapeMonitor: Any?
    private var observations: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--render-roll-preview"), CommandLine.arguments.count > index + 1 {
            let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let amounts = ["¥123.456", "¥123.466", "¥123.476", "¥123.486", "¥123.496", "¥123.506"]
            for step in 0..<(amounts.count - 1) {
                for frame in 0..<25 {
                    let image = StatusAmountRenderer.image(from: amounts[step], to: amounts[step + 1], progress: Double(frame) / 24, width: 90)
                    if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) {
                        try? data.write(to: folder.appendingPathComponent(String(format: "%03d.png", step * 25 + frame)))
                    }
                }
            }
            NSApp.terminate(nil)
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-display-preview"), CommandLine.arguments.count > index + 1 {
            let view = HStack(spacing: 24) {
                IncomeDisplay(settings: store.settings, snapshot: store.snapshot, now: store.now).environment(\.colorScheme, .light)
                IncomeDisplay(settings: store.settings, snapshot: store.snapshot, now: store.now).environment(\.colorScheme, .dark)
            }.padding(24).background(Color(red: 0.82, green: 0.82, blue: 0.84))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            if let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
            NSApp.terminate(nil)
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--configure"), CommandLine.arguments.count > index + 4 {
            do {
                var settings = store.settings
                settings.currency = CommandLine.arguments[index + 1]
                settings.monthlySalary = Double(CommandLine.arguments[index + 2]) ?? -1
                settings.workStart = Int(CommandLine.arguments[index + 3]) ?? -1
                settings.workEnd = Int(CommandLine.arguments[index + 4]) ?? -1
                try store.save(settings)
            } catch { alert(error.localizedDescription) }
        }
        if CommandLine.arguments.contains("--enable-login") {
            do {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } catch { alert("未能开启开机启动：\(error.localizedDescription)") }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--status-file"), CommandLine.arguments.count > index + 1 {
            let status = SMAppService.mainApp.status
            let login = status == .enabled ? "enabled" : status == .requiresApproval ? "requiresApproval" : "notEnabled"
            let state: [String: Any] = ["currency": store.settings.currency, "monthlySalary": store.settings.monthlySalary, "workStart": store.settings.workStart, "workEnd": store.settings.workEnd, "login": login, "presentation": "menu-bar-capsule", "progress": store.snapshot.progress, "earned": store.snapshot.earned, "lunchEnabled": store.settings.lunchEnabled, "lunchStart": store.settings.lunchStart, "lunchEnd": store.settings.lunchEnd, "lunchPaid": store.settings.lunchPaid]
            if let data = try? JSONSerialization.data(withJSONObject: state, options: .prettyPrinted) {
                try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
            }
        }
        makeStatusItem()
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.store.now = Date() } })
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            showSettings()
        } else if let warning = store.loadWarning {
            showSettings()
            alert(warning)
        }
    }

    func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            amountAnimator = StatusAmountAnimator(button: button)
        }
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let detailsController = NSHostingController(rootView: IncomeDetails(
            store: store,
            edit: { [weak self] in self?.showSettings() },
            loginEnabled: { SMAppService.mainApp.status == .enabled },
            toggleLogin: { [weak self] in self?.toggleLogin() },
            quit: { NSApp.terminate(nil) }
        ))
        // A fixed viewport prevents SwiftUI content growth from moving the popover above the menu bar.
        detailsController.sizingOptions = []
        popover.contentViewController = detailsController
        popover.contentSize = NSSize(width: 308, height: store.detailsHeight)
        store.$now.combineLatest(store.$settings, store.$millionaireMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                // Published values become current after the publisher sends them.
                DispatchQueue.main.async { self?.updateStatusAmount() }
            }.store(in: &subscriptions)
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.popover.isShown == true {
                self?.popover.performClose(nil)
                return nil
            }
            return event
        }
        updateStatusAmount()
        if let index = CommandLine.arguments.firstIndex(of: "--render-status-preview"), CommandLine.arguments.count > index + 1,
           let image = statusItem.button?.image, let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
        }
    }

    func updateStatusAmount() {
        let amount = store.displaySettings.money(store.snapshot.earned, digits: 3)
        lastAmount = amount
        let width = max(StatusAmountRenderer.width(for: amount), StatusAmountRenderer.width(for: store.displaySettings.money(store.displaySettings.dailySalary, digits: 3)))
        statusItem.length = width + 4
        let animate = lastCurrency == store.settings.currency && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        lastCurrency = store.settings.currency
        let snapshot = store.snapshot
        let earning = store.displaySettings.monthlySalary > 0 && (snapshot.status == .working || (snapshot.status == .lunch && store.settings.lunchPaid))
        amountAnimator?.show(amount, width: width, animated: animate, earning: earning)
        statusItem.button?.setAccessibilityLabel("今日收入 \(amount)，点击查看详情")
        statusItem.button?.toolTip = "\(store.millionaireMode ? "百万年薪体验" : "今日收入") \(amount) · \(store.snapshot.statusLabel)"
    }

    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            for (title, selector) in [("修改工资与作息…", #selector(editSettings)), (SMAppService.mainApp.status == .enabled ? "关闭开机启动" : "开启开机启动", #selector(toggleLogin)), ("退出今日收入", #selector(quit))] {
                let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
                item.target = self
                menu.addItem(item)
            }
            popover.performClose(nil)
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { toggleDetails() }
    }

    func toggleDetails() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            store.now = Date()
            let screen = button.window?.screen ?? NSScreen.main
            let anchor = button.window?.convertToScreen(button.convert(button.bounds, to: nil))
            let available = screen.map { min($0.visibleFrame.maxY, anchor?.minY ?? $0.visibleFrame.maxY) - $0.visibleFrame.minY } ?? 500
            store.detailsHeight = min(440, max(160, available - 40))
            store.detailsPresentationID += 1
            popover.contentSize = NSSize(width: 308, height: store.detailsHeight)
            popover.contentViewController?.view.frame.size = popover.contentSize
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            positionDetailsBelowMenuBar()
            DispatchQueue.main.async { [weak self] in self?.positionDetailsBelowMenuBar() }
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func positionDetailsBelowMenuBar() {
        guard popover.isShown, let button = statusItem.button,
              let statusWindow = button.window,
              let screen = statusWindow.screen ?? NSScreen.main,
              let window = popover.contentViewController?.view.window else { return }
        let bounds = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        let anchor = statusWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let frame = window.frame
        let x = max(bounds.minX, min(frame.minX, bounds.maxX - frame.width))
        let top = min(anchor.minY - 2, bounds.maxY)
        let y = max(bounds.minY, min(top - frame.height, bounds.maxY - frame.height))
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow { settingsWindow = nil }
    }

    func showSettings(_ field: EditField = .currency) {
        popover.performClose(nil)
        // Reuse the same window, preserving any draft until it is explicitly cancelled.
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .incomeEditField, object: field)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 690), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "今日收入 · 工资与作息"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(settings: store.settings, initialField: field, save: { [weak self] settings in
            guard let self else { return }
            try self.store.save(settings)
            self.settingsWindow?.close()
        }, cancel: { [weak self] in self?.settingsWindow?.close() }))
        settingsWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func editSettings() { showSettings() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval { alert("请在系统设置 → 通用 → 登录项中允许“今日收入”启动。") }
        } catch { alert("未能修改开机启动：\(error.localizedDescription)") }
    }
    func alert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "今日收入"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { toggleDetails(); return true }
}

extension Notification.Name { static let incomeEditField = Notification.Name("incomeEditField") }

@main
@MainActor
enum DesktopIncomeMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
