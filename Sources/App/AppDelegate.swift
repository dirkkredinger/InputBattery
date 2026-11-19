import AppKit
import CoreBluetooth
import ServiceManagement
import WidgetKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var statusItem: NSStatusItem!
    private var monitor: BatteryMonitor!
    private let notifier = Notifier()
    private var appleDevices: AppleDeviceSource!
    private let defaults = UserDefaults.standard
    private var devices: [DeviceBattery] = []
    private var lastWidgetReload = Date.distantPast

    private var warnLevel: Int {
        get { defaults.object(forKey: "warnLevel") as? Int ?? 20 }
        set { defaults.set(newValue, forKey: "warnLevel"); settingsChanged() }
    }
    private var criticalLevel: Int {
        get { defaults.object(forKey: "criticalLevel") as? Int ?? 10 }
        set { defaults.set(newValue, forKey: "criticalLevel"); settingsChanged() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        notifier.requestPermission()

        devices = SharedStore.load()?.devices ?? []
        monitor = BatteryMonitor(previous: devices)
        monitor.onChange = { [weak self] devices in self?.update(devices) }
        update(monitor.sortedDevices)

        appleDevices = AppleDeviceSource(previous: devices)
        appleDevices.onUpdate = { [weak self] list in
            guard let self else { return }
            // Skip devices that CoreBluetooth already reports (same identifier or name).
            let own = self.devices.filter { !$0.id.hasPrefix(AppleDeviceSource.idPrefix) }
            let ids = Set(own.map { AppleDeviceSource.idPrefix + $0.id })
            let names = Set(own.map(\.name))
            self.monitor.setExternal(list.filter { !ids.contains($0.id) && !names.contains($0.name) },
                                     prefix: AppleDeviceSource.idPrefix)
        }
        appleDevices.start()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // Bluetooth needs a moment to reconnect after wake.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                self?.monitor.refresh()
                self?.appleDevices.poll()
            }
        }
    }

    // MARK: State

    private func update(_ devices: [DeviceBattery]) {
        self.devices = devices
        updateStatusItem()
        notifier.evaluate(devices, warn: warnLevel, critical: criticalLevel)
        writeSnapshot()
    }

    private func settingsChanged() {
        updateStatusItem()
        notifier.evaluate(devices, warn: warnLevel, critical: criticalLevel)
        writeSnapshot(force: true)
    }

    private func writeSnapshot(force: Bool = false) {
        let snapshot = Snapshot(devices: devices, warnLevel: warnLevel, criticalLevel: criticalLevel, written: .now)
        let old = SharedStore.load()
        SharedStore.save(snapshot)
        // Only bother the widget when something visible changed.
        let changed = force || old.map { o in
            o.devices.map { [$0.id, "\($0.level)", "\($0.connected)"] } != devices.map { [$0.id, "\($0.level)", "\($0.connected)"] }
        } ?? true
        if changed || Date().timeIntervalSince(lastWidgetReload) > 1800 {
            WidgetCenter.shared.reloadAllTimelines()
            lastWidgetReload = .now
        }
    }

    // MARK: Menu bar

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let shown = devices.filter(\.connected)
        let result = NSMutableAttributedString()
        let font = NSFont.menuBarFont(ofSize: 0)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)

        if shown.isEmpty {
            button.image = NSImage(systemSymbolName: "battery.0percent", accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig)
            button.attributedTitle = NSAttributedString()
            button.toolTip = L("No device with battery information connected")
            return
        }

        button.image = nil
        for (i, d) in shown.enumerated() {
            if i > 0 { result.append(NSAttributedString(string: "  ")) }
            let tier = BatteryTier.of(d.level, warn: warnLevel, critical: criticalLevel)
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 0]
            if tier == .critical { attrs[.foregroundColor] = NSColor.systemRed }
            else if tier == .low { attrs[.foregroundColor] = NSColor.systemOrange }

            if let img = NSImage(systemSymbolName: d.kind.symbol, accessibilityDescription: d.name)?
                .withSymbolConfiguration(symbolConfig) {
                let tinted = tier == .ok ? img : img.tinted(attrs[.foregroundColor] as! NSColor)
                tinted.isTemplate = tier == .ok
                let att = NSTextAttachment()
                att.image = tinted
                att.bounds = CGRect(x: 0, y: font.descender + 1.5, width: tinted.size.width, height: tinted.size.height)
                result.append(NSAttributedString(attachment: att))
                result.append(NSAttributedString(string: " ", attributes: attrs))
            }
            result.append(NSAttributedString(string: "\(d.level) %" + (d.charging == true ? "⚡︎" : ""), attributes: attrs))
        }
        button.attributedTitle = result
        button.toolTip = shown.map { "\($0.name): \($0.level) %" }.joined(separator: "\n")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if monitor.bluetoothState == .unauthorized {
            menu.addItem(disabled(L("No Bluetooth access – allow it in System Settings › Privacy & Security › Bluetooth.")))
        } else if monitor.bluetoothState == .poweredOff {
            menu.addItem(disabled(L("Bluetooth is turned off.")))
        }

        if devices.isEmpty {
            menu.addItem(disabled(L("No device with battery information found.")))
        }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        for d in devices {
            let tier = BatteryTier.of(d.level, warn: warnLevel, critical: criticalLevel)
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let title = NSMutableAttributedString(string: "\(d.name)   ", attributes: [.font: NSFont.menuFont(ofSize: 0)])
            var levelAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)]
            if tier == .critical { levelAttrs[.foregroundColor] = NSColor.systemRed }
            if tier == .low { levelAttrs[.foregroundColor] = NSColor.systemOrange }
            title.append(NSAttributedString(string: "\(d.level) %", attributes: levelAttrs))
            var sub = d.connected
                ? String(format: L("updated %@"), rel.localizedString(for: d.updated, relativeTo: .now))
                : String(format: L("not connected · last seen %@"), rel.localizedString(for: d.updated, relativeTo: .now))
            if d.charging == true { sub = L("charging") + " · " + sub }
            if let parts = d.partsDescription { sub = parts + "\n" + sub }
            title.append(NSAttributedString(string: "\n" + sub, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = title
            item.image = NSImage(systemSymbolName: d.kind.symbol, accessibilityDescription: nil)
            if !d.connected {
                let forget = NSMenu()
                let f = NSMenuItem(title: L("Remove from list"), action: #selector(forgetDevice(_:)), keyEquivalent: "")
                f.target = self
                f.representedObject = d.id
                forget.addItem(f)
                item.submenu = forget
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(levelMenu(L("Warn at"), values: [40, 30, 25, 20, 15], current: warnLevel, action: #selector(setWarn(_:))))
        menu.addItem(levelMenu(L("Critical at"), values: [15, 10, 5], current: criticalLevel, action: #selector(setCritical(_:))))

        let login = NSMenuItem(title: L("Open at Login"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item(L("Refresh Now"), #selector(refresh), key: "r"))
        menu.addItem(item(L("Send Test Notification"), #selector(testNotification)))
        menu.addItem(.separator())
        menu.addItem(item(L("About InputBattery"), #selector(about)))
        menu.addItem(item(L("Support on Ko-fi ♥"), #selector(donate)))
        menu.addItem(.separator())
        menu.addItem(item(L("Quit InputBattery"), #selector(quit), key: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func levelMenu(_ title: String, values: [Int], current: Int, action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: "\(title): \(current) %", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for v in values {
            let i = item("\(v) %", action)
            i.tag = v
            i.state = v == current ? .on : .off
            sub.addItem(i)
        }
        parent.submenu = sub
        return parent
    }

    // MARK: Actions

    @objc private func setWarn(_ sender: NSMenuItem) {
        warnLevel = max(sender.tag, criticalLevel + 5)
    }

    @objc private func setCritical(_ sender: NSMenuItem) {
        criticalLevel = sender.tag
        if warnLevel < sender.tag + 5 { warnLevel = sender.tag + 5 }
    }

    @objc private func forgetDevice(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { monitor.forget(id) }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func refresh() {
        monitor.refresh()
        appleDevices.poll()
    }
    @objc private func testNotification() { notifier.sendTest() }
    @objc private func about() { Links.showAbout() }
    @objc private func donate() { NSWorkspace.shared.open(Links.donate) }
    @objc private func quit() { NSApp.terminate(nil) }
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let img = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return img
    }
}
