import AppKit
import CoreText
import PDFKit
import Testing
@testable import UniPDFCore

@Suite struct EraserTests {
    private let red = AnnotationColor(red: 1, green: 0, blue: 0)

    private func stroke(_ points: [CGPoint], width: Double = 2) -> SlideAnnotation {
        SlideAnnotation(content: .ink(points: points, color: red, width: width))
    }

    private func points(_ annotation: SlideAnnotation) -> [CGPoint] {
        guard case .ink(let points, _, _) = annotation.content else { return [] }
        return points
    }

    @Test func aMissedStrokeStaysTheSame() {
        let line = stroke([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
        #expect(line.erasing(around: CGPoint(x: 50, y: 50), radius: 10) == [line])
    }

    @Test func erasingTheMiddleLeavesTwoPieces() {
        let line = stroke([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], width: 2)
        let pieces = line.erasing(around: CGPoint(x: 50, y: 0), radius: 10)
        #expect(pieces.count == 2)
        // Reach is the radius plus half the stroke width.
        #expect(abs(points(pieces[0]).last!.x - 39) < 0.01)
        #expect(abs(points(pieces[1]).first!.x - 61) < 0.01)
        #expect(pieces[0].id == line.id)
        #expect(pieces[1].id != line.id)
    }

    @Test func aCutBetweenSparsePointsIsFound() {
        // A quick stroke may have only its two ends; the eraser still has to cut in between.
        let line = stroke([CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 400)])
        #expect(line.erasing(around: CGPoint(x: 200, y: 200), radius: 5).count == 2)
    }

    @Test func erasingTheEndShortensAndErasingAllRemoves() {
        let line = stroke([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)])
        let shortened = line.erasing(around: CGPoint(x: 100, y: 0), radius: 20)
        #expect(shortened.count == 1)
        #expect(abs(points(shortened[0]).last!.x - 79) < 0.01)
        #expect(line.erasing(around: CGPoint(x: 50, y: 0), radius: 100).isEmpty)
        #expect(stroke([CGPoint(x: 5, y: 5)]).erasing(around: CGPoint(x: 6, y: 5), radius: 3).isEmpty)
    }

    @Test func tinyLeftoversAreDropped() {
        let line = stroke([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)], width: 8)
        // Only a sliver of 0.5 points would remain on the left.
        let pieces = line.erasing(around: CGPoint(x: 18.5, y: 0), radius: 14)
        #expect(pieces.count == 1)
        #expect(points(pieces[0]).first!.x > 30)
    }

    @Test func highlightsKeepTheTextBesideTheEraser() {
        let highlight = SlideAnnotation(content: .highlight(rects: [CGRect(x: 0, y: 0, width: 200, height: 20),
                                                                    CGRect(x: 0, y: 40, width: 200, height: 20)], color: red))
        let erased = highlight.erasing(around: CGPoint(x: 100, y: 10), radius: 10)
        guard case .highlight(let rects, _)? = erased.first?.content else { Issue.record("No highlight left"); return }
        #expect(erased.first?.id == highlight.id)
        #expect(rects == [CGRect(x: 0, y: 0, width: 90, height: 20), CGRect(x: 110, y: 0, width: 90, height: 20),
                          CGRect(x: 0, y: 40, width: 200, height: 20)])
    }

    @Test func turnedHighlightsAreCutAlongTheirText() {
        let vertical = SlideAnnotation(content: .highlight(rects: [CGRect(x: 0, y: 0, width: 20, height: 200)], color: red))
        guard case .highlight(let rects, _)? = vertical.erasing(around: CGPoint(x: 10, y: 100), radius: 10).first?.content else {
            Issue.record("No highlight left"); return
        }
        #expect(rects == [CGRect(x: 0, y: 0, width: 20, height: 90), CGRect(x: 0, y: 110, width: 20, height: 90)])
    }

    @Test func aFullyErasedHighlightDisappears() {
        let highlight = SlideAnnotation(content: .highlight(rects: [CGRect(x: 0, y: 0, width: 30, height: 20)], color: red))
        #expect(highlight.erasing(around: CGPoint(x: 15, y: 10), radius: 20).isEmpty)
    }

    @Test func onlyStrokesAndHighlightsAreErasable() {
        #expect(stroke([.zero]).isErasable)
        #expect(SlideAnnotation(content: .highlight(rects: [CGRect(x: 0, y: 0, width: 1, height: 1)], color: red)).isErasable)
        #expect(!SlideAnnotation(content: .shape(.line, start: .zero, end: CGPoint(x: 10, y: 10), color: red, width: 2)).isErasable)
        #expect(!SlideAnnotation(content: .text("A", frame: CGRect(x: 0, y: 0, width: 10, height: 10), style: SlideTextStyle(), color: red)).isErasable)
    }

    @Test func preciseErasingRemovesWholeCharacters() {
        // Ten characters of ten points each, one line.
        let characters = (0..<20).map { CGRect(x: CGFloat($0) * 10, y: 2, width: 10, height: 16) }
        let highlight = SlideAnnotation(content: .highlight(rects: [CGRect(x: 0, y: 0, width: 200, height: 20)], color: red))
        // The eraser only grazes the bottom of the character at 100–110 and ends inside it.
        let erased = highlight.erasing(around: CGPoint(x: 103, y: 21), radius: 4, characters: characters)
        guard case .highlight(let rects, _)? = erased.first?.content else { Issue.record("No highlight left"); return }
        #expect(rects == [CGRect(x: 0, y: 0, width: 100, height: 20), CGRect(x: 110, y: 0, width: 90, height: 20)])
        // Across two characters, both go whole.
        guard case .highlight(let wider, _)? = highlight.erasing(around: CGPoint(x: 100, y: 10), radius: 3, characters: characters).first?.content else {
            Issue.record("No highlight left"); return
        }
        #expect(wider == [CGRect(x: 0, y: 0, width: 90, height: 20), CGRect(x: 110, y: 0, width: 90, height: 20)])
    }

    @Test func withoutATextLayerTheHighlightIsCutWhereTouched() {
        let highlight = SlideAnnotation(content: .highlight(rects: [CGRect(x: 0, y: 0, width: 200, height: 20)], color: red))
        #expect(highlight.erasing(around: CGPoint(x: 100, y: 10), radius: 10, characters: [])
                == highlight.erasing(around: CGPoint(x: 100, y: 10), radius: 10))
    }

    @Test func touchingNoCharacterLeavesTheHighlight() {
        let characters = [CGRect(x: 0, y: 2, width: 10, height: 16), CGRect(x: 30, y: 2, width: 10, height: 16)]
        let highlight = SlideAnnotation(content: .highlight(rects: [CGRect(x: 0, y: 0, width: 40, height: 20)], color: red))
        #expect(highlight.erasing(around: CGPoint(x: 20, y: 10), radius: 3, characters: characters) == [highlight])
    }

    @Test func characterRectsFollowTheDisplayedSlide() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 640, height: 360)
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.textPosition = CGPoint(x: 40, y: 300)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "ABC", attributes: [.font: NSFont.systemFont(ofSize: 24)])), context)
        context.endPDFPage(); context.closePDF()
        let page = try #require(PDFDocument(data: data as Data)?.page(at: 0))
        let upright = PDFTextHighlight.characterRects(on: page)
        #expect(upright.count == 3)
        // Top-left origin: the line near the top of the page is near the top of the slide.
        #expect(abs(upright[0].minX - 40) < 3 && upright[0].minY < 60)
        page.rotation = 90
        let turned = PDFTextHighlight.characterRects(on: page)
        // A turned page shows the line running downwards along the right edge.
        #expect(turned[0].minY < turned[2].minY && turned[0].minX > 290)
    }

    @Test func viewerLayersSplitHighlightsFromTheRest() throws {
        func pixels(_ layer: AnnotationRenderer.Layer) throws -> (yellow: Bool, blue: Bool) {
            let context = try #require(CGContext(data: nil, width: 100, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let highlight = SlideAnnotation(content: .highlight(rects: [CGRect(x: 0, y: 0, width: 40, height: 40)], color: PDFTextHighlight.yellow))
            let stroke = SlideAnnotation(content: .ink(points: [CGPoint(x: 60, y: 20), CGPoint(x: 95, y: 20)], color: AnnotationColor(red: 0, green: 0, blue: 1), width: 10))
            AnnotationRenderer.draw([highlight, stroke], in: context, layer: layer)
            let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            func alpha(x: Int) -> UInt8 { bytes[20 * context.bytesPerRow + x * 4 + 3] }
            return (alpha(x: 20) > 0, alpha(x: 80) > 0)
        }
        #expect(try pixels(.all) == (true, true))
        #expect(try pixels(.highlights) == (true, false))
        #expect(try pixels(.marks) == (false, true))
    }
}
