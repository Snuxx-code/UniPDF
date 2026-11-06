import CoreGraphics
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
}
