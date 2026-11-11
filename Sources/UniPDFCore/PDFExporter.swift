import AppKit
import CoreText
import PDFKit

public enum PDFExporter {
    public static func validatedDocument(data: Data) throws -> PDFDocument {
        guard let document = PDFDocument(data: data) else { throw ProjectError.invalidPDF }
        guard !document.isLocked, document.allowsCopying, document.allowsPrinting else { throw ProjectError.lockedPDF }
        guard document.pageCount > 0 else { throw ProjectError.invalidPDF }
        return document
    }

    /// Landscape A4. Slides remain vector-based; overflow notes get continuation pages.
    public static func export(_ project: StudyProject, includingProject: Bool = true) throws -> Data {
        guard let data = project.pdfData else { throw ProjectError.invalidPDF }
        let source = try validatedDocument(data: data)
        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 841.89, height: 595.28)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, [
                kCGPDFContextTitle: project.title, kCGPDFContextCreator: "UniPDF"
              ] as CFDictionary) else { throw ProjectError.exportFailed }
        if includingProject { context.addDocumentMetadata(try PDFProjectMetadata.encode(project) as CFData) }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.lineBreakMode = .byWordWrapping
        for index in 0..<source.pageCount {
            guard let page = source.page(at: index), let pageRef = page.pageRef else { throw ProjectError.invalidPDF }
            let notes = project.pages[index] ?? PageNotes()
            let comments = CommentLinks.ordered(notes)
            let numbers = Dictionary(uniqueKeysWithValues: comments.enumerated().map { ($1.id, $0 + 1) })
            let content = NSMutableAttributedString(attributedString: NotesMarkup.rendered(
                notes.text, appearance: .print(size: 11.5),
                comments: Dictionary(uniqueKeysWithValues: comments.enumerated().map { ($1.id, ($0 + 1, $1.comment.color.strong)) })))
            if !comments.isEmpty { content.append(footnotes(comments)) }
            if !notes.formula.isEmpty {
                content.append(NSAttributedString(string: "\n\n", attributes: [.font: NSFont.systemFont(ofSize: 11)]))
                content.append(MathNotation.formatted(notes.formula, size: 16))
            }
            if content.length == 0 && notes.drawing.isEmpty {
                content.append(NSAttributedString(string: "Keine Mitschrift zu dieser Folie.", attributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.darkGray
                ]))
            }
            let framesetter = CTFramesetterCreateWithAttributedString(content)
            var offset = 0
            var continuation = 0
            repeat {
                context.beginPDFPage(nil)
                context.setFillColor(NSColor.white.cgColor)
                context.fill(mediaBox)
                drawLabel(project.title, in: CGRect(x: 32, y: 548, width: 770, height: 20), size: 13, context: context)
                drawLabel("FOLIE \(index + 1) / \(source.pageCount)", in: CGRect(x: 32, y: 518, width: 460, height: 16), size: 9, context: context)
                drawLabel(continuation == 0 ? "MITSCHRIFT" : "MITSCHRIFT · FORTSETZUNG \(continuation)",
                          in: CGRect(x: 526, y: 518, width: 283, height: 16), size: 9, context: context)
                let slideRect = CGRect(x: 32, y: 72, width: 460, height: 428)
                let slideTransform = pageRef.getDrawingTransform(.cropBox, rect: slideRect, rotate: 0, preserveAspectRatio: true)
                context.saveGState()
                context.clip(to: slideRect)
                context.concatenate(slideTransform)
                context.drawPDFPage(pageRef)
                context.restoreGState()
                // The transform accounts for rotation and does not enlarge small pages, so ask it where the slide went.
                AnnotationRenderer.draw(notes.annotations, in: context, slideSize: page.displayedSlideSize,
                                        target: pageRef.getBoxRect(.cropBox).applying(slideTransform), commentNumbers: numbers)
                context.setStrokeColor(NSColor(white: 0.85, alpha: 1).cgColor)
                context.setLineWidth(0.5)
                context.move(to: CGPoint(x: 509, y: 55)); context.addLine(to: CGPoint(x: 509, y: 505)); context.strokePath()

                let hasDrawing = continuation == 0 && !notes.drawing.isEmpty
                let textBottom: CGFloat = hasDrawing ? 257 : 55
                let textRect = CGRect(x: 526, y: textBottom, width: 283, height: 500 - textBottom)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), CGPath(rect: textRect, transform: nil), nil)
                context.textMatrix = .identity
                CTFrameDraw(frame, context)
                let visible = CTFrameGetVisibleStringRange(frame)
                if offset < content.length && visible.length == 0 { throw ProjectError.exportFailed }
                offset += visible.length
                if hasDrawing {
                    drawLabel("SKIZZE", in: CGRect(x: 526, y: 226, width: 283, height: 16), size: 9, context: context)
                    context.saveGState()
                    // Ink uses a top-left origin.
                    context.translateBy(x: 526, y: 220)
                    context.scaleBy(x: 1, y: -1)
                    InkRenderer.draw(notes.drawing, in: context, rect: CGRect(x: 0, y: 0, width: 283, height: 176.875))
                    context.restoreGState()
                }
                drawLabel("UniPDF · \(index + 1)" + (continuation > 0 ? " · Fortsetzung \(continuation)" : ""),
                          in: CGRect(x: 32, y: 21, width: 775, height: 14), size: 8, context: context)
                context.endPDFPage()
                continuation += 1
            } while offset < content.length
        }
        context.closePDF()
        guard output.length > 0 else { throw ProjectError.exportFailed }
        return output as Data
    }

    /// The comments beneath the notes: number, the passage, then the comment, formatted like the notes.
    static func footnotes(_ comments: [(id: UUID, comment: SlideComment)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let spacing = NSMutableParagraphStyle()
        spacing.paragraphSpacingBefore = 10
        result.append(NSAttributedString(string: "\n\nKOMMENTARE", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.darkGray, .paragraphStyle: spacing
        ]))
        for (index, (_, comment)) in comments.enumerated() {
            let head = NSMutableParagraphStyle()
            head.paragraphSpacingBefore = 7
            result.append(NSAttributedString(string: "\n\(index + 1)  ", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: comment.color.strong.nsColor, .paragraphStyle: head
            ]))
            let quote = comment.isArea ? "Bereich auf der Folie" : "„\(comment.quote.split(whereSeparator: \.isWhitespace).joined(separator: " "))“"
            result.append(NSAttributedString(string: quote, attributes: [
                .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 10), toHaveTrait: .italicFontMask),
                .foregroundColor: NSColor.darkGray, .paragraphStyle: head
            ]))
            let body = comment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                result.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 4)]))
                result.append(NotesMarkup.rendered(body, appearance: .print(size: 11)))
            }
        }
        return result
    }

    private static func drawLabel(_ text: String, in rect: CGRect, size: CGFloat, context: CGContext) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.darkGray
        ])
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: rect.minX, y: rect.minY + 3)
        CTLineDraw(CTLineCreateWithAttributedString(string), context)
    }
}
