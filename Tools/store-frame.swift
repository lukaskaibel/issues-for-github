// Frames a window snapshot for the Mac App Store: the window with rounded corners, a shadow and the coloured
// traffic lights of an active window, on the violet backdrop of the README pictures, 2880 x 1800 without alpha.
//   swift Tools/store-frame.swift <window.png> <out.png> light|dark
// The snapshot comes from the debug remote's `snapshot` command at 2x; see Tools/mac-app-store-screenshots.sh.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let dark = ["light": false, "dark": true][arguments[3]],
      let window = NSImage(contentsOfFile: arguments[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("usage: swift Tools/store-frame.swift <window.png> <out.png> light|dark")
    exit(1)
}

let width = 2880, height = 1800
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r) / 255, CGFloat(g) / 255, CGFloat(b) / 255, a])!
}

let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin, like the snapshot.
context.translateBy(x: 0, y: CGFloat(height))
context.scaleBy(x: 1, y: -1)

// The backdrop: a base colour with soft glows in the app's violet, pink and blue.
struct Glow { let color: (Int, Int, Int); let strength: CGFloat; let center: CGPoint; let radius: CGFloat }
let base = dark ? (11, 12, 16) : (244, 244, 250)
let glows: [Glow] = dark
    ? [Glow(color: (101, 108, 230), strength: 0.80, center: CGPoint(x: 0.50, y: -0.05), radius: 0.95),
       Glow(color: (196, 95, 166), strength: 0.34, center: CGPoint(x: 1.00, y: 1.05), radius: 0.60),
       Glow(color: (90, 176, 216), strength: 0.22, center: CGPoint(x: 0.00, y: 1.05), radius: 0.55)]
    : [Glow(color: (143, 150, 242), strength: 0.42, center: CGPoint(x: 0.50, y: 0.00), radius: 0.75),
       Glow(color: (217, 139, 196), strength: 0.20, center: CGPoint(x: 0.95, y: 1.05), radius: 0.55),
       Glow(color: (90, 176, 216), strength: 0.14, center: CGPoint(x: 0.02, y: 1.00), radius: 0.50)]
context.setFillColor(rgb(base.0, base.1, base.2))
context.fill(CGRect(x: 0, y: 0, width: width, height: height))
for glow in glows {
    // Fades with the square of the distance, in steps fine enough to look continuous.
    let steps = 24
    let locations = (0...steps).map { CGFloat($0) / CGFloat(steps) }
    let colors = locations.map { rgb(glow.color.0, glow.color.1, glow.color.2, glow.strength * (1 - $0) * (1 - $0)) }
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
    let center = CGPoint(x: glow.center.x * CGFloat(width), y: glow.center.y * CGFloat(height))
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                               endRadius: glow.radius * CGFloat(width), options: [])
}

// A little noise keeps the gradient from banding.
let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
var seed: UInt32 = 0x9E37_79B9
for index in 0..<(width * height) {
    seed = seed &* 1_664_525 &+ 1_013_904_223
    let noise = Int((seed >> 30) & 1) - Int((seed >> 29) & 1)
    for channel in 0..<3 {
        pixels[index * 4 + channel] = UInt8(clamping: Int(pixels[index * 4 + channel]) + noise)
    }
}

// The window, centred, with the two shadows of a macOS window.
let frame = CGRect(x: (width - window.width) / 2, y: (height - window.height) / 2, width: window.width, height: window.height)
let shape = CGPath(roundedRect: frame, cornerWidth: 36, cornerHeight: 36, transform: nil)
let shadowStrength: CGFloat = dark ? 0.70 : 0.24
for (blur, opacity, drop) in [(CGFloat(120), 0.9, CGFloat(40)), (28, 0.6, 8)] {
    // The shape itself is drawn far off the canvas, so only its shadow lands on it.
    let away = CGFloat(width * 2)
    context.saveGState()
    context.setShadow(offset: CGSize(width: -away, height: -drop), blur: blur, color: rgb(0, 0, 0, shadowStrength * opacity))
    context.translateBy(x: away, y: 0)
    context.addPath(shape)
    context.setFillColor(rgb(0, 0, 0))
    context.fillPath()
    context.restoreGState()
}
context.saveGState()
context.addPath(shape)
context.clip()
// The snapshot is top-down; flip it back for drawing into the flipped context.
context.translateBy(x: frame.minX, y: frame.maxY)
context.scaleBy(x: 1, y: -1)
context.draw(window, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
context.restoreGState()

// The snapshot shows the grey traffic lights of a window in the background; paint the active ones over them.
let lights: [(fill: (Int, Int, Int), ring: (Int, Int, Int))] = dark
    ? [((243, 90, 80), (247, 123, 114)), ((252, 190, 7), (249, 207, 35)), ((33, 191, 12), (79, 211, 53))]
    : [((248, 122, 114), (232, 93, 86)), ((253, 199, 51), (223, 158, 36)), ((126, 213, 85), (94, 178, 59))]
let behind = NSBitmapImageRep(cgImage: window).colorAt(x: 165, y: 40)?.usingColorSpace(.sRGB)?.cgColor ?? rgb(128, 128, 128)
for (index, light) in lights.enumerated() {
    let center = CGPoint(x: frame.minX + 31.5 + CGFloat(index) * 46, y: frame.minY + 31.5)
    context.setFillColor(behind)
    context.fillEllipse(in: CGRect(x: center.x - 15.5, y: center.y - 15.5, width: 31, height: 31))
    context.setFillColor(rgb(light.fill.0, light.fill.1, light.fill.2))
    context.fillEllipse(in: CGRect(x: center.x - 14, y: center.y - 14, width: 28, height: 28))
    context.setStrokeColor(rgb(light.ring.0, light.ring.1, light.ring.2))
    context.setLineWidth(1.2)
    context.strokeEllipse(in: CGRect(x: center.x - 13.4, y: center.y - 13.4, width: 26.8, height: 26.8))
}

// The hairline macOS draws around windows, so the window stands off the backdrop.
context.addPath(CGPath(roundedRect: frame.insetBy(dx: -0.5, dy: -0.5), cornerWidth: 36.5, cornerHeight: 36.5, transform: nil))
context.setStrokeColor(dark ? rgb(255, 255, 255, 34.0 / 255) : rgb(0, 0, 0, 30.0 / 255))
context.setLineWidth(1)
context.strokePath()

// The App Store wants no alpha channel.
let opaque = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
opaque.draw(context.makeImage()!, in: CGRect(x: 0, y: 0, width: width, height: height))
let output = NSBitmapImageRep(cgImage: opaque.makeImage()!)
try output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
