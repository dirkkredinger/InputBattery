import Foundation
import IOKit.ps

/// Battery levels macOS itself knows: Apple accessories (AirPods and their case,
/// AirPods Max, Magic Keyboard/Mouse/Trackpad) and Bluetooth headsets that report
/// their battery over the hands-free profile.
///
/// macOS keeps them as accessory power sources – the same list `pmset -g accps` prints and the system
/// Batteries widget shows. This class reads that list whenever it changes.
final class AppleDeviceSource {
    static let idPrefix = "apple-"

    /// Called on the main queue with the currently visible Apple devices.
    var onUpdate: (([DeviceBattery]) -> Void)?

    /// Devices that left the list stay visible (greyed out) this long.
    private let keepOffline: TimeInterval = 12 * 3600
    private var known: [String: DeviceBattery] = [:]
    private var timer: Timer?
    private var runLoopSource: CFRunLoopSource?

    /// `IOPSCopyPowerSourcesByType` is not in the public headers; it is the call
    /// `pmset -g accps` uses to list accessory batteries (type 0 = accessories).
    private typealias CopyByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
    private static let copyByType: CopyByType? = {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let sym = dlsym(h, "IOPSCopyPowerSourcesByType") else { return nil }
        return unsafeBitCast(sym, to: CopyByType.self)
    }()

    init(previous: [DeviceBattery]) {
        // Ids with ":" came from an older version (Bluetooth address); skip them.
        for d in previous where d.id.hasPrefix(Self.idPrefix) && !d.id.contains(":") {
            var d = d
            d.connected = false
            d.charging = nil
            known[d.id] = d
        }
    }

    func start() {
        poll()
        // Fires when any power source changes; the timer is only a fallback.
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<AppleDeviceSource>.fromOpaque(ctx).takeUnretainedValue().poll()
        }, ctx)?.takeRetainedValue() {
            runLoopSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.poll() }
    }

    func poll() {
        guard let copy = Self.copyByType, let info = copy(0)?.takeRetainedValue() else { return }
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        let now = Date()
        var present = Set<String>()

        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let name = d[kIOPSNameKey] as? String,
                  let current = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let level = max > 0 ? Swift.min(100, current * 100 / max) : current
            let accessoryID = d["Accessory Identifier"] as? String ?? name
            let partID = d["Part Identifier"] as? String
            let category = d["Accessory Category"] as? String ?? ""
            let isCase = partID == "Case" || category.localizedCaseInsensitiveContains("case")

            // AirPods: "Combined" lists left and right earbud as parts.
            var parts: [BatteryPart]? = nil
            if let combined = d["Combined Parts"] as? [[String: Any]] {
                parts = combined.compactMap { p in
                    guard let c = p[kIOPSCurrentCapacityKey] as? Int else { return nil }
                    switch p["Part Identifier"] as? String {
                    case "Left": return BatteryPart(label: "L", level: c)
                    case "Right": return BatteryPart(label: "R", level: c)
                    default: return nil
                    }
                }
                if parts?.isEmpty == true { parts = nil }
            }
            let headline = parts?.map(\.level).min() ?? level

            let id = Self.idPrefix + accessoryID
            present.insert(id)
            let kind = Self.kind(name: name, category: category, isCase: isCase)
            known[id] = DeviceBattery(
                id: id,
                name: name,
                kind: kind, level: headline, updated: now,
                connected: d[kIOPSIsPresentKey] as? Bool ?? true,
                parts: parts,
                charging: d[kIOPSIsChargingKey] as? Bool)
        }

        // Devices that went out of range: keep the last value for a while.
        for (id, var d) in known where !present.contains(id) {
            if now.timeIntervalSince(d.updated) > keepOffline {
                known[id] = nil
            } else if d.connected || d.charging != nil {
                d.connected = false
                d.charging = nil
                known[id] = d
            }
        }
        let result = Array(known.values)
        DispatchQueue.main.async { self.onUpdate?(result) }
    }

    private static func kind(name: String, category: String, isCase: Bool) -> DeviceKind {
        let n = name.lowercased()
        if isCase { return n.contains("pro") ? .airpodsProCase : .airpodsCase }
        let c = category.lowercased()
        if c.contains("keyboard") { return .keyboard }
        if c.contains("trackpad") { return .trackpad }
        if c.contains("mouse") { return .mouse }
        if n.contains("airpods max") { return .airpodsMax }
        if n.contains("airpods pro") { return .airpodsPro }
        if n.contains("airpods") { return .airpods }
        if c.contains("head") || c.contains("audio") { return .headphones }
        return .other
    }
}
