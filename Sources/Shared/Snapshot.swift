import Foundation

/// Kind of input device, used to pick an icon.
enum DeviceKind: String, Codable {
    case keyboard, mouse, trackpad, other

    var symbol: String {
        switch self {
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .other: return "dot.radiowaves.left.and.right"
        }
    }
}

/// Last known battery state of one Bluetooth device.
struct DeviceBattery: Codable, Identifiable, Hashable {
    var id: String          // CoreBluetooth peripheral identifier
    var name: String
    var kind: DeviceKind
    var level: Int          // 0…100
    var updated: Date
    var connected: Bool
}

/// What the app writes and the widget reads.
struct Snapshot: Codable {
    var devices: [DeviceBattery]
    var warnLevel: Int
    var criticalLevel: Int
    var written: Date

    static let placeholder = Snapshot(
        devices: [
            DeviceBattery(id: "1", name: "Keyboard", kind: .keyboard, level: 80, updated: .now, connected: true),
            DeviceBattery(id: "2", name: "Mouse", kind: .mouse, level: 15, updated: .now, connected: true),
        ],
        warnLevel: 20, criticalLevel: 10, written: .now)
}

enum BatteryTier: Int {
    case ok = 0, low = 1, critical = 2

    static func of(_ level: Int, warn: Int, critical: Int) -> BatteryTier {
        if level <= critical { return .critical }
        if level <= warn { return .low }
        return .ok
    }
}

/// Shared JSON file in ~/Library/Application Support/InputBattery/.
/// The sandboxed widget may read it through a home-relative file exception.
enum SharedStore {
    static let folderName = "InputBattery"

    /// The real home folder, also when running inside the widget's sandbox container.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static var fileURL: URL {
        realHome.appendingPathComponent("Library/Application Support/\(folderName)/status.json")
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Snapshot.self, from: data)
    }

    static func save(_ snapshot: Snapshot) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Localized string from the bundle's Localizable.strings.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}
