// Draws the Hatch app icon and writes assets/icon-1024.png plus assets/Hatch.iconset.
// Usage: swift scripts/make-icon.swift   (scripts/make-icon.sh then builds assets/Hatch.icns)
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

func newContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func drawMaster() -> CGImage {
    let ctx = newContext(1024)

    // macOS icon body: 824pt square inside the 1024 canvas, with a soft drop shadow.
    let body = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x000000, 0.4))
    ctx.addPath(body); ctx.setFillColor(color(0x1a1b3a)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body); ctx.clip()

    // Background: indigo, lighter at the top.
    ctx.drawLinearGradient(gradient([(0, color(0x4a4fa8)), (1, color(0x15162f))]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    let cx: CGFloat = 512
    let slotTop: CGFloat = 338

    // Light pouring out of the opening, and a soft pool of it around the slot.
    let beam = CGMutablePath()
    beam.move(to: CGPoint(x: cx - 210, y: slotTop))
    beam.addLine(to: CGPoint(x: cx + 210, y: slotTop))
    beam.addLine(to: CGPoint(x: cx + 330, y: 930))
    beam.addLine(to: CGPoint(x: cx - 330, y: 930))
    beam.closeSubpath()
    ctx.saveGState()
    ctx.addPath(beam); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, color(0xffffff, 0.85)), (0.35, color(0x9cc2ff, 0.4)), (1, color(0x5b9cf5, 0))]),
                           start: CGPoint(x: cx, y: slotTop), end: CGPoint(x: cx, y: 930), options: [])
    ctx.restoreGState()
    ctx.drawRadialGradient(gradient([(0, color(0xffffff, 0.9)), (0.2, color(0xa9c9ff, 0.5)), (0.6, color(0x5b9cf5, 0.12)), (1, color(0x5b9cf5, 0))]),
                           startCenter: CGPoint(x: cx, y: slotTop), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: slotTop), endRadius: 430, options: [])

    // Rising chevrons: "launch", and also a shell prompt turned upright.
    func chevron(y: CGFloat, half: CGFloat, rise: CGFloat, width: CGFloat, alpha: CGFloat) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: cx - half, y: y))
        p.addLine(to: CGPoint(x: cx, y: y + rise))
        p.addLine(to: CGPoint(x: cx + half, y: y))
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 30, color: color(0x9cc2ff, 0.9))
        ctx.addPath(p)
        ctx.setStrokeColor(color(0xffffff, alpha)); ctx.setLineWidth(width)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }
    chevron(y: 436, half: 150, rise: 120, width: 58, alpha: 1)
    chevron(y: 578, half: 118, rise: 94, width: 46, alpha: 0.7)
    chevron(y: 692, half: 88, rise: 70, width: 36, alpha: 0.38)

    // The opening in the deck, lit from inside.
    let slot = CGPath(roundedRect: CGRect(x: cx - 270, y: slotTop - 80, width: 540, height: 80), cornerWidth: 30, cornerHeight: 30, transform: nil)
    ctx.saveGState()
    ctx.addPath(slot); ctx.clip()
    ctx.drawLinearGradient(gradient([(0, color(0xffffff)), (0.3, color(0xbad2ff)), (1, color(0x2a2d6a))]),
                           start: CGPoint(x: cx, y: slotTop), end: CGPoint(x: cx, y: slotTop - 80), options: [])
    ctx.restoreGState()

    // Two hatch doors, hinged at the outer ends of the slot and swung open past vertical.
    func door(hingeX: CGFloat, angle: CGFloat, outward: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: hingeX, y: slotTop - 8)
        ctx.rotate(by: angle)
        let rect = CGRect(x: outward > 0 ? 0 : -260, y: -29, width: 260, height: 58)
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: color(0x0b0c24, 0.5))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 22, cornerHeight: 22, transform: nil)); ctx.clip()
        ctx.drawLinearGradient(gradient([(0, color(0xffffff)), (1, color(0xaebcf5))]),
                               start: CGPoint(x: 0, y: 29), end: CGPoint(x: 0, y: -29), options: [])
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
    door(hingeX: cx - 250, angle: 1.8, outward: 1)    // left door: starts pointing right, swings up and out
    door(hingeX: cx + 250, angle: -1.8, outward: -1)  // right door: the mirror image

    ctx.restoreGState()
    return ctx.makeImage()!
}

func resized(_ image: CGImage, to size: Int) -> CGImage {
    let ctx = newContext(size)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "assets", isDirectory: true)
let iconset = root.appendingPathComponent("Hatch.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let master = drawMaster()
writePNG(master, to: root.appendingPathComponent("icon-1024.png"))
for base in [16, 32, 128, 256, 512] {
    writePNG(resized(master, to: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(resized(master, to: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("wrote \(root.path)")
