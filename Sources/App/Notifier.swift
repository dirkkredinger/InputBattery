import Foundation
import UserNotifications

/// Sends a notification when a device drops below the warning or critical level.
/// Each level warns once; the critical warning repeats every 12 hours.
/// When the level rises clearly above the warning level again (new batteries),
/// the device is reset.
final class Notifier {
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let repeatCritical: TimeInterval = 12 * 3600

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func evaluate(_ devices: [DeviceBattery], warn: Int, critical: Int) {
        var tiers = defaults.dictionary(forKey: "alertTiers") as? [String: Int] ?? [:]
        var lastCritical = defaults.dictionary(forKey: "lastCriticalAlert") as? [String: Double] ?? [:]

        for d in devices where d.connected && d.charging != true {
            let tier = BatteryTier.of(d.level, warn: warn, critical: critical)
            let previous = BatteryTier(rawValue: tiers[d.id] ?? 0) ?? .ok

            switch tier {
            case .critical:
                let last = lastCritical[d.id] ?? 0
                if previous != .critical || Date().timeIntervalSince1970 - last > repeatCritical {
                    send(d, critical: true)
                    lastCritical[d.id] = Date().timeIntervalSince1970
                }
                tiers[d.id] = BatteryTier.critical.rawValue
            case .low:
                if previous == .ok { send(d, critical: false) }
                if previous != .critical { tiers[d.id] = BatteryTier.low.rawValue }
            case .ok:
                // Small hysteresis so a value jumping between 20 and 21 % does not re-arm the warning.
                if d.level > warn + 5 {
                    tiers[d.id] = BatteryTier.ok.rawValue
                    lastCritical[d.id] = nil
                }
            }
        }
        defaults.set(tiers, forKey: "alertTiers")
        defaults.set(lastCritical, forKey: "lastCriticalAlert")
    }

    func sendTest() {
        send(DeviceBattery(id: "test", name: L("Test device"), kind: .other, level: 15,
                           updated: .now, connected: true), critical: false)
    }

    private func send(_ d: DeviceBattery, critical: Bool) {
        let content = UNMutableNotificationContent()
        content.title = String(format: L(critical ? "%@ is almost empty" : "%@ battery low"), d.name)
        content.body = String(format: L(critical ? "Only %d %% left. Replace the batteries now." : "%d %% left. Have new batteries ready."), d.level)
        content.sound = .default
        if critical { content.interruptionLevel = .timeSensitive }
        let req = UNNotificationRequest(identifier: "battery-\(d.id)", content: content, trigger: nil)
        center.add(req)
    }
}
