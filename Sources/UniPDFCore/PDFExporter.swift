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
                comments: Dictionary(uniqueKeysWithValues: comments.enumerated().map {
                    ($1.id, NotesMarkup.CommentMark(number: $0 + 1, label: $1.comment.label, color: $1.comment.color))
                })))
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
                // Beneath the text: the tags' pastel and the bars beside the comments.
                drawCommentDecorations(frame, content: content, in: textRect, context: context)
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

    /// Marks a comment's footnote, so that a bar in its colour runs along all of it.
    static let barKey = NSAttributedString.Key("UniPDFCommentBar")

    /// One footnote's bar; a class, so that two footnotes in the same colour stay apart.
    final class CommentBar: NSObject {
        let color: NSColor
        init(_ color: NSColor) { self.color = color }
    }

    static let footnoteIndent: CGFloat = 10

    /// The comments beneath the notes: each its tag, as in the app, then the comment formatted like the notes,
    /// with a bar in the comment's colour beside all of it.
    static func footnotes(_ comments: [(id: UUID, comment: SlideComment)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let spacing = NSMutableParagraphStyle()
        spacing.paragraphSpacingBefore = 10
        result.append(NSAttributedString(string: "\n\nKOMMENTARE", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.darkGray, .paragraphStyle: spacing
        ]))
        for (index, (_, comment)) in comments.enumerated() {
            let footnote = NSMutableAttributedString()
            let head = NSMutableParagraphStyle()
            head.paragraphSpacingBefore = 9
            head.paragraphSpacing = 2
            footnote.append(NotesMarkup.chip(NotesMarkup.CommentMark(number: index + 1, label: comment.label, color: comment.color), size: 9.5))
            footnote.addAttribute(.paragraphStyle, value: head, range: NSRange(location: 0, length: footnote.length))
            let body = comment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                footnote.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 11), .paragraphStyle: head]))
                footnote.append(NotesMarkup.rendered(body, appearance: .print(size: 11)))
            }
            // Every paragraph of the footnote moves in, to leave room for the bar.
            let all = NSRange(location: 0, length: footnote.length)
            footnote.enumerateAttribute(.paragraphStyle, in: all) { value, range, _ in
                let paragraph = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                paragraph.headIndent += footnoteIndent
                paragraph.firstLineHeadIndent += footnoteIndent
                paragraph.tabStops = paragraph.tabStops.map { NSTextTab(textAlignment: $0.alignment, location: $0.location + footnoteIndent) }
                footnote.addAttribute(.paragraphStyle, value: paragraph, range: range)
            }
            footnote.addAttribute(barKey, value: CommentBar(comment.color.strong.nsColor), range: all)
            result.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: 4)]))
            result.append(footnote)
        }
        return result
    }

    /// Paints the pastel of the tags and the bars of the footnotes on one page, before its text.
    static func drawCommentDecorations(_ frame: CTFrame, content: NSAttributedString, in rect: CGRect, context: CGContext) {
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        guard !lines.isEmpty else { return }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        var bars: [(bar: CommentBar, top: CGFloat, bottom: CGFloat)] = []
        for (line, origin) in zip(lines, origins) {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let baseline = rect.minY + origin.y
            let range = CTLineGetStringRange(line)
            guard range.length > 0, range.location < content.length else { continue }
            // The bar follows every line of its footnote.
            if let bar = content.attribute(barKey, at: range.location, effectiveRange: nil) as? CommentBar {
                if let last = bars.last, last.bar === bar { bars[bars.count - 1].bottom = baseline - descent }
                else { bars.append((bar, baseline + ascent, baseline - descent)) }
            }
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let runRange = CTRunGetStringRange(run)
                guard runRange.location < content.length,
                      let fill = content.attribute(NotesMarkup.chipKey, at: runRange.location, effectiveRange: nil) as? NSColor else { continue }
                var runAscent: CGFloat = 0, runDescent: CGFloat = 0
                let width = CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0), &runAscent, &runDescent, nil)
                let x = rect.minX + origin.x + CTLineGetOffsetForStringIndex(line, runRange.location, nil)
                let chip = CGRect(x: x, y: baseline - runDescent - 1.5, width: width, height: runAscent + runDescent + 3)
                context.setFillColor(fill.cgColor)
                context.addPath(CGPath(roundedRect: chip, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil))
                context.fillPath()
            }
        }
        for (bar, top, bottom) in bars {
            let line = CGRect(x: rect.minX + 1, y: bottom, width: 2.5, height: top - bottom)
            context.setFillColor(bar.color.cgColor)
            context.addPath(CGPath(roundedRect: line, cornerWidth: 1.25, cornerHeight: 1.25, transform: nil))
            context.fillPath()
        }
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
