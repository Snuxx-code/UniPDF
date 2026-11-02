import AppKit

public enum InkRenderer {
    public static func color(_ color: InkColor) -> NSColor {
        switch color {
        case .graphite: NSColor(srgbRed: 0.16, green: 0.19, blue: 0.21, alpha: 1)
        case .blue: NSColor(srgbRed: 0.16, green: 0.35, blue: 0.74, alpha: 1)
        case .red: NSColor(srgbRed: 0.75, green: 0.20, blue: 0.23, alpha: 1)
        case .green: NSColor(srgbRed: 0.12, green: 0.45, blue: 0.34, alpha: 1)
        }
    }

    // Coordinates use an 800 × 500 canvas with a top-left origin in UI and PDF alike.
    public static func draw(_ elements: [InkElement], in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.clip(to: rect)
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 800, y: rect.height / 500)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for element in elements {
            guard let first = element.points.first, let last = element.points.last else { continue }
            let start = CGPoint(x: first.x, y: first.y)
            let end = CGPoint(x: last.x, y: last.y)
            context.setStrokeColor(color(element.color).cgColor)
            context.setFillColor(color(element.color).cgColor)
            context.setLineWidth(element.width)
            let path = CGMutablePath()
            let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                             width: abs(end.x - start.x), height: abs(end.y - start.y))
            switch element.tool {
            case .pen:
                if element.points.count == 1 {
                    context.fillEllipse(in: CGRect(x: start.x - element.width / 2, y: start.y - element.width / 2,
                                                 width: element.width, height: element.width))
                    continue
                }
                path.move(to: start)
                for point in element.points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
            case .line, .arrow:
                path.move(to: start); path.addLine(to: end)
                if element.tool == .arrow {
                    let angle = atan2(end.y - start.y, end.x - start.x)
                    let length = max(14, element.width * 5)
                    for offset in [-Double.pi / 6, Double.pi / 6] {
                        path.move(to: end)
                        path.addLine(to: CGPoint(x: end.x - length * cos(angle + offset), y: end.y - length * sin(angle + offset)))
                    }
                }
            case .rectangle: path.addRect(box)
            case .ellipse: path.addEllipse(in: box)
            }
            context.addPath(path)
            context.strokePath()
        }
        context.restoreGState()
    }
}
