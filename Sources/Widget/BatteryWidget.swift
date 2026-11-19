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

struct BatteryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BatteryEntry

    var body: some View {
        Group {
            if let s = entry.snapshot, !s.devices.isEmpty {
                switch family {
                case .systemSmall: SmallView(snapshot: s)
                default: MediumView(snapshot: s)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "battery.0percent").font(.title2).foregroundStyle(.secondary)
                    Text(L("Open InputBattery to see your devices."))
                        .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

private func color(_ d: DeviceBattery, _ s: Snapshot) -> Color {
    switch BatteryTier.of(d.level, warn: s.warnLevel, critical: s.criticalLevel) {
    case .critical: .red
    case .low: .orange
    case .ok: .green
    }
}

struct SmallView: View {
    let snapshot: Snapshot
    var body: some View {
        let shown = Array(snapshot.devices.prefix(2))
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ForEach(shown) { d in Ring(device: d, color: color(d, snapshot)) }
            }
            if let worst = snapshot.devices.filter(\.connected).min(by: { $0.level < $1.level }),
               BatteryTier.of(worst.level, warn: snapshot.warnLevel, critical: snapshot.criticalLevel) != .ok {
                Label(L("Replace batteries"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold)).foregroundStyle(color(worst, snapshot))
            }
        }
    }
}

struct Ring: View {
    let device: DeviceBattery
    let color: Color
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 6)
                Circle().trim(from: 0, to: CGFloat(device.level) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: device.kind.symbol).font(.system(size: 17, weight: .medium))
            }
            .frame(width: 54, height: 54)
            .opacity(device.connected ? 1 : 0.45)
            Text("\(device.level) %").font(.callout.weight(.semibold)).monospacedDigit()
        }
    }
}

struct MediumView: View {
    let snapshot: Snapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(snapshot.devices.prefix(3)) { d in
                HStack(spacing: 10) {
                    Image(systemName: d.kind.symbol).font(.title3).frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(d.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            Spacer()
                            Text("\(d.level) %").font(.subheadline.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(color(d, snapshot))
                        }
                        Gauge(value: Double(d.level), in: 0...100) { EmptyView() }
                            .gaugeStyle(.linearCapacity)
                            .tint(color(d, snapshot))
                        if !d.connected {
                            Text(L("not connected")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .opacity(d.connected ? 1 : 0.55)
            }
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
