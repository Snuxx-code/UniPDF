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
        case highlight(rects: [CGRect], color: AnnotationColor)
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
        case .highlight(let rects, _):
            return rects.reduce(CGRect.null) { $0.union($1) }
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
        case .highlight(let rects, let color):
            return !rects.isEmpty && rects.allSatisfy(valid) && color.isValid
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
        case .highlight(let rects, let color):
            result.content = .highlight(rects: rects.map { $0.offsetBy(dx: delta.dx, dy: delta.dy) }, color: color)
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
        case .highlight(let rects, let color):
            result.content = .highlight(rects: rects.map { CGRect(origin: map($0.origin), size: CGSize(
                width: old.width > 0 ? $0.width / old.width * rect.width : $0.width,
                height: old.height > 0 ? $0.height / old.height * rect.height : $0.height)) }, color: color)
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
        case .text, .image, .highlight:
            return nil
        }
        return path
    }

    /// Outlined shapes count only at their line, so that something inside them stays reachable.
    public func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch content {
        case .text, .image:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .highlight(let rects, _):
            return rects.contains { $0.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        case .ink(_, _, let width), .shape(_, _, _, _, let width):
            let reach = width + 2 * tolerance
            guard visualBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point), let outline else { return false }
            if bounds.width == 0 && bounds.height == 0 { return hypot(point.x - bounds.midX, point.y - bounds.midY) <= reach / 2 }
            return outline.copy(strokingWithWidth: reach, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
        }
    }
}

extension SlideAnnotation {
    /// Whether the eraser works on this kind: pen strokes and text highlights. Shapes, text and images are deleted instead.
    public var isErasable: Bool {
        switch content {
        case .ink, .highlight: true
        default: false
        }
    }

    /// What is left after erasing a disc, like a real eraser: a stroke breaks into the pieces outside it,
    /// a highlight keeps the parts of each line beside it. Returns `[self]` when the disc misses.
    /// The first piece keeps the identity, so the eraser does not tear apart what it does not touch.
    /// With `characters`, the slide's text in slide points, a highlight loses whole characters only.
    public func erasing(around center: CGPoint, radius: CGFloat, characters: [CGRect]? = nil) -> [SlideAnnotation] {
        switch content {
        case .ink(let points, let color, let width):
            // The eraser removes everything it touches, including the edge of a wide stroke.
            let reach = radius + width / 2
            func inside(_ point: CGPoint) -> Bool { hypot(point.x - center.x, point.y - center.y) <= reach }
            if points.count == 1 { return inside(points[0]) ? [] : [self] }
            var pieces: [[CGPoint]] = []
            var current: [CGPoint] = []
            var touched = false
            for (start, end) in zip(points, points.dropFirst()) {
                guard let (entry, exit) = Self.discInterval(from: start, to: end, center: center, radius: reach) else {
                    if current.isEmpty { current = [start] }
                    current.append(end)
                    continue
                }
                touched = true
                func point(_ t: CGFloat) -> CGPoint { CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t) }
                if entry > 0 {
                    if current.isEmpty { current = [start] }
                    current.append(point(entry))
                }
                if !current.isEmpty { pieces.append(current) }
                current = exit < 1 ? [point(exit), end] : []
            }
            guard touched else { return [self] }
            if !current.isEmpty { pieces.append(current) }
            // A sliver shorter than the stroke is wide would only show up as a dot.
            let kept = pieces.filter { piece in
                zip(piece, piece.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) } >= max(width / 2, 0.5)
            }
            return kept.enumerated().map { index, piece in
                SlideAnnotation(id: index == 0 ? id : UUID(), content: .ink(points: piece, color: color, width: width))
            }
        case .highlight(let rects, let color):
            var touched = false
            let remaining = rects.flatMap { rect -> [CGRect] in
                guard Self.disc(center, radius, touches: rect) else { return [rect] }
                // Text runs along the longer side, also on turned slides.
                let horizontal = rect.width >= rect.height
                let (low, high) = horizontal ? (rect.minX, rect.maxX) : (rect.minY, rect.maxY)
                let middle = horizontal ? center.x : center.y
                var cut = (middle - radius, middle + radius)
                // A page without a text layer has no characters to keep whole.
                if let characters, !characters.isEmpty {
                    // The characters of this line that the eraser touches, removed whole.
                    let hit = characters.filter { rect.contains(CGPoint(x: $0.midX, y: $0.midY)) && Self.disc(center, radius, touches: $0) }
                    guard let first = hit.map({ horizontal ? $0.minX : $0.minY }).min(),
                          let last = hit.map({ horizontal ? $0.maxX : $0.maxY }).max() else { return [rect] }
                    cut = (first, last)
                }
                touched = true
                // Lengths are checked before they become rectangles, because CGRect reports a negative width as positive.
                let spans = [(low, cut.0 - low), (cut.1, high - cut.1)].filter { $0.1 >= 1 }
                return spans.map { start, length in
                    horizontal ? CGRect(x: start, y: rect.minY, width: length, height: rect.height)
                               : CGRect(x: rect.minX, y: start, width: rect.width, height: length)
                }
            }
            guard touched else { return [self] }
            return remaining.isEmpty ? [] : [SlideAnnotation(id: id, content: .highlight(rects: remaining, color: color))]
        default:
            return [self]
        }
    }

    private static func disc(_ center: CGPoint, _ radius: CGFloat, touches rect: CGRect) -> Bool {
        let nearest = CGPoint(x: min(max(center.x, rect.minX), rect.maxX), y: min(max(center.y, rect.minY), rect.maxY))
        return hypot(nearest.x - center.x, nearest.y - center.y) <= radius
    }

    /// The part of a segment inside a disc, as fractions of the segment from 0 to 1.
    private static func discInterval(from start: CGPoint, to end: CGPoint, center: CGPoint, radius: CGFloat) -> (CGFloat, CGFloat)? {
        let direction = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let offset = CGVector(dx: start.x - center.x, dy: start.y - center.y)
        let a = direction.dx * direction.dx + direction.dy * direction.dy
        let c = offset.dx * offset.dx + offset.dy * offset.dy - radius * radius
        guard a > 0 else { return c <= 0 ? (0, 1) : nil }
        let b = 2 * (offset.dx * direction.dx + offset.dy * direction.dy)
        let discriminant = b * b - 4 * a * c
        guard discriminant >= 0 else { return nil }
        let root = discriminant.squareRoot()
        let entry = max((-b - root) / (2 * a), 0), exit = min((-b + root) / (2 * a), 1)
        return entry < exit ? (entry, exit) : nil
    }
}
