import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Icon context") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(srgbRed: 0.16, green: 0.40, blue: 0.34, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 200, yRadius: 200).fill()
        NSColor(srgbRed: 0.86, green: 0.92, blue: 0.87, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 223, y: 238, width: 285, height: 547), xRadius: 30, yRadius: 30).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 530, y: 238, width: 285, height: 547), xRadius: 30, yRadius: 30).fill()
        NSColor(srgbRed: 0.16, green: 0.40, blue: 0.34, alpha: 0.55).setStroke()
        for y in [640.0, 554.0, 468.0] {
            let line = NSBezierPath()
            line.lineWidth = 18
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: 590, y: y)); line.line(to: NSPoint(x: y == 468 ? 700 : 751, y: y)); line.stroke()
        }
        let fold = NSBezierPath()
        NSColor(srgbRed: 0.16, green: 0.40, blue: 0.34, alpha: 0.45).setStroke()
        fold.lineWidth = 12; fold.lineCapStyle = .round
        fold.move(to: NSPoint(x: 280, y: 700)); fold.line(to: NSPoint(x: 440, y: 700)); fold.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
}

// ICNS accepts PNG representations in these size-specific chunks.
var chunks = Data()
for (tag, name) in [("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
                    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
                    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
                    ("ic10", "icon_512x512@2x.png")] {
    let png = try Data(contentsOf: directory.appendingPathComponent(name))
    chunks.append(Data(tag.utf8))
    var length = UInt32(png.count + 8).bigEndian
    withUnsafeBytes(of: &length) { chunks.append(contentsOf: $0) }
    chunks.append(png)
}
var icon = Data("icns".utf8)
var length = UInt32(chunks.count + 8).bigEndian
withUnsafeBytes(of: &length) { icon.append(contentsOf: $0) }
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
