import AppKit
import CoreText
import PDFKit
import Testing
@testable import UniPDFCore

private func textLecture(rotation: Int = 0, cropped: Bool = false) throws -> PDFDocument {
    let bytes = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 640, height: 360)
    let consumer = try #require(CGDataConsumer(data: bytes))
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    for _ in 0..<2 {
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(box)
        for (text, y) in [("ERSTE TEXTZEILE", 280.0), ("ZWEITE TEXTZEILE", 230.0)] {
            context.textPosition = CGPoint(x: 80, y: y)
            let label = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black
            ])
            CTLineDraw(CTLineCreateWithAttributedString(label), context)
        }
        context.endPDFPage()
    }
    context.closePDF()
    let source = try #require(PDFDocument(data: bytes as Data))
    let page = try #require(source.page(at: 0))
    page.rotation = rotation
    if cropped { page.setBounds(CGRect(x: 60, y: 200, width: 400, height: 120), for: .cropBox) }
    let data = try #require(source.dataRepresentation())
    return try #require(PDFDocument(data: data))
}

private func allText(on page: PDFPage) throws -> PDFSelection {
    try #require(page.selection(for: NSRange(location: 0, length: page.numberOfCharacters)))
}

@Suite struct TextHighlightTests {
    @Test func highlightsFollowIndividualLinesAndIgnoreTheGap() throws {
        let document = try textLecture()
        let page = try #require(document.page(at: 0))
        let selection = try allText(on: page)
        let annotation = try #require(PDFTextHighlight.annotation(for: selection, on: page))
        guard case .highlight(let rects, let color) = annotation.content else { Issue.record("Not a highlight"); return }
        #expect(rects.count == 2)
        #expect(color == PDFTextHighlight.yellow)
        #expect(annotation.contains(CGPoint(x: rects[0].midX, y: rects[0].midY), tolerance: 0))
        let gap = CGPoint(x: rects[0].midX, y: (rects[0].midY + rects[1].midY) / 2)
        #expect(!annotation.contains(gap, tolerance: 0))
        #expect(annotation.isValid)
    }

    @Test func emptyAndForeignPageSelectionsAreIgnored() throws {
        let document = try textLecture()
        let first = try #require(document.page(at: 0))
        let second = try #require(document.page(at: 1))
        #expect(PDFTextHighlight.annotation(for: PDFSelection(document: document), on: first) == nil)
        #expect(try PDFTextHighlight.annotation(for: allText(on: second), on: first) == nil)
    }

    @Test func highlightsRemainEditableAfterRepeatedPDFSaves() throws {
        let document = try textLecture(rotation: 90)
        let page = try #require(document.page(at: 0))
        let highlight = try #require(PDFTextHighlight.annotation(for: allText(on: page), on: page))
        var notes = PageNotes()
        notes.annotations = [highlight]
        let original = try #require(document.dataRepresentation())
        let project = StudyProject(pdfData: original, pages: [0: notes])
        let reopened = try StudyPDF.open(PDFExporter.export(project))
        let again = try StudyPDF.open(PDFExporter.export(reopened))
        #expect(again.pages[0] == notes)
        #expect(again.pdfData == original)
        #expect(again.version == 3)
        #expect(!notes.isEmpty)
    }

    @Test func rejectsInvalidHighlightGeometry() throws {
        #expect(!SlideAnnotation(content: .highlight(rects: [.null], color: PDFTextHighlight.yellow)).isValid)
        for rects in [[], [CGRect.zero], [CGRect(x: 0, y: 0, width: 0, height: 10)]] {
            var notes = PageNotes()
            notes.annotations = [SlideAnnotation(content: .highlight(rects: rects, color: PDFTextHighlight.yellow))]
            #expect(throws: ProjectError.self) { try StudyProject.decode(StudyProject(pages: [0: notes]).encoded()) }
        }
    }

    @Test func highlightsCanBeMovedAndResizedWithoutFillingLineGaps() {
        let rects = [CGRect(x: 10, y: 20, width: 100, height: 10), CGRect(x: 10, y: 60, width: 50, height: 10)]
        let highlight = SlideAnnotation(content: .highlight(rects: rects, color: PDFTextHighlight.yellow))
        let moved = highlight.moved(by: CGVector(dx: 5, dy: 10))
        #expect(moved.bounds == CGRect(x: 15, y: 30, width: 100, height: 50))
        let resized = highlight.resized(to: CGRect(x: 100, y: 100, width: 200, height: 100))
        guard case .highlight(let transformed, _) = resized.content else { Issue.record("Not a highlight"); return }
        #expect(transformed == [CGRect(x: 100, y: 100, width: 200, height: 20), CGRect(x: 100, y: 180, width: 100, height: 20)])
        #expect(!resized.contains(CGPoint(x: 120, y: 150), tolerance: 0))
    }

    @Test func versionTwoProjectsStillOpen() throws {
        var project = StudyProject(title: "Version 2")
        project.version = 2
        let restored = try StudyProject.decode(project.encoded())
        #expect(restored.title == project.title)
        #expect(restored.version == 3)
    }
}

@Suite @MainActor struct TextHighlightRenderingTests {
    @Test func markerStaysTranslucentAndPreservesBlackText() throws {
        let context = try #require(CGContext(data: nil, width: 100, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 40))
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 20, y: 10, width: 5, height: 20))
        let rect = CGRect(x: 10, y: 5, width: 80, height: 30)
        let highlight = SlideAnnotation(content: .highlight(rects: [rect, rect], color: PDFTextHighlight.yellow))
        AnnotationRenderer.draw([highlight], in: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let black = 20 * context.bytesPerRow + 22 * 4
        #expect(bytes[black] < 10 && bytes[black + 1] < 10 && bytes[black + 2] < 10)
        let yellow = 20 * context.bytesPerRow + 60 * 4
        #expect(bytes[yellow] > 240 && bytes[yellow + 1] > 220)
        #expect(bytes[yellow + 2] > 160 && bytes[yellow + 2] < 200)
    }

    @Test(arguments: [0, 90, 180, 270])
    func exportedHighlightsMatchSelectedTextOnRotatedAndCroppedSlides(rotation: Int) throws {
        let document = try textLecture(rotation: rotation, cropped: true)
        let page = try #require(document.page(at: 0))
        let selection = try allText(on: page)
        let highlight = try #require(PDFTextHighlight.annotation(for: selection, on: page))
        var notes = PageNotes()
        notes.annotations = [highlight]
        let exported = try PDFExporter.export(StudyProject(pdfData: document.dataRepresentation(), pages: [0: notes]))
        let dataProvider = try #require(CGDataProvider(data: exported as CFData))
        let output = try #require(CGPDFDocument(dataProvider)?.page(at: 1))
        let context = try #require(CGContext(data: nil, width: 842, height: 596, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.drawPDFPage(output)
        let reference = try #require(page.pageRef)
        let transform = reference.getDrawingTransform(.cropBox, rect: CGRect(x: 32, y: 72, width: 460, height: 428), rotate: 0, preserveAspectRatio: true)
        let expected = selection.selectionsByLine().map { $0.bounds(for: page).applying(transform).insetBy(dx: -2, dy: -2) }
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var markedPixels = 0
        var misplacedPixels = 0
        for row in 0..<context.height {
            for column in 0..<context.width {
                let offset = row * context.bytesPerRow + column * 4
                if bytes[offset] > 235 && bytes[offset + 1] > 205 && bytes[offset + 2] < 220 {
                    markedPixels += 1
                    let pdfPoint = CGPoint(x: CGFloat(column) + 0.5, y: CGFloat(context.height - 1 - row) + 0.5)
                    if !expected.contains(where: { $0.contains(pdfPoint) }) { misplacedPixels += 1 }
                }
            }
        }
        #expect(markedPixels > 100)
        #expect(misplacedPixels == 0)
        #expect(PDFDocument(data: exported)?.string?.contains("ERSTE TEXTZEILE") == true)
    }
}
