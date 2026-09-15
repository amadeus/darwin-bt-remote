// Run from the repository root: swift scripts/artwork/GenerateAppIcon.swift
// Original vector artwork, inspired by the app's keyboard status symbol.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("DeusKVM/Assets.xcassets/AppIcon.appiconset")

func rounded(_ rect: NSRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func render(_ size: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)

    let tile = rounded(NSRect(x: 64, y: 64, width: 896, height: 896), 204)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(calibratedRed: 0.23, green: 0.24, blue: 0.73, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.30, green: 0.22, blue: 0.78, alpha: 1),
        NSColor(calibratedRed: 0.19, green: 0.46, blue: 0.96, alpha: 1)
    ])!.draw(in: tile, angle: 90)
    NSColor.white.withAlphaComponent(0.22).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    // A broad, centered keyboard with a clear space bar and two rows of keys.
    let keyboard = rounded(NSRect(x: 198, y: 318, width: 628, height: 388), 62)
    NSGraphicsContext.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.40, alpha: 0.28)
    glyphShadow.shadowBlurRadius = 14
    glyphShadow.shadowOffset = NSSize(width: 0, height: -10)
    glyphShadow.set()
    NSColor.white.setStroke()
    keyboard.lineWidth = 30
    keyboard.stroke()
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.setFill()
    for y in [CGFloat(574), 486] {
        for column in 0 ..< 6 {
            rounded(NSRect(x: 262 + CGFloat(column) * 86, y: y, width: 70, height: 54), 12).fill()
        }
    }
    rounded(NSRect(x: 262, y: 398, width: 70, height: 54), 12).fill()
    rounded(NSRect(x: 348, y: 398, width: 328, height: 54), 12).fill()
    rounded(NSRect(x: 692, y: 398, width: 70, height: 54), 12).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let sizes = [16, 32, 48, 64, 128, 256, 512, 1024]
let images = Dictionary(uniqueKeysWithValues: sizes.map { ($0, render($0)) })
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: assets.appendingPathComponent("Contents.json")))
    as! [String: Any]
for image in manifest["images"] as! [[String: String]] {
    let size = Int(image["size"]!.components(separatedBy: "x")[0])!
    let scale = image["scale"] == "2x" ? 2 : 1
    try images[size * scale]!.write(to: assets.appendingPathComponent(image["filename"]!))
}

// ICO supports PNG frames; package native resolutions for Windows DPI scaling.
var ico = Data()
func appendWord(_ value: some FixedWidthInteger) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { ico.append(contentsOf: $0) }
}

let windowsSizes = sizes.filter { $0 <= 256 }
appendWord(UInt16(0)); appendWord(UInt16(1)); appendWord(UInt16(windowsSizes.count))
var offset = 6 + 16 * windowsSizes.count
for size in windowsSizes {
    let data = images[size]!
    ico.append(contentsOf: [UInt8(size == 256 ? 0 : size), UInt8(size == 256 ? 0 : size), 0, 0])
    appendWord(UInt16(1)); appendWord(UInt16(32))
    appendWord(UInt32(data.count)); appendWord(UInt32(offset))
    offset += data.count
}

for size in windowsSizes {
    ico.append(images[size]!)
}

try ico.write(to: root.appendingPathComponent("windows/DeusKVM.Companion/AppIcon.ico"))
print("Generated Mac app icons and Windows AppIcon.ico")
