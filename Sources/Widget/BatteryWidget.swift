import SwiftUI
import WidgetKit

struct BatteryEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(BatteryEntry(date: .now, snapshot: context.isPreview ? (SharedStore.load() ?? .placeholder) : SharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        // The app reloads the widget on every change; this is only a fallback.
        let entry = BatteryEntry(date: .now, snapshot: SharedStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

// MARK: - Neon palette

enum Neon {
    static let cyan = Color(red: 0.0, green: 0.92, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.16, blue: 0.72)
    static let amber = Color(red: 1.0, green: 0.68, blue: 0.0)
    static let red = Color(red: 1.0, green: 0.14, blue: 0.28)
    static let dim = Color(red: 0.55, green: 0.62, blue: 0.75)

    static func color(_ d: DeviceBattery, _ s: Snapshot) -> Color {
        switch BatteryTier.of(d.level, warn: s.warnLevel, critical: s.criticalLevel) {
        case .critical: red
        case .low: amber
        case .ok: cyan
        }
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private extension DeviceKind {
    var tag: String {
        switch self {
        case .keyboard: "KBD"
        case .mouse: "MSE"
        case .trackpad: "TRK"
        case .other: "DEV"
        }
    }
}

private extension View {
    /// Soft neon glow.
    func glow(_ color: Color, radius: CGFloat = 3) -> some View {
        shadow(color: color.opacity(0.85), radius: radius)
    }
}

// MARK: - Background

/// Thin horizontal CRT scanlines.
struct Scanlines: Shape {
    var spacing: CGFloat = 3
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var y: CGFloat = 0
        while y < rect.height {
            p.addRect(CGRect(x: 0, y: y, width: rect.width, height: 1))
            y += spacing
        }
        return p
    }
}

/// Corner brackets like a HUD frame.
struct HUDCorners: Shape {
    var length: CGFloat = 10
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l = length
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.maxX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - l, y: r.maxY))
        p.move(to: CGPoint(x: r.minX + l, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - l))
        return p
    }
}

struct NeonBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.03, blue: 0.10).opacity(0.55),
                         Color(red: 0.14, green: 0.0, blue: 0.20).opacity(0.40)],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            Scanlines().fill(Neon.cyan.opacity(0.05))
        }
    }
}

// MARK: - Widget views

struct BatteryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BatteryEntry

    var body: some View {
        ZStack {
            HUDCorners().stroke(Neon.cyan.opacity(0.5), lineWidth: 1.2).padding(-6)
            if let s = entry.snapshot, !s.devices.isEmpty {
                switch family {
                case .systemSmall: SmallView(snapshot: s)
                default: MediumView(snapshot: s)
                }
            } else {
                VStack(spacing: 6) {
                    Text("NO SIGNAL").font(Neon.mono(13, .bold)).foregroundStyle(Neon.magenta).glow(Neon.magenta)
                    Text(L("Open InputBattery to see your devices."))
                        .font(Neon.mono(9)).multilineTextAlignment(.center).foregroundStyle(Neon.dim)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { NeonBackground() }
    }
}

/// Header line: "▚ INPUT.POWER        21:45"
struct HUDHeader: View {
    let snapshot: Snapshot
    var compact = false
    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(Neon.magenta).frame(width: 3, height: 9).glow(Neon.magenta, radius: 2)
            Text(compact ? "PWR" : "INPUT.POWER")
                .font(Neon.mono(9, .bold)).tracking(1.5)
                .foregroundStyle(Neon.magenta).glow(Neon.magenta, radius: 2)
            Spacer(minLength: 4)
            Text(snapshot.written, style: .time)
                .font(Neon.mono(8)).foregroundStyle(Neon.dim)
        }
    }
}

/// Segmented bar, filled in proportion to 100 %.
struct SegmentBar: View {
    let level: Int
    let color: Color
    var segments = 20

    var body: some View {
        let lit = level <= 0 ? 0 : max(1, Int((Double(level) / 100 * Double(segments)).rounded()))
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                Rectangle()
                    .fill(i < lit ? color : color.opacity(0.13))
                    .shadow(color: i < lit ? color.opacity(0.8) : .clear, radius: 2.5)
            }
        }
        .frame(height: 8)
    }
}

struct SmallView: View {
    let snapshot: Snapshot
    var body: some View {
        VStack(spacing: 8) {
            HUDHeader(snapshot: snapshot, compact: true)
            HStack(spacing: 12) {
                ForEach(Array(snapshot.devices.prefix(2))) { d in
                    NeonRing(device: d, color: Neon.color(d, snapshot))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct NeonRing: View {
    let device: DeviceBattery
    let color: Color
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle().stroke(color.opacity(0.15), style: StrokeStyle(lineWidth: 5, dash: [2.5, 2]))
                Circle().trim(from: 0, to: CGFloat(device.level) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, dash: [2.5, 2]))
                    .rotationEffect(.degrees(-90))
                    .glow(color)
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(color).glow(color, radius: 2)
            }
            .frame(width: 52, height: 52)
            Text("\(device.level)%")
                .font(Neon.mono(13, .bold)).foregroundStyle(color).glow(color, radius: 2)
            Text(device.connected ? device.kind.tag : "OFFLINE")
                .font(Neon.mono(8)).tracking(1.5).foregroundStyle(Neon.dim)
        }
        .opacity(device.connected ? 1 : 0.5)
    }
}

struct MediumView: View {
    let snapshot: Snapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HUDHeader(snapshot: snapshot)
            ForEach(Array(snapshot.devices.prefix(3))) { d in
                let color = Neon.color(d, snapshot)
                HStack(spacing: 10) {
                    Image(systemName: d.kind.symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(color).glow(color, radius: 2)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(d.kind.tag).font(Neon.mono(8, .bold)).tracking(1)
                                .foregroundStyle(Neon.magenta)
                            Text(d.name.uppercased()).font(Neon.mono(10, .medium)).tracking(0.5)
                                .foregroundStyle(.white.opacity(0.88)).lineLimit(1)
                            Spacer(minLength: 4)
                            if !d.connected {
                                Text("OFFLINE").font(Neon.mono(8)).foregroundStyle(Neon.dim)
                            }
                            Text("\(d.level)%").font(Neon.mono(12, .bold))
                                .foregroundStyle(color).glow(color, radius: 2)
                        }
                        SegmentBar(level: d.level, color: color)
                    }
                }
                .opacity(d.connected ? 1 : 0.5)
            }
            Spacer(minLength: 0)
        }
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InputBatteryWidget", provider: Provider()) { entry in
            BatteryWidgetView(entry: entry)
        }
        .configurationDisplayName(L("Keyboard & Mouse Battery"))
        .description(L("Battery level of your Bluetooth keyboard and mouse."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BatteryWidgetBundle: WidgetBundle {
    var body: some Widget { BatteryWidget() }
}
