import CoreGraphics
import Foundation

public struct AnnotationColor: Codable, Sendable, Equatable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    var isValid: Bool { [red, green, blue, alpha].allSatisfy { (0...1).contains($0) } }
}

public enum SlideShape: String, Codable, CaseIterable, Sendable {
    case rectangle, square, circle, ellipse, line
    public var label: String {
        switch self {
        case .rectangle: "Rechteck"
        case .square: "Quadrat"
        case .circle: "Kreis"
        case .ellipse: "Oval"
        case .line: "Linie"
        }
    }
    public var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .square: "square"
        case .circle: "circle"
        case .ellipse: "oval"
        case .line: "line.diagonal"
        }
    }
    /// A square and a circle stay one, whichever way they are dragged.
    public var keepsAspect: Bool { self == .square || self == .circle }
}

public struct SlideTextStyle: Codable, Sendable, Equatable {
    /// A font family name. Nil is the system font; a family missing on this Mac falls back to it.
    public var fontFamily: String?
    public var size: Double
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public init(fontFamily: String? = nil, size: Double = 24, bold: Bool = false, italic: Bool = false, underline: Bool = false) {
        self.fontFamily = fontFamily; self.size = size; self.bold = bold; self.italic = italic; self.underline = underline
    }
}

/// Something placed on the slide itself. Coordinates are points of the slide as it is displayed:
/// the origin is its top-left corner, after the page's rotation and without its crop offset.
/// That keeps annotations independent of zoom, and upright on rotated pages.
public struct SlideAnnotation: Codable, Sendable, Equatable, Identifiable {
    public enum Content: Codable, Sendable, Equatable {
        case ink(points: [CGPoint], color: AnnotationColor, width: Double)
        case shape(SlideShape, start: CGPoint, end: CGPoint, color: AnnotationColor, width: Double)
        case text(String, frame: CGRect, style: SlideTextStyle, color: AnnotationColor)
        case image(Data, frame: CGRect)
    }

    public var id: UUID
    public var content: Content

    public init(id: UUID = UUID(), content: Content) {
        self.id = id
        self.content = content
    }

    /// The geometry itself, without the stroke.
    public var bounds: CGRect {
        switch content {
        case .ink(let points, _, _):
            let xs = points.map(\.x), ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        case .shape(_, let start, let end, _, _):
            return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        case .text(_, let frame, _, _), .image(_, let frame):
            return frame
        }
    }

    /// Everything that gets painted.
    public var visualBounds: CGRect {
        switch content {
        case .ink(_, _, let width), .shape(_, _, _, _, let width): bounds.insetBy(dx: -width / 2, dy: -width / 2)
        default: bounds
        }
    }

    public var isValid: Bool {
        func valid(_ value: CGFloat) -> Bool { value.isFinite && abs(value) <= 100_000 }
        func valid(_ point: CGPoint) -> Bool { valid(point.x) && valid(point.y) }
        func valid(_ frame: CGRect) -> Bool { valid(frame.origin) && valid(frame.width) && valid(frame.height) && frame.width > 0 && frame.height > 0 }
        func valid(width: Double) -> Bool { width.isFinite && width > 0 && width <= 1000 }
        switch content {
        case .ink(let points, let color, let width):
            return !points.isEmpty && points.allSatisfy(valid) && color.isValid && valid(width: width)
        case .shape(_, let start, let end, let color, let width):
            return valid(start) && valid(end) && color.isValid && valid(width: width)
        case .text(_, let frame, let style, let color):
            return valid(frame) && color.isValid && style.size.isFinite && (1...1000).contains(style.size)
        case .image(let data, let frame):
            return !data.isEmpty && valid(frame)
        }
    }

    public func moved(by delta: CGVector) -> SlideAnnotation {
        func shift(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + delta.dx, y: point.y + delta.dy) }
        var result = self
        switch content {
        case .ink(let points, let color, let width):
            result.content = .ink(points: points.map(shift), color: color, width: width)
        case .shape(let shape, let start, let end, let color, let width):
            result.content = .shape(shape, start: shift(start), end: shift(end), color: color, width: width)
        case .text(let string, let frame, let style, let color):
            result.content = .text(string, frame: frame.offsetBy(dx: delta.dx, dy: delta.dy), style: style, color: color)
        case .image(let data, let frame):
            result.content = .image(data, frame: frame.offsetBy(dx: delta.dx, dy: delta.dy))
        }
        return result
    }

    /// Maps the geometry from its current bounds onto `rect`. Stroke widths and font sizes stay as they are.
    public func resized(to rect: CGRect) -> SlideAnnotation {
        let old = bounds
        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(x: old.width > 0 ? rect.minX + (point.x - old.minX) / old.width * rect.width : rect.minX,
                    y: old.height > 0 ? rect.minY + (point.y - old.minY) / old.height * rect.height : rect.minY)
        }
        var result = self
        switch content {
        case .ink(let points, let color, let width):
            result.content = .ink(points: points.map(map), color: color, width: width)
        case .shape(let shape, let start, let end, let color, let width):
            result.content = .shape(shape, start: map(start), end: map(end), color: color, width: width)
        case .text(let string, _, let style, let color):
            result.content = .text(string, frame: rect, style: style, color: color)
        case .image(let data, _):
            result.content = .image(data, frame: rect)
        }
        return result
    }

    /// The stroked line of ink and shapes; text and images have none.
    public var outline: CGPath? {
        let path = CGMutablePath()
        switch content {
        case .ink(let points, _, _):
            guard let first = points.first else { return nil }
            path.move(to: first)
            if points.count == 1 {
                path.addLine(to: first)
            } else {
                // Through the midpoints, so that a quick stroke does not look faceted.
                for index in 1..<points.count - 1 {
                    let (control, next) = (points[index], points[index + 1])
                    path.addQuadCurve(to: CGPoint(x: (control.x + next.x) / 2, y: (control.y + next.y) / 2), control: control)
                }
                path.addLine(to: points[points.count - 1])
            }
        case .shape(let shape, let start, let end, _, _):
            switch shape {
            case .rectangle, .square: path.addRect(bounds)
            case .circle, .ellipse: path.addEllipse(in: bounds)
            case .line:
                path.move(to: start)
                path.addLine(to: end)
            }
        case .text, .image:
            return nil
        }
        return path
    }

    /// Outlined shapes count only at their line, so that something inside them stays reachable.
    public func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch content {
        case .text, .image:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .ink(_, _, let width), .shape(_, _, _, _, let width):
            let reach = width + 2 * tolerance
            guard visualBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point), let outline else { return false }
            if bounds.width == 0 && bounds.height == 0 { return hypot(point.x - bounds.midX, point.y - bounds.midY) <= reach / 2 }
            return outline.copy(strokingWithWidth: reach, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
        }
    }
}
