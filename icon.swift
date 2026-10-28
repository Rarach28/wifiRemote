// Draws the app icon: a remote glyph on a deep blue glass tile. Usage: swift icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.16, green: 0.22, blue: 0.48, alpha: 1),
                    NSColor(red: 0.04, green: 0.06, blue: 0.16, alpha: 1)])!.draw(in: path, angle: -90)
// A soft highlight across the top half, like light on glass.
NSGraphicsContext.saveGraphicsState()
path.addClip()
NSGradient(colors: [NSColor(white: 1, alpha: 0.28), NSColor(white: 1, alpha: 0)])!
    .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
NSGraphicsContext.restoreGraphicsState()
NSColor(white: 1, alpha: 0.35).setStroke()
path.lineWidth = 6
path.stroke()
let config = NSImage.SymbolConfiguration(pointSize: 470, weight: .regular)
    .applying(.init(paletteColors: [.white]))
if let glyph = NSImage(systemSymbolName: "appletv.remote.gen4.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let g = glyph.size
    glyph.draw(in: NSRect(x: (size - g.width) / 2, y: (size - g.height) / 2, width: g.width, height: g.height))
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
