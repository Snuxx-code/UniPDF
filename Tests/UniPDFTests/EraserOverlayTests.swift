import AppKit
import PDFKit
import Testing
import UniPDFCore
@testable import UniPDF

/// The eraser on the slide, driven with mouse events in an offscreen window.
@Suite @MainActor struct EraserOverlayTests {
    private final class Box { var annotations: [SlideAnnotation] = []; var commits = 0 }

    private func setUp(_ annotations: [SlideAnnotation]) throws -> (SlideCanvasView, PDFSession, PDFPage, NSWindow, Box) {
        let bytes = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: 800, height: 400)
        let consumer = try #require(CGDataConsumer(data: bytes))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &media, nil))
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        let document = try #require(PDFDocument(data: bytes as Data))
        let session = PDFSession()
        session.document = document
        let canvas = SlideCanvasView(session: session)
        canvas.frame = NSRect(x: 0, y: 0, width: 900, height: 900)
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.pdfView.displayMode = .singlePage
        canvas.pdfView.document = document
        canvas.pdfView.autoScales = true
        canvas.pdfView.layoutDocumentView()
        session.view = canvas.pdfView
        session.overlay = canvas.overlay
        let box = Box()
        box.annotations = annotations
        canvas.overlay.show(annotations, pageIndex: 0) { box.annotations = $0; box.commits += 1 }
        return (canvas, session, try #require(document.page(at: 0)), window, box)
    }

    private func mouse(_ type: NSEvent.EventType, _ slide: CGPoint, _ canvas: SlideCanvasView, _ page: PDFPage, _ window: NSWindow) throws -> NSEvent {
        let rect = canvas.pdfView.convert(page.bounds(for: .cropBox), from: page)
        let scale = rect.width / page.displayedSlideSize.width
        let location = canvas.pdfView.convert(CGPoint(x: rect.minX + slide.x * scale, y: rect.maxY - slide.y * scale), to: nil)
        return try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func drag(_ path: [CGPoint], _ canvas: SlideCanvasView, _ page: PDFPage, _ window: NSWindow) throws {
        canvas.overlay.mouseDown(with: try mouse(.leftMouseDown, path[0], canvas, page, window))
        for point in path.dropFirst() { canvas.overlay.mouseDragged(with: try mouse(.leftMouseDragged, point, canvas, page, window)) }
        canvas.overlay.mouseUp(with: try mouse(.leftMouseUp, path[path.count - 1], canvas, page, window))
    }

    private let blue = AnnotationColor(InkColor.blue)

    @Test func aQuickSwipeCutsAStrokeAndLeavesShapesAlone() throws {
        let stroke = SlideAnnotation(content: .ink(points: [CGPoint(x: 100, y: 200), CGPoint(x: 700, y: 200)], color: blue, width: 2))
        let box = SlideAnnotation(content: .shape(.rectangle, start: CGPoint(x: 380, y: 100), end: CGPoint(x: 420, y: 300), color: blue, width: 2))
        let (canvas, session, page, window, result) = try setUp([stroke, box])
        session.tool = .eraser
        session.style.eraserRadius = 10
        // Two events far apart, as a fast hand produces them.
        try drag([CGPoint(x: 400, y: 100), CGPoint(x: 400, y: 300)], canvas, page, window)
        let strokes = result.annotations.filter { if case .ink = $0.content { true } else { false } }
        #expect(strokes.count == 2)
        #expect(result.annotations.contains(box))
        // The whole swipe is one change, and so one undo step.
        #expect(result.commits == 1)
        #expect(session.tool == .eraser)
    }

    @Test func erasingAcrossAHighlightTrimsIt() throws {
        let highlight = SlideAnnotation(content: .highlight(rects: [CGRect(x: 100, y: 190, width: 400, height: 20)], color: PDFTextHighlight.yellow))
        let (canvas, session, page, window, result) = try setUp([highlight])
        session.tool = .eraser
        session.style.eraserRadius = 10
        try drag([CGPoint(x: 300, y: 150), CGPoint(x: 300, y: 250)], canvas, page, window)
        guard case .highlight(let rects, _)? = result.annotations.first?.content else { Issue.record("Highlight gone"); return }
        #expect(rects.count == 2)
        #expect(rects.allSatisfy { $0.maxX <= 291 || $0.minX >= 309 })
    }

    @Test func aClickOnEmptySlideChangesNothing() throws {
        let stroke = SlideAnnotation(content: .ink(points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100)], color: blue, width: 2))
        let (canvas, session, page, window, result) = try setUp([stroke])
        session.tool = .eraser
        try drag([CGPoint(x: 600, y: 300)], canvas, page, window)
        #expect(result.commits == 0)
        #expect(result.annotations == [stroke])
    }
}
