import AppKit
import CoreText
import PDFKit
import Testing
import UniPDFCore
@testable import UniPDF

@Suite @MainActor struct TextMarkerOverlayTests {
    @MainActor private final class Harness {
        let session = PDFSession()
        let pdfView = GeometryPDFView()
        let overlay: AnnotationOverlayView
        let window: NSWindow
        let page: PDFPage
        var committed: [SlideAnnotation] = []

        init(hasText: Bool = false) throws {
            let bytes = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: 800, height: 400)
            let consumer = try #require(CGDataConsumer(data: bytes))
            let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(box)
            if hasText {
                for (text, y) in [("ERSTE TEXTZEILE", 300.0), ("ZWEITE TEXTZEILE", 250.0)] {
                    context.textPosition = CGPoint(x: 80, y: y)
                    let label = NSAttributedString(string: text, attributes: [
                        .font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black
                    ])
                    CTLineDraw(CTLineCreateWithAttributedString(label), context)
                }
            }
            context.endPDFPage()
            context.closePDF()
            let document = try #require(PDFDocument(data: bytes as Data))
            page = try #require(document.page(at: 0))
            session.document = document
            pdfView.document = document
            pdfView.frame = box
            overlay = AnnotationOverlayView(session: session, pdfView: pdfView)
            overlay.frame = box
            let root = NSView(frame: box)
            root.addSubview(pdfView)
            root.addSubview(overlay)
            window = NSWindow(contentRect: box, styleMask: [.titled], backing: .buffered, defer: true)
            window.contentView = root
            session.view = pdfView
            session.overlay = overlay
            update()
        }

        func update() {
            overlay.show(committed, pageIndex: 0) { [unowned self] in committed = $0 }
        }

        private func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: overlay.convert(point, to: nil),
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }

        func drag(from start: CGPoint, to end: CGPoint) throws {
            overlay.mouseDown(with: try event(.leftMouseDown, at: start))
            overlay.mouseDragged(with: try event(.leftMouseDragged, at: end))
            overlay.mouseUp(with: try event(.leftMouseUp, at: end))
            update()
        }

        func click(_ point: CGPoint) throws {
            overlay.mouseDown(with: try event(.leftMouseDown, at: point))
            overlay.mouseUp(with: try event(.leftMouseUp, at: point))
            update()
        }
    }

    @Test func textMarkerAppliesToAnExistingPDFSelectionOnce() throws {
        let harness = try Harness(hasText: true)
        harness.pdfView.currentSelection = harness.page.selection(for: NSRange(location: 0, length: harness.page.numberOfCharacters))
        harness.session.activateHighlighter()
        #expect(harness.session.tool == .highlight)
        #expect(harness.committed.count == 1)
        guard case .highlight(let rects, let color) = harness.committed.first?.content else { Issue.record("Not a highlight"); return }
        #expect(rects.count == 2)
        #expect(color == PDFTextHighlight.yellow)
        #expect(harness.pdfView.currentSelection == nil)
        harness.session.activateHighlighter()
        #expect(harness.committed.count == 1)
    }

    @Test func textMarkerSelectsTextLinesAndCanBeRecoloredAndDeleted() throws {
        let harness = try Harness(hasText: true)
        harness.session.activateHighlighter()
        try harness.drag(from: CGPoint(x: 80, y: 94), to: CGPoint(x: 240, y: 144))
        #expect(harness.committed.count == 1)
        let highlight = try #require(harness.committed.first)
        guard case .highlight(let rects, _) = highlight.content else { Issue.record("Not a highlight"); return }
        #expect(rects.count == 2)
        #expect(harness.session.tool == .highlight)
        try harness.click(CGPoint(x: 700, y: 350))
        #expect(harness.committed.count == 1)
        harness.session.tool = .select
        try harness.click(CGPoint(x: rects[0].midX, y: rects[0].midY))
        #expect(harness.session.selectedKind == .highlight)
        let markerColor = AnnotationColor(red: 1, green: 0.4, blue: 0.65)
        let penColor = harness.session.style.color
        harness.session.style.highlightColor = markerColor
        harness.overlay.applyStyle()
        guard case .highlight(let unchanged, let updated) = harness.committed.first?.content else { Issue.record("Not a highlight"); return }
        #expect(unchanged == rects)
        #expect(updated == markerColor)
        #expect(harness.session.style.color == penColor)
        harness.overlay.deleteSelection()
        #expect(harness.committed.isEmpty)
    }

    @Test func textMarkerReportsSlidesWithoutSelectableText() throws {
        let harness = try Harness()
        harness.session.activateHighlighter()
        try harness.drag(from: CGPoint(x: 80, y: 90), to: CGPoint(x: 200, y: 140))
        #expect(harness.committed.isEmpty)
        #expect(harness.session.annotationError?.contains("no selectable PDF text") == true)
    }

    @Test func foregroundAnnotationsRemainSelectableAboveHighlights() throws {
        let harness = try Harness(hasText: true)
        let frame = CGRect(x: 80, y: 80, width: 160, height: 30)
        let text = SlideAnnotation(content: .text("Vordergrund", frame: frame, style: SlideTextStyle(), color: PDFTextHighlight.yellow))
        // Even a more recently created marker is drawn and hit behind the text box.
        let highlight = SlideAnnotation(content: .highlight(rects: [frame], color: PDFTextHighlight.yellow))
        harness.committed = [text, highlight]
        harness.update()
        try harness.click(CGPoint(x: frame.midX, y: frame.midY))
        #expect(harness.session.selectedAnnotation == text.id)
    }


    /// Keep real PDF text selections and overlay events, without starting PDFKit GPU tiles.
    @MainActor private final class GeometryPDFView: PDFView {
        private var source: PDFDocument?
        private var selectedText: PDFSelection?
        override var document: PDFDocument? {
            get { source }
            set { source = newValue }
        }
        override var currentPage: PDFPage? { source?.page(at: 0) }
        override var currentSelection: PDFSelection? {
            get { selectedText }
            set { selectedText = newValue }
        }
        override func clearSelection() { selectedText = nil }
        override func convert(_ rect: NSRect, from page: PDFPage?) -> NSRect { rect }
        override func convert(_ point: NSPoint, to page: PDFPage?) -> NSPoint { point }
    }
}
