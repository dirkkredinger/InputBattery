import Foundation
import CoreBluetooth
import IOKit.hid

/// Reads the standard Bluetooth "Battery Service" (0x180F) of every connected
/// device that offers it, and keeps listening for changes.
final class BatteryMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    /// Called on the main queue whenever something changed.
    var onChange: (([DeviceBattery]) -> Void)?
    private(set) var bluetoothState: CBManagerState = .unknown

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var levelChars: [UUID: CBCharacteristic] = [:]
    private(set) var devices: [String: DeviceBattery] = [:]
    private var scanTimer: Timer?
    private var readTimer: Timer?

    init(previous: [DeviceBattery]) {
        super.init()
        for d in previous {
            var d = d
            d.connected = false
            devices[d.id] = d
        }
        central = CBCentralManager(delegate: self, queue: .main)
        // Look for newly connected devices every minute, re-read all levels every 10 minutes.
        scanTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.discover() }
        readTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in self?.readAll() }
    }

    var sortedDevices: [DeviceBattery] {
        devices.values.sorted { ($0.kind.sortKey, $0.name) < ($1.kind.sortKey, $1.name) }
    }

    func refresh() {
        discover()
        readAll()
    }

    func forget(_ id: String) {
        devices[id] = nil
        notify()
    }

    // MARK: Discovery

    private func discover() {
        guard central.state == .poweredOn else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        let connectedIDs = Set(connected.map(\.identifier))
        for p in connected where peripherals[p.identifier] == nil {
            peripherals[p.identifier] = p
            p.delegate = self
            central.connect(p)
        }
        // Devices the system no longer lists as connected.
        for (id, p) in peripherals where !connectedIDs.contains(id) && p.state != .connected {
            markDisconnected(id)
        }
    }

    private func readAll() {
        for (id, ch) in levelChars {
            peripherals[id]?.readValue(for: ch)
        }
    }

    private func markDisconnected(_ id: UUID) {
        peripherals[id] = nil
        levelChars[id] = nil
        if devices[id.uuidString]?.connected == true {
            devices[id.uuidString]?.connected = false
            notify()
        }
    }

    private func notify() {
        onChange?(sortedDevices)
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        if central.state == .poweredOn {
            discover()
        } else {
            for id in Array(peripherals.keys) { markDisconnected(id) }
        }
        notify()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        markDisconnected(peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        markDisconnected(peripheral.identifier)
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] where s.uuid == Self.batteryService {
            peripheral.discoverCharacteristics([Self.batteryLevel], for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] where ch.uuid == Self.batteryLevel {
            levelChars[peripheral.identifier] = ch
            if ch.properties.contains(.notify) { peripheral.setNotifyValue(true, for: ch) }
            peripheral.readValue(for: ch)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == Self.batteryLevel,
              let byte = characteristic.value?.first else { return }
        let id = peripheral.identifier.uuidString
        let name = peripheral.name ?? devices[id]?.name ?? "Bluetooth"
        devices[id] = DeviceBattery(
            id: id, name: name,
            kind: DeviceKindResolver.kind(forName: name),
            level: min(100, Int(byte)), updated: .now, connected: true)
        notify()
    }
}

private extension DeviceKind {
    var sortKey: Int {
        switch self { case .keyboard: 0; case .mouse: 1; case .trackpad: 2; case .other: 3 }
    }
}

/// Finds out whether a Bluetooth device is a keyboard or a mouse by looking up its
/// HID entry in the I/O Registry (no special permission needed).
enum DeviceKindResolver {
    static func kind(forName name: String) -> DeviceKind {
        if let k = kindFromRegistry(name) { return k }
        let n = name.lowercased()
        if n.contains("keyboard") || n.contains("tastatur") { return .keyboard }
        if n.contains("mouse") || n.contains("maus") { return .mouse }
        if n.contains("trackpad") { return .trackpad }
        return .other
    }

    private static func kindFromRegistry(_ name: String) -> DeviceKind? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            func prop(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard let product = prop(kIOHIDProductKey) as? String,
                  product.trimmingCharacters(in: .whitespaces) == name.trimmingCharacters(in: .whitespaces),
                  prop(kIOHIDPrimaryUsagePageKey) as? Int == kHIDPage_GenericDesktop,
                  let usage = prop(kIOHIDPrimaryUsageKey) as? Int else { continue }
            // Keyboards and mice usually report both collections; the primary usage tells them apart.
            switch usage {
            case kHIDUsage_GD_Keyboard, kHIDUsage_GD_Keypad: return .keyboard
            case kHIDUsage_GD_Mouse, kHIDUsage_GD_Pointer: return .mouse
            default: continue
            }
        }
        return nil
    }
}
