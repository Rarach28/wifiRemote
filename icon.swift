// Draws the app icon: a white remote under Wi-Fi waves on a deep blue glass tile.
// Usage: swift icon.swift <out.png>
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let navy = NSColor(red: 0.07, green: 0.10, blue: 0.24, alpha: 1)

// Tile: blue gradient, a glassy highlight over the top half and a thin light rim.
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.20, green: 0.30, blue: 0.62, alpha: 1),
                    NSColor(red: 0.04, green: 0.06, blue: 0.17, alpha: 1)])!.draw(in: tile, angle: -90)
NSGraphicsContext.saveGraphicsState()
tile.addClip()
NSGradient(colors: [NSColor(white: 1, alpha: 0.22), NSColor(white: 1, alpha: 0)])!
    .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
NSGraphicsContext.restoreGraphicsState()
NSColor(white: 1, alpha: 0.30).setStroke()
tile.lineWidth = 6
tile.stroke()

// Remote body: a tall white capsule with a soft shadow.
let body = NSBezierPath(roundedRect: NSRect(x: 402, y: 150, width: 220, height: 560), xRadius: 110, yRadius: 110)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSColor.white.setFill()
body.fill()
NSGraphicsContext.restoreGraphicsState()

// Buttons cut into the body in the tile's navy: the D-pad ring with its OK button, two pairs of keys and a
// volume rocker.
func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}
navy.setFill()
let ring = circle(512, 590, 82)
ring.append(circle(512, 590, 34).reversed)
ring.fill()
for (x, y) in [(462.0, 462.0), (562.0, 462.0), (462.0, 382.0), (562.0, 382.0)] { circle(x, y, 24).fill() }
NSBezierPath(roundedRect: NSRect(x: 488, y: 200, width: 48, height: 130), xRadius: 24, yRadius: 24).fill()

// Wi-Fi waves above the remote.
for (i, radius) in [70.0, 130.0, 190.0].enumerated() {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: 512, y: 700), radius: radius, startAngle: 52, endAngle: 128)
    arc.lineWidth = 30
    arc.lineCapStyle = .round
    NSColor(white: 1, alpha: 1 - Double(i) * 0.18).setStroke()
    arc.stroke()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
