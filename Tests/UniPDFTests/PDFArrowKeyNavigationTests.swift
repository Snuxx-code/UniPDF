import AppKit
import PDFKit
import Testing
@testable import UniPDF

@Suite @MainActor struct PDFArrowKeyNavigationTests {
    @MainActor private final class Harness {
        let session = PDFSession()
        let canvas: FocusableView
        let pdfView = RecordingPDFView()
        let window: NSWindow
        let navigator: PDFArrowKeyNavigation
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 1000, height: 700))

        init(pageCount: Int = 3) throws {
            let data = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: 640, height: 360)
            let consumer = try #require(CGDataConsumer(data: data))
            let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
            for _ in 0..<max(pageCount, 1) {
                context.beginPDFPage(nil); context.endPDFPage()
            }
            context.closePDF()
            let document = try #require(PDFDocument(data: data as Data))
            if pageCount == 0 { document.removePage(at: 0) }
            session.document = document
            canvas = FocusableView()
            canvas.frame = CGRect(x: 0, y: 0, width: 650, height: 700)
            root.addSubview(canvas)
            window = NSWindow(contentRect: root.frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.contentView = root
            pdfView.document = document
            session.view = pdfView
            navigator = PDFArrowKeyNavigation(canvas: canvas, session: session)
            window.makeFirstResponder(canvas)
        }

        func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [.function, .numericPad], repeatKey: Bool = false) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: repeatKey, keyCode: code))
        }

        func send(_ code: UInt16, flags: NSEvent.ModifierFlags = [.function, .numericPad], repeatKey: Bool = false,
                  in target: NSWindow? = nil) throws -> Bool {
            navigator.handle(try key(code, flags: flags, repeatKey: repeatKey), in: target ?? window)
        }
    }

    @Test(arguments: [(UInt16(123), -1), (UInt16(124), 1), (UInt16(125), 1), (UInt16(126), -1)])
    func arrowsNavigateExactlyOneSlide(code: UInt16, offset: Int) throws {
        let harness = try Harness()
        harness.session.selection = 1
        harness.pdfView.go(to: try #require(harness.session.document?.page(at: 1)))
        #expect(try harness.send(code))
        #expect(harness.session.selection == 1 + offset)
        #expect(harness.pdfView.currentPage === harness.session.document?.page(at: 1 + offset))
    }

    @Test func keyRepeatsStopAtBothEnds() throws {
        let harness = try Harness()
        for _ in 0..<8 { #expect(try harness.send(124, repeatKey: true)) }
        #expect(harness.session.selection == 2)
        for _ in 0..<8 { #expect(try harness.send(126, repeatKey: true)) }
        #expect(harness.session.selection == 0)
    }

    @Test(arguments: [NSEvent.ModifierFlags.command, .option, .control, .shift])
    func modifiedArrowsKeepTheirExistingMeaning(flags: NSEvent.ModifierFlags) throws {
        let harness = try Harness()
        #expect(try !harness.send(124, flags: flags))
        #expect(harness.session.selection == 0)
    }

    @Test func textEditorsAndSidebarControlsAreNotIntercepted() throws {
        let harness = try Harness()
        for insideCanvas in [false, true] {
            let editor = NSTextView(frame: CGRect(x: 0, y: 0, width: 250, height: 100))
            (insideCanvas ? harness.canvas : harness.root).addSubview(editor)
            #expect(harness.window.makeFirstResponder(editor))
            #expect(try !harness.send(124))
            editor.removeFromSuperview()
        }
        let field = NSTextField(frame: CGRect(x: 680, y: 0, width: 250, height: 30))
        harness.root.addSubview(field)
        #expect(harness.window.makeFirstResponder(field))
        #expect(try !harness.send(124))
        let list = FocusableView(frame: CGRect(x: 680, y: 50, width: 250, height: 200))
        harness.root.addSubview(list)
        #expect(harness.window.makeFirstResponder(list))
        #expect(try !harness.send(125))
        #expect(harness.session.selection == 0)
    }

    @Test func annotationSelectionAndOtherWindowsKeepTheirKeys() throws {
        let harness = try Harness()
        #expect(harness.window.makeFirstResponder(harness.canvas))
        harness.session.selectedAnnotation = UUID()
        #expect(try !harness.send(124))
        harness.session.selectedAnnotation = nil
        let other = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                             backing: .buffered, defer: true)
        #expect(try !harness.send(124, in: other))
        #expect(try !harness.send(0))
        #expect(harness.session.selection == 0)
        #expect(try harness.send(124))
        #expect(harness.session.selection == 1)
    }

    @Test func emptyDocumentsDoNotProduceNegativePageIndices() throws {
        let harness = try Harness(pageCount: 0)
        harness.session.move(1)
        #expect(harness.session.selection == 0)
        #expect(try !harness.send(124))
    }

    @Test func delayedPageNotificationsDoNotUndoFastNavigation() throws {
        let harness = try Harness()
        let coordinator = PDFPane.Coordinator()
        coordinator.session = harness.session
        let document = try #require(harness.session.document)
        let queuedSynchronization = { coordinator.synchronizeCurrentPage(in: harness.pdfView, document: document) }
        #expect(try harness.send(124))
        #expect(try harness.send(124))
        queuedSynchronization()
        #expect(harness.session.selection == 2)
        #expect(harness.pdfView.currentPage === harness.session.document?.page(at: 2))
    }

    @MainActor private final class FocusableView: NSView {
        override var acceptsFirstResponder: Bool { true }
    }

    /// Exercise navigation and focus routing without PDFKit's WindowServer/GPU tile rendering.
    @MainActor private final class RecordingPDFView: PDFView {
        private var source: PDFDocument?
        private var shown: PDFPage?
        override var document: PDFDocument? {
            get { source }
            set {
                source = newValue
                shown = (newValue?.pageCount ?? 0) > 0 ? newValue?.page(at: 0) : nil
            }
        }
        override var currentPage: PDFPage? { shown }
        override func go(to page: PDFPage) { shown = page }
    }
}
