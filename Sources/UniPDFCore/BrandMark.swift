import CoreGraphics

/// The UniPDF symbol as a path, shared by the app's interface and the study PDF's footer.
/// A page whose frame opens on the right where the text marker passes through; drawn from the web app's
/// brand kit (public/brand/unipdf-symbol.svg, and the bolder -small cut for sizes below about 32 points).
/// The path lies in a 256 square with its y pointing down, as in the SVG.
public enum BrandMark {
    /// The brand gradient from green to blue, as sRGB components, with its stops.
    public static let gradient: [(red: CGFloat, green: CGFloat, blue: CGFloat, location: CGFloat)] = [
        (0x1E / 255, 0x6B / 255, 0x52 / 255, 0),
        (0x22 / 255, 0xA3 / 255, 0x8A / 255, 0.52),
        (0x3D / 255, 0x86 / 255, 0xF0 / 255, 1),
    ]

    /// Where the symbol's ink lies within its 256 square.
    public static let inkBounds = CGRect(x: 19, y: 40, width: 218, height: 176)

    public static func path(small: Bool = false) -> CGPath {
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
        let markerTop: CGFloat = small ? 104 : 108, height: CGFloat = small ? 40 : 32, slant: CGFloat = small ? 10.72 : 8.57
        path.move(to: CGPoint(x: 67, y: markerTop))
        path.addLine(to: CGPoint(x: 237, y: markerTop))
        path.addLine(to: CGPoint(x: 237 - slant, y: markerTop + height))
        path.addLine(to: CGPoint(x: 67, y: markerTop + height))
        path.addArc(center: CGPoint(x: 67, y: markerTop + height / 2), radius: height / 2,
                    startAngle: .pi / 2, endAngle: .pi * 3 / 2, clockwise: false)
        path.closeSubpath()
        return path
    }

    /// Fills the symbol with the brand gradient, its ink `height` tall, its foot on `baseline` and its left edge at `x`,
    /// in a context whose y points up, such as a PDF page.
    public static func draw(in context: CGContext, x: CGFloat, baseline: CGFloat, height: CGFloat) {
        let scale = height / inkBounds.height
        let colors = gradient.map { CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) } as CFArray
        guard let shading = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors,
                                       locations: gradient.map(\.location)) else { return }
        context.saveGState()
        // Into the symbol's square: its ink's bottom-left on the point given, y turned to point down.
        context.translateBy(x: x - inkBounds.minX * scale, y: baseline + inkBounds.maxY * scale)
        context.scaleBy(x: scale, y: -scale)
        context.addPath(path(small: true))
        context.clip()
        context.drawLinearGradient(shading, start: CGPoint(x: 20, y: 40), end: CGPoint(x: 236, y: 216), options: [])
        context.restoreGState()
    }
}
