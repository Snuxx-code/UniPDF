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
    public static func draw(_ annotations: [SlideAnnotation], in context: CGContext, slideSize: CGSize, target: CGRect) {
        guard slideSize.width > 0 else { return }
        context.saveGState()
        context.clip(to: target)
        context.translateBy(x: target.minX, y: target.maxY)
        context.scaleBy(x: target.width / slideSize.width, y: -target.height / slideSize.height)
        draw(annotations, in: context)
        context.restoreGState()
    }

    /// Draws annotations into a context whose coordinates already are slide points with a top-left origin.
    public static func draw(_ annotations: [SlideAnnotation], in context: CGContext) {
        for annotation in annotations {
            switch annotation.content {
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
