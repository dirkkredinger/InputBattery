// Renders the promo images for the README with demo data:
//   Docs/screenshot(-de).png  – menu bar, menu and widgets on a desktop
//   Docs/demo(-de).gif        – the mouse running low, widget and menu bar change colour, warnings appear
// Built and run by Tools/make_promo.sh together with the widget sources.
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Texts

struct Texts {
    let de: Bool
    var clock: String { de ? "Do. 21:42" : "Thu 9:42 PM" }
    func updated(_ s: String) -> String { de ? "aktualisiert vor \(s)" : "updated \(s) ago" }
    var charging: String { de ? "lädt" : "charging" }
    var warnAt: String { de ? "Warnen bei: 20 %" : "Warn at: 20 %" }
    var criticalAt: String { de ? "Kritisch bei: 10 %" : "Critical at: 10 %" }
    var login: String { de ? "Bei Anmeldung öffnen" : "Open at Login" }
    var refresh: String { de ? "Jetzt aktualisieren" : "Refresh Now" }
    var about: String { de ? "Über InputBattery" : "About InputBattery" }
    var kofi: String { de ? "Auf Ko-fi unterstützen ♥" : "Support on Ko-fi ♥" }
    var quit: String { de ? "InputBattery beenden" : "Quit InputBattery" }
    func lowTitle(_ n: String) -> String { de ? "\(n): Batterie schwach" : "\(n) battery low" }
    func lowBody(_ l: Int) -> String { de ? "Noch \(l) %. Leg schon mal neue Batterien bereit." : "\(l) % left. Have new batteries ready." }
    func critTitle(_ n: String) -> String { de ? "\(n) ist fast leer" : "\(n) is almost empty" }
    func critBody(_ l: Int) -> String { de ? "Nur noch \(l) %. Bitte jetzt die Batterien wechseln." : "Only \(l) % left. Replace the batteries now." }
    var now: String { de ? "Jetzt" : "now" }
}

// MARK: - Demo data

func demoSnapshot(mouse: Int = 18) -> Snapshot {
    // Same time as the clock in the mocked menu bar.
    let now = Calendar.current.date(bySettingHour: 21, minute: 42, second: 0, of: Date()) ?? Date()
    return Snapshot(devices: [
        DeviceBattery(id: "k", name: "UGREEN-K552", kind: .keyboard, level: 80, updated: now, connected: true),
        DeviceBattery(id: "m", name: "UGREEN BLE Mouse", kind: .mouse, level: mouse, updated: now, connected: true),
        DeviceBattery(id: "a", name: "AirPods Pro", kind: .airpodsPro, level: 100, updated: now, connected: true,
                      parts: [BatteryPart(label: "L", level: 100), BatteryPart(label: "R", level: 100)], charging: true),
        DeviceBattery(id: "h", name: "G-96", kind: .headphones, level: 64, updated: now, connected: true),
        DeviceBattery(id: "c", name: "AirPods Pro Case", kind: .airpodsProCase, level: 86, updated: now, connected: true),
    ], warnLevel: 20, criticalLevel: 10, written: now)
}

/// Colours like the real menu bar: plain when fine, orange when low, red when critical.
func menuColor(_ d: DeviceBattery, _ s: Snapshot) -> Color {
    switch BatteryTier.of(d.level, warn: s.warnLevel, critical: s.criticalLevel) {
    case .critical: Color(nsColor: .systemRed)
    case .low: Color(nsColor: .systemOrange)
    case .ok: .white
    }
}

// MARK: - Desktop pieces

struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.12),
                                    Color(red: 0.10, green: 0.04, blue: 0.20),
                                    Color(red: 0.22, green: 0.05, blue: 0.22)],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(Color(red: 1, green: 0.2, blue: 0.6).opacity(0.35)).frame(width: 420).blur(radius: 120).offset(x: -260, y: 220)
            Circle().fill(Color(red: 0, green: 0.8, blue: 1).opacity(0.28)).frame(width: 480).blur(radius: 140).offset(x: 330, y: -60)
            Circle().fill(Color(red: 1, green: 0.55, blue: 0.1).opacity(0.18)).frame(width: 300).blur(radius: 110).offset(x: 120, y: 260)
            // City skyline
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<36, id: \.self) { i in
                    let h = CGFloat([60, 120, 90, 180, 70, 140, 220, 100, 160, 80, 130, 200][i % 12])
                    Rectangle().fill(Color.black.opacity(0.55)).frame(width: CGFloat(18 + (i * 7) % 22), height: h)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .clipped()
        }
        .clipped()
    }
}

struct MenuBarStrip: View {
    let snapshot: Snapshot
    let t: Texts
    var highlighted = true
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "apple.logo").font(.system(size: 13))
            Text("Finder").font(.system(size: 13, weight: .bold))
            Spacer()
            HStack(spacing: 10) {
                ForEach(snapshot.devices) { d in
                    HStack(spacing: 3) {
                        Image(systemName: d.kind.symbol).font(.system(size: 12))
                        Text("\(d.level) %" + (d.charging == true ? "⚡︎" : "")).font(.system(size: 13))
                    }
                    .foregroundStyle(menuColor(d, snapshot))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(highlighted ? 0.2 : 0)))
            Image(systemName: "wifi").font(.system(size: 13))
            Image(systemName: "switch.2").font(.system(size: 12))
            Text(t.clock).font(.system(size: 13))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(Color.black.opacity(0.35))
    }
}

struct MenuMock: View {
    let snapshot: Snapshot
    let t: Texts
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(snapshot.devices) { d in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: d.kind.symbol).font(.system(size: 13)).frame(width: 20).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 10) {
                            Text(d.name).font(.system(size: 13))
                            Text("\(d.level) %").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(menuColor(d, snapshot))
                        }
                        if let parts = d.parts {
                            Text(parts.map { "\($0.label) \($0.level) %" }.joined(separator: " · "))
                                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                        }
                        Text((d.charging == true ? t.charging + " · " : "") + t.updated(d.id == "m" ? "1 min" : "30 s"))
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.vertical, 4)
            }
            Divider().overlay(Color.white.opacity(0.15)).padding(.vertical, 5)
            ForEach([t.warnAt, t.criticalAt], id: \.self) { s in
                HStack { Text(s); Spacer(); Image(systemName: "chevron.right").font(.system(size: 10)) }.padding(.vertical, 3)
            }
            HStack(spacing: 6) { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)); Text(t.login) }
                .padding(.vertical, 3).padding(.leading, -16)
            Divider().overlay(Color.white.opacity(0.15)).padding(.vertical, 5)
            HStack { Text(t.refresh); Spacer(); Text("⌘R").foregroundStyle(.white.opacity(0.45)) }.padding(.vertical, 3)
            Text(t.about).padding(.vertical, 3)
            Text(t.kofi).padding(.vertical, 3)
            Divider().overlay(Color.white.opacity(0.15)).padding(.vertical, 5)
            HStack { Text(t.quit); Spacer(); Text("⌘Q").foregroundStyle(.white.opacity(0.45)) }.padding(.vertical, 3)
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 22).padding(.vertical, 10)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color(red: 0.13, green: 0.12, blue: 0.17).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
}

/// A widget as it sits on the desktop.
struct WidgetFrame<Content: View>: View {
    let width: CGFloat, height: CGFloat
    @ViewBuilder let content: Content
    var body: some View {
        ZStack {
            NeonBackground()
            ZStack {
                HUDCorners().stroke(Neon.cyan.opacity(0.5), lineWidth: 1.2).padding(-6)
                content
            }
            .padding(16)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08)))
        .environment(\.colorScheme, .dark)
    }
}

struct NotificationBanner: View {
    let title: String
    let message: String
    let t: Texts
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: NSImage(contentsOfFile: "Sources/App/AppIcon.icns") ?? NSImage())
                .resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(t.now).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                Text(message).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.16, green: 0.15, blue: 0.2).opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
    }
}

// MARK: - Scenes

struct ScreenshotScene: View {
    let t: Texts
    var body: some View {
        let s = demoSnapshot()
        VStack(spacing: 0) {
            MenuBarStrip(snapshot: s, t: t)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 20) {
                        WidgetFrame(width: 344, height: 160) { MediumView(snapshot: s, maxRows: 5) }
                        WidgetFrame(width: 160, height: 160) { SmallView(snapshot: s) }
                    }
                    WidgetFrame(width: 690, height: 300) { ExtraLargeView(snapshot: s) }
                }
                .padding(.top, 40).padding(.leading, 40)
                Spacer(minLength: 0)
                MenuMock(snapshot: s, t: t)
                    .padding(.top, 6).padding(.trailing, 150)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 1280, height: 600)
        .background(Wallpaper())
    }
}

/// One frame of the demo: the mouse runs low.
struct DemoScene: View {
    let t: Texts
    let mouse: Int
    let banner: (String, String)?
    var body: some View {
        let s = demoSnapshot(mouse: mouse)
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                MenuBarStrip(snapshot: s, t: t, highlighted: false)
                Spacer()
            }
            WidgetFrame(width: 344, height: 160) { MediumView(snapshot: s, maxRows: 5) }
                .padding(.top, 110)
            if let banner {
                HStack {
                    Spacer()
                    NotificationBanner(title: banner.0, message: banner.1, t: t)
                }
                .padding(.top, 36).padding(.trailing, 12)
            }
        }
        .frame(width: 760, height: 320)
        .background(Wallpaper())
    }
}

// MARK: - Output

@MainActor
func render<V: View>(_ view: V, scale: CGFloat) -> CGImage? {
    let r = ImageRenderer(content: view)
    r.scale = scale
    return r.cgImage
}

@MainActor
func writePNG<V: View>(_ view: V, to path: String) {
    guard let img = render(view, scale: 2) else { return }
    let rep = NSBitmapImageRep(cgImage: img)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    print("wrote", path)
}

@MainActor
func writeGIF(frames: [(DemoScene, Double)], to path: String) {
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                     UTType.gif.identifier as CFString, frames.count, nil) else { return }
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (scene, delay) in frames {
        guard let img = render(scene, scale: 1.5) else { continue }
        CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    CGImageDestinationFinalize(dest)
    print("wrote", path)
}

@main
struct Promo {
    static func main() {
        MainActor.assumeIsolated {
            for de in [false, true] {
                let t = Texts(de: de)
                let suffix = de ? "-de" : ""
                writePNG(ScreenshotScene(t: t), to: "Docs/screenshot\(suffix).png")

                let mouse = "UGREEN BLE Mouse"
                var frames: [(DemoScene, Double)] = []
                frames.append((DemoScene(t: t, mouse: 26, banner: nil), 1.2))
                for l in [25, 24, 23, 22, 21] { frames.append((DemoScene(t: t, mouse: l, banner: nil), 0.35)) }
                frames.append((DemoScene(t: t, mouse: 20, banner: (t.lowTitle(mouse), t.lowBody(20))), 2.6))
                for l in [19, 17, 15, 13, 11] { frames.append((DemoScene(t: t, mouse: l, banner: nil), 0.35)) }
                frames.append((DemoScene(t: t, mouse: 10, banner: (t.critTitle(mouse), t.critBody(10))), 3.0))
                frames.append((DemoScene(t: t, mouse: 10, banner: nil), 1.2))
                writeGIF(frames: frames, to: "Docs/demo\(suffix).gif")
            }
        }
    }
}
