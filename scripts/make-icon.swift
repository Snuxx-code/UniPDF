import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

// The UniPDF symbol from the brand kit of the web app (public/brand/unipdf-symbol.svg and its bolder
// -small cut for 16 and 32 pixels), in the SVG's 256-point space with y pointing down: a page whose
// frame opens on the right, where the text marker passes through.
func symbol(small: Bool) -> CGPath {
    let path = CGMutablePath()
    let radius: CGFloat = small ? 16 : 22, right: CGFloat = small ? 179 : 185, opening: CGFloat = small ? 100 : 102
    let top: CGFloat = small ? 64 : 58, bottom: CGFloat = small ? 192 : 198, left: CGFloat = small ? 43 : 37
    let k: CGFloat = 0.5523 // Control points of a quarter circle.
    path.move(to: CGPoint(x: right, y: 148))
    path.addLine(to: CGPoint(x: right, y: bottom - radius))
    path.addCurve(to: CGPoint(x: right - radius, y: bottom), control1: CGPoint(x: right, y: bottom - radius + radius * k),
                  control2: CGPoint(x: right - radius + radius * k, y: bottom))
    path.addLine(to: CGPoint(x: 59, y: bottom))
    path.addCurve(to: CGPoint(x: left, y: bottom - radius), control1: CGPoint(x: 59 - radius * k, y: bottom),
                  control2: CGPoint(x: left, y: bottom - radius * k))
    path.addLine(to: CGPoint(x: left, y: 80))
    path.addCurve(to: CGPoint(x: 59, y: top), control1: CGPoint(x: left, y: 80 - radius * k), control2: CGPoint(x: 59 - radius * k, y: top))
    path.addLine(to: CGPoint(x: 163, y: top))
    path.addCurve(to: CGPoint(x: right, y: 80), control1: CGPoint(x: 163 + radius * k, y: top), control2: CGPoint(x: right, y: 80 - radius * k))
    path.addLine(to: CGPoint(x: right, y: opening))
    path.addLine(to: CGPoint(x: 203, y: opening))
    path.addLine(to: CGPoint(x: 203, y: 80))
    path.addCurve(to: CGPoint(x: 163, y: 40), control1: CGPoint(x: 203, y: 57.9), control2: CGPoint(x: 185.1, y: 40))
    path.addLine(to: CGPoint(x: 59, y: 40))
    path.addCurve(to: CGPoint(x: 19, y: 80), control1: CGPoint(x: 36.9, y: 40), control2: CGPoint(x: 19, y: 57.9))
    path.addLine(to: CGPoint(x: 19, y: 176))
    path.addCurve(to: CGPoint(x: 59, y: 216), control1: CGPoint(x: 19, y: 198.1), control2: CGPoint(x: 36.9, y: 216))
    path.addLine(to: CGPoint(x: 163, y: 216))
    path.addCurve(to: CGPoint(x: 203, y: 176), control1: CGPoint(x: 185.1, y: 216), control2: CGPoint(x: 203, y: 198.1))
    path.addLine(to: CGPoint(x: 203, y: 148))
    path.closeSubpath()
    let lines = small ? [CGRect(x: 59, y: 80, width: 68, height: 16), CGRect(x: 59, y: 160, width: 84, height: 16)]
        : [CGRect(x: 59, y: 80, width: 48, height: 12), CGRect(x: 115, y: 80, width: 40, height: 12), CGRect(x: 59, y: 158, width: 76, height: 12)]
    for line in lines { path.addRoundedRect(in: line, cornerWidth: line.height / 2, cornerHeight: line.height / 2) }
    // The marker, round on the left and cut at a slant on the right.
    let markerTop: CGFloat = small ? 104 : 108, height: CGFloat = small ? 40 : 32, slant: CGFloat = small ? 10.72 : 8.57
    path.move(to: CGPoint(x: 67, y: markerTop))
    path.addLine(to: CGPoint(x: 237, y: markerTop))
    path.addLine(to: CGPoint(x: 237 - slant, y: markerTop + height))
    path.addLine(to: CGPoint(x: 67, y: markerTop + height))
    path.addArc(center: CGPoint(x: 67, y: markerTop + height / 2), radius: height / 2, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: false)
    path.closeSubpath()
    return path
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let brand = CGGradient(colorsSpace: space, colors: [
    CGColor(srgbRed: 0x1E / 255, green: 0x6B / 255, blue: 0x52 / 255, alpha: 1),
    CGColor(srgbRed: 0x22 / 255, green: 0xA3 / 255, blue: 0x8A / 255, alpha: 1),
    CGColor(srgbRed: 0x3D / 255, green: 0x86 / 255, blue: 0xF0 / 255, alpha: 1)
] as CFArray, locations: [0, 0.5, 1])!

// Apple's icon grid: an 824-point plate on a 1024 canvas, leaving room for its shadow.
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Icon context") }
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let plate = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.3))
        context.addPath(plate); context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(plate); context.clip()
        context.drawLinearGradient(brand, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
        context.restoreGState()
        // The symbol fills most of the plate, in white; small icons use the bolder cut.
        context.translateBy(x: 212, y: 812)
        context.scaleBy(x: 600 / 256, y: -600 / 256)
        context.addPath(symbol(small: pixels <= 64))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fillPath()
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("Icon image") }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
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
