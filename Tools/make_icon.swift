// Draws the app icon into <out>/AppIcon.iconset
import AppKit
let out = CommandLine.arguments.dropFirst().first ?? "Resources"
let set = URL(fileURLWithPath: out).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.45, alpha: 1),
               ending: NSColor(calibratedRed: 0.05, green: 0.50, blue: 0.40, alpha: 1))!.draw(in: path, angle: -90)
    func symbol(_ name: String, _ size: CGFloat, _ center: NSPoint) {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
        let r = NSRect(x: center.x - img.size.width / 2, y: center.y - img.size.height / 2, width: img.size.width, height: img.size.height)
        img.draw(in: r)
    }
    symbol("keyboard", s * 0.22, NSPoint(x: s * 0.40, y: s * 0.62))
    symbol("computermouse", s * 0.20, NSPoint(x: s * 0.68, y: s * 0.60))
    symbol("battery.75percent", s * 0.26, NSPoint(x: s * 0.5, y: s * 0.33))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: set.appendingPathComponent("icon_\(name).png"))
}
