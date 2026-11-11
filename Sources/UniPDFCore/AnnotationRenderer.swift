import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers

extension AnnotationColor {
    public init(_ ink: InkColor) { self.init(InkRenderer.color(ink)) }

    public init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .black
        self.init(red: min(max(srgb.redComponent, 0), 1), green: min(max(srgb.greenComponent, 0), 1),
                  blue: min(max(srgb.blueComponent, 0), 1), alpha: min(max(srgb.alphaComponent, 0), 1))
    }

    public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

extension PDFPage {
    /// The page as it is displayed, after its rotation. Annotations are positioned in this size.
    public var displayedSlideSize: CGSize {
        let box = bounds(for: .cropBox)
        return abs(rotation) % 180 == 90 ? CGSize(width: box.height, height: box.width) : box.size
    }
}

public enum AnnotationRenderer {
    private nonisolated(unsafe) static let images = NSCache<NSUUID, CGImage>()

    /// Draws annotations onto a slide occupying `target` of a context with a bottom-left origin,
    /// such as a PDF page or a thumbnail.
    /// With `commentNumbers`, comments carry their number, as their footnotes in the study PDF do.
    public static func draw(_ annotations: [SlideAnnotation], in context: CGContext, slideSize: CGSize, target: CGRect,
                            commentNumbers: [UUID: Int] = [:]) {
        guard slideSize.width > 0 else { return }
        context.saveGState()
        context.clip(to: target)
        context.translateBy(x: target.minX, y: target.maxY)
        context.scaleBy(x: target.width / slideSize.width, y: -target.height / slideSize.height)
        draw(annotations, in: context)
        drawCommentNumbers(annotations, numbers: commentNumbers, in: context)
        context.restoreGState()
    }

    /// Rounded like the tags in the notes, but never rounder than half a line.
    static func commentPath(_ rects: [CGRect], isArea: Bool) -> CGPath {
        let path = CGMutablePath()
        for rect in rects {
            let padded = isArea ? rect : rect.insetBy(dx: -1.5, dy: -0.5)
            let radius = min(isArea ? 8 : 4, padded.height / 2, padded.width / 2)
            path.addRoundedRect(in: padded, cornerWidth: radius, cornerHeight: radius)
        }
        return path
    }

    private static func drawCommentNumbers(_ annotations: [SlideAnnotation], numbers: [UUID: Int], in context: CGContext) {
        guard !numbers.isEmpty else { return }
        for annotation in annotations {
            guard case .comment(let comment) = annotation.content, let number = numbers[annotation.id],
                  let first = comment.rects.first else { continue }
            let size = min(max(first.height * 0.55, 7), 12)
            let label = NSAttributedString(string: "\(number)", attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .bold), .foregroundColor: comment.color.strong.nsColor
            ])
            let line = CTLineCreateWithAttributedString(label)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            let tag = CGRect(x: first.minX - 2, y: first.minY - size * 1.15 - 1, width: width + size * 0.8, height: size * 1.25)
            context.saveGState()
            context.setFillColor(comment.color.pastel.nsColor.cgColor)
            context.addPath(CGPath(roundedRect: tag, cornerWidth: tag.height / 2, cornerHeight: tag.height / 2, transform: nil))
            context.fillPath()
            // The context is flipped; text is drawn upright.
            context.translateBy(x: tag.minX + size * 0.4, y: tag.maxY - size * 0.3)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    /// Draws annotations into a context whose coordinates already are slide points with a top-left origin.
    /// Which annotations to draw: the viewer draws highlights in a layer of their own,
    /// which it blends with the slide beneath, so that they stay behind the text.
    public enum Layer: Sendable { case all, highlights, marks }

    public static func draw(_ annotations: [SlideAnnotation], in context: CGContext, layer: Layer = .all) {
        // Highlights sit beneath handwritten strokes, text boxes and inserted images.
        // Comments lie beneath the text like highlights; their pastel multiplies with the slide.
        for annotation in annotations where layer != .marks {
            guard case .comment(let comment) = annotation.content else { continue }
            context.saveGState()
            context.setBlendMode(.multiply)
            context.setAlpha(comment.isArea ? 0.45 : 0.9)
            context.setFillColor(comment.color.pastel.nsColor.cgColor)
            context.addPath(commentPath(comment.rects, isArea: comment.isArea))
            context.fillPath()
            context.restoreGState()
        }
        for annotation in annotations where layer != .marks {
            guard case .highlight(let rects, let color) = annotation.content else { continue }
            context.saveGState()
            context.setBlendMode(.multiply)
            context.setAlpha(0.35)
            context.setFillColor(color.nsColor.cgColor)
            // Fill once, so overlapping rectangles in one selection do not darken each other.
            context.beginPath()
            for rect in rects { context.addRect(rect) }
            context.fillPath()
            context.restoreGState()
        }
        for annotation in annotations where layer != .highlights {
            switch annotation.content {
            case .highlight:
                continue
            case .comment(let comment):
                context.saveGState()
                context.setStrokeColor(comment.color.strong.nsColor.withAlphaComponent(0.8).cgColor)
                context.setLineWidth(comment.isArea ? 1.5 : 1)
                context.addPath(commentPath(comment.rects, isArea: comment.isArea))
                context.strokePath()
                context.restoreGState()
            case .ink(_, let color, let width), .shape(_, _, _, let color, let width):
                guard let outline = annotation.outline else { continue }
                context.saveGState()
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.setStrokeColor(color.nsColor.cgColor)
                context.setLineWidth(width)
                context.addPath(outline)
                context.strokePath()
                context.restoreGState()
            case .text(let string, let frame, let style, let color):
                let previous = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                // Real text, so that it stays selectable and searchable in the exported PDF.
                attributedText(string, style: style, color: color)
                    .draw(with: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading])
                NSGraphicsContext.current = previous
            case .image(let data, let frame):
                guard let image = image(for: annotation.id, data: data) else { continue }
                context.saveGState()
                // CGContext draws images bottom-up.
                context.translateBy(x: frame.minX, y: frame.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: CGRect(origin: .zero, size: frame.size))
                context.restoreGState()
            }
        }
    }

    public static func thumbnail(of page: PDFPage, annotations: [SlideAnnotation], size: CGSize) -> NSImage {
        let slide = page.thumbnail(of: size, for: .cropBox)
        guard !annotations.isEmpty else { return slide }
        let slideSize = page.displayedSlideSize
        return NSImage(size: slide.size, flipped: false) { rect in
            slide.draw(in: rect)
            if let context = NSGraphicsContext.current?.cgContext {
                draw(annotations, in: context, slideSize: slideSize, target: rect)
            }
            return true
        }
    }

    public static func font(for style: SlideTextStyle) -> NSFont {
        let size = CGFloat(style.size)
        var font = NSFont.systemFont(ofSize: size) as CTFont
        if let family = style.fontFamily {
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
            let named = CTFontCreateWithFontDescriptor(descriptor, size, nil)
            if CTFontCopyFamilyName(named) as String == family { font = named }
        }
        var traits: CTFontSymbolicTraits = []
        if style.bold { traits.insert(.traitBold) }
        if style.italic { traits.insert(.traitItalic) }
        // A family without this style stays as it is, rather than turning into another font.
        if !traits.isEmpty, let styled = CTFontCreateCopyWithSymbolicTraits(font, size, nil, traits, traits) { font = styled }
        return font as NSFont
    }

    public static func attributedText(_ string: String, style: SlideTextStyle, color: AnnotationColor) -> NSAttributedString {
        NSAttributedString(string: string, attributes: textAttributes(style: style, color: color))
    }

    public static func textAttributes(style: SlideTextStyle, color: AnnotationColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: style), .foregroundColor: color.nsColor, .paragraphStyle: paragraph
        ]
        if style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return attributes
    }

    /// The height a text box needs at `width`; at least one line.
    public static func textHeight(_ string: String, style: SlideTextStyle, width: CGFloat) -> CGFloat {
        let text = attributedText(string.isEmpty ? " " : string + (string.hasSuffix("\n") ? " " : ""), style: style, color: AnnotationColor(red: 0, green: 0, blue: 0))
        return ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
    }

    private static func image(for id: UUID, data: Data) -> CGImage? {
        if let cached = images.object(forKey: id as NSUUID) { return cached }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images.setObject(image, forKey: id as NSUUID)
        return image
    }
}

public enum SlideImageImport {
    /// Upright and at most this long on its longest side, because the image gets embedded in the PDF twice over.
    static let maximumPixels = 2400

    /// Prepares any image the system can read for embedding. Throws `ProjectError.invalidImage` otherwise.
    public static func prepare(_ data: Data) throws -> (data: Data, pixelSize: CGSize) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixels
              ] as CFDictionary) else { throw ProjectError.invalidImage }
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        var encoded = try encode(image, as: .png, quality: 1)
        // Lossless keeps screenshots sharp. A large photo would make the PDF needlessly heavy.
        if opaque, encoded.count > 2_000_000 { encoded = try encode(image, as: .jpeg, quality: 0.85) }
        return (encoded, CGSize(width: image.width, height: image.height))
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw ProjectError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ProjectError.invalidImage }
        return output as Data
    }
}
