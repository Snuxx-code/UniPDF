import AppKit
import CoreText
import PDFKit
import Testing
import UniformTypeIdentifiers
import UniPDFCore
@testable import UniPDF

@Suite @MainActor struct DocumentSavingTests {
    private func lecturePDF() throws -> Data {
        let bytes = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 640, height: 360)
        let consumer = try #require(CGDataConsumer(data: bytes))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for pageNumber in 1...2 {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor)
            context.fill(box)
            context.textPosition = CGPoint(x: 40, y: 280)
            let label = NSAttributedString(string: "ORIGINALFOLIE \(pageNumber)", attributes: [.font: NSFont.systemFont(ofSize: 18)])
            CTLineDraw(CTLineCreateWithAttributedString(label), context)
            context.endPDFPage()
        }
        context.closePDF()
        return bytes as Data
    }

    @Test func nativeDocumentCanReadAndWritePDFs() {
        #expect(StudyDocument.readableContentTypes.contains(.pdf))
        #expect(StudyDocument.writableContentTypes.contains(.pdf))
        #expect(StudyDocument.readableContentTypes.contains(.uniPDF))
        #expect(StudyDocument.writableContentTypes.contains(.uniPDF))
    }

    @Test func savingReplacesOriginalAndRemainsEditableAfterReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Vorlesung.pdf")
        let original = try lecturePDF()
        try original.write(to: url)
        var document = try StudyDocument(data: Data(contentsOf: url), contentType: .pdf, title: "Vorlesung")
        var notes = PageNotes()
        notes.text = "Erste Mitschrift"
        notes.formula = "x^{2}"
        notes.drawing = [InkElement(tool: .arrow, color: .blue, points: [InkPoint(x: 40, y: 50), InkPoint(x: 600, y: 400)])]
        document.project.pages[0] = notes
        try document.contents(for: .pdf).write(to: url, options: .atomic)

        let firstSave = try Data(contentsOf: url)
        #expect(firstSave != original)
        #expect(PDFDocument(data: firstSave)?.string?.contains("Erste Mitschrift") == true)
        var reopened = try StudyDocument(data: firstSave, contentType: .pdf)
        #expect(reopened.project.pdfData == original)
        #expect(reopened.project.pages[0] == notes)

        reopened.project.pages[0]?.text = "Aktualisierte Mitschrift"
        try reopened.contents(for: .pdf).write(to: url, options: .atomic)
        let secondSave = try Data(contentsOf: url)
        let secondPDF = try #require(PDFDocument(data: secondSave))
        #expect(secondPDF.string?.contains("Aktualisierte Mitschrift") == true)
        #expect(secondPDF.string?.contains("Erste Mitschrift") == false)
        #expect(secondPDF.pageCount == 2)
        let restored = try StudyDocument(data: secondSave, contentType: .pdf)
        #expect(restored.project.pdfData == original)
        #expect(restored.project.pages[0]?.formula == notes.formula)
        #expect(restored.project.pages[0]?.drawing == notes.drawing)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["Vorlesung.pdf"])
    }

    @Test func legacyProjectStillOpensAndSaves() throws {
        let project = StudyProject(title: "Altes Projekt", pdfData: try lecturePDF())
        let document = try StudyDocument(data: project.encoded(), contentType: .uniPDF)
        let saved = try StudyProject.decode(document.contents(for: .uniPDF))
        #expect(saved.title == project.title)
        #expect(saved.pdfData == project.pdfData)
    }

    @Test func invalidPDFCannotBeOpened() {
        #expect(throws: ProjectError.self) {
            try StudyDocument(data: Data("kein PDF".utf8), contentType: .pdf)
        }
    }

    @Test func failedSerializationLeavesOriginalUntouched() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let original = try lecturePDF()
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        var document = try StudyDocument(data: original, contentType: .pdf)
        var invalidNotes = PageNotes()
        invalidNotes.drawing = [InkElement(tool: .pen, color: .graphite, width: .infinity,
                                           points: [InkPoint(x: 20, y: 20)])]
        document.project.pages[0] = invalidNotes
        #expect(throws: (any Error).self) {
            // Native FileDocument saving likewise needs a complete wrapper before writing.
            let replacement = try document.contents(for: .pdf)
            try replacement.write(to: url, options: .atomic)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func aiContextIncludesUnsavedChangesAndDoesNotOverwriteOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Meine Vorlesung.pdf")
        let original = try lecturePDF()
        try original.write(to: url)
        var project = StudyProject(title: "Vorlesung", pdfData: original)
        var notes = PageNotes()
        notes.text = "NOCH NICHT GESPEICHERTE MITSCHRIFT"
        notes.formula = "E = m c^{2}"
        project.pages[1] = notes
        let context = try AIQuestionContext.create(project: project, sourceURL: url, slideIndex: 1)
        defer { try? FileManager.default.removeItem(at: context.studyPDFURL.deletingLastPathComponent()) }
        let studyPDF = try #require(PDFDocument(url: context.studyPDFURL))
        let slidePDF = try #require(PDFDocument(url: context.slidePDFURL))
        #expect(studyPDF.string?.contains(notes.text) == true)
        #expect(slidePDF.pageCount == 1)
        #expect(slidePDF.string?.contains("ORIGINALFOLIE 2") == true)
        #expect(slidePDF.string?.contains("ORIGINALFOLIE 1") == false)
        #expect(context.slideNumber == 2)
        #expect(context.slideCount == 2)
        #expect(context.sourceURL == url)
        #expect(try Data(contentsOf: url) == original)
        let snapshot = try Data(contentsOf: context.studyPDFURL)
        #expect(try StudyPDF.open(snapshot).pages.isEmpty)
    }
}

@Suite @MainActor struct EditorWidthTests {
    @Test func dividerKeepsTheEditorWidth() {
        #expect(EditorWidthMemory.dividerPosition(totalWidth: 1200, editorWidth: 500, dividerThickness: 1) == 699)
    }

    @Test func bothPanesKeepTheirMinimumWidth() {
        // A remembered narrow pane from a smaller limit, and a wide one in a small window.
        #expect(EditorWidthMemory.dividerPosition(totalWidth: 1200, editorWidth: 100, dividerThickness: 1) == 849)
        #expect(EditorWidthMemory.dividerPosition(totalWidth: 800, editorWidth: 700, dividerThickness: 1) == 360)
    }
}

/// PDFView decides where an annotation appears on screen, the exporter where it appears in the PDF.
/// Both must agree on the slide's coordinates, whatever the rotation or zoom.
@Suite @MainActor struct AnnotationViewerTests {
    private func rotatedLecture(_ rotation: Int) throws -> Data {
        let bytes = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 640, height: 360)
        let consumer = try #require(CGDataConsumer(data: bytes))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor); context.fill(box)
        // A landmark only one spot of the page has.
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 80, y: 260, width: 40, height: 40))
        context.endPDFPage(); context.closePDF()
        let document = try #require(PDFDocument(data: bytes as Data))
        document.page(at: 0)?.rotation = rotation
        return try #require(document.dataRepresentation())
    }

    @Test(arguments: [(0, 1.0), (90, 1.0), (180, 1.0), (270, 1.0), (90, 1.7), (270, 0.6)])
    func viewerAndExportAgreeOnTheSlide(rotation: Int, zoom: Double) throws {
        let pdf = try rotatedLecture(rotation)
        let document = try #require(PDFDocument(data: pdf))
        let page = try #require(document.page(at: 0))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        let view = PDFView(frame: NSRect(x: 0, y: 0, width: 800, height: 800))
        window.contentView = view
        view.displayMode = .singlePage
        view.document = document
        view.autoScales = true
        view.layoutDocumentView()
        view.scaleFactor *= zoom
        view.layoutDocumentView()

        // The landmark's center, as the viewer sees it on the slide.
        let slide = view.convert(page.bounds(for: view.displayBox), from: page)
        let size = page.displayedSlideSize
        #expect(abs(slide.width / slide.height - size.width / size.height) < 0.01)
        let scale = slide.width / size.width
        let onScreen = view.convert(CGPoint(x: 100, y: 280), from: page)
        let point = CGPoint(x: (onScreen.x - slide.minX) / scale, y: (slide.maxY - onScreen.y) / scale)

        // A white patch placed exactly there has to cover the landmark in the export.
        let patch = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        patch.setFillColor(NSColor.white.cgColor)
        patch.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let patchCG = try #require(patch.makeImage())
        let patchImage = NSBitmapImageRep(cgImage: patchCG)
        var notes = PageNotes()
        let patchData = try #require(patchImage.representation(using: .png, properties: [:]))
        notes.annotations = [SlideAnnotation(content: .image(patchData,
                                                             frame: CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)))]
        func redPixels(_ data: Data) throws -> Int {
            let provider = try #require(CGDataProvider(data: data as CFData))
            let exported = try #require(CGPDFDocument(provider)?.page(at: 1))
            let context = try #require(CGContext(data: nil, width: 842, height: 596, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.drawPDFPage(exported)
            let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            var count = 0
            for offset in stride(from: 0, to: context.height * context.bytesPerRow, by: 4) where bytes[offset] > 200 && bytes[offset + 1] < 60 { count += 1 }
            return count
        }
        #expect(try redPixels(PDFExporter.export(StudyProject(pdfData: pdf))) > 100)
        #expect(try redPixels(PDFExporter.export(StudyProject(pdfData: pdf, pages: [0: notes]))) == 0)
    }

    @Test func annotatedDocumentSurvivesSavingAndReopening() throws {
        var document = try StudyDocument(data: rotatedLecture(90), contentType: .pdf)
        var notes = PageNotes()
        notes.annotations = [SlideAnnotation(content: .shape(.ellipse, start: CGPoint(x: 10, y: 20), end: CGPoint(x: 100, y: 60),
                                                             color: AnnotationColor(InkColor.green), width: 3))]
        document.project.pages[0] = notes
        let saved = try document.contents(for: .pdf)
        let reopened = try StudyDocument(data: saved, contentType: .pdf)
        #expect(reopened.project.pages[0] == notes)
        let again = try StudyDocument(data: reopened.contents(for: .pdf), contentType: .pdf)
        #expect(again.project.pages[0] == notes)
        #expect(again.project.pdfData == document.project.pdfData)
    }
}

/// Drives the annotation layer with real mouse events in an offscreen window.
@Suite @MainActor struct AnnotationOverlayTests {
    @MainActor private final class Harness {
        let session = PDFSession()
        let canvas: SlideCanvasView
        let window: NSWindow
        let page: PDFPage
        var committed: [SlideAnnotation] = []
        private var overlay: AnnotationOverlayView { canvas.overlay }

        init(rotation: Int = 0) throws {
            let bytes = NSMutableData()
            var box = CGRect(x: 0, y: 0, width: 800, height: 400)
            let consumer = try #require(CGDataConsumer(data: bytes))
            let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
            for _ in 0..<2 {
                context.beginPDFPage(nil)
                context.setFillColor(NSColor.white.cgColor); context.fill(box)
                context.endPDFPage()
            }
            context.closePDF()
            let document = try #require(PDFDocument(data: bytes as Data))
            page = try #require(document.page(at: 0))
            page.rotation = rotation
            session.document = document
            canvas = SlideCanvasView(session: session)
            canvas.frame = NSRect(x: 0, y: 0, width: 900, height: 900)
            window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = canvas
            canvas.pdfView.displayMode = .singlePage
            canvas.pdfView.document = document
            canvas.pdfView.autoScales = true
            canvas.pdfView.layoutDocumentView()
            session.view = canvas.pdfView
            session.overlay = canvas.overlay
            update()
        }

        /// What SwiftUI does after each change of the document.
        func update(pageIndex: Int = 0) {
            overlay.show(committed, pageIndex: pageIndex) { [unowned self] in committed = $0 }
        }

        private func event(_ type: NSEvent.EventType, at slide: CGPoint, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) throws -> NSEvent {
            let rect = canvas.pdfView.convert(page.bounds(for: .cropBox), from: page)
            let scale = rect.width / page.displayedSlideSize.width
            let location = canvas.pdfView.convert(CGPoint(x: rect.minX + slide.x * scale, y: rect.maxY - slide.y * scale), to: nil)
            return try #require(NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                                                   context: nil, eventNumber: 0, clickCount: clicks, pressure: 1))
        }

        func drag(from start: CGPoint, to end: CGPoint, flags: NSEvent.ModifierFlags = []) throws {
            overlay.mouseDown(with: try event(.leftMouseDown, at: start, flags: flags))
            overlay.mouseDragged(with: try event(.leftMouseDragged, at: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), flags: flags))
            overlay.mouseDragged(with: try event(.leftMouseDragged, at: end, flags: flags))
            overlay.mouseUp(with: try event(.leftMouseUp, at: end, flags: flags))
            update()
        }

        func click(_ point: CGPoint) throws {
            overlay.mouseDown(with: try event(.leftMouseDown, at: point))
            overlay.mouseUp(with: try event(.leftMouseUp, at: point))
            update()
        }
    }

    private func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }

    @Test func squareAndCircleStayRegularAndRectangleAndOvalDoNot() throws {
        for (shape, regular) in [(SlideShape.square, true), (.circle, true), (.rectangle, false), (.ellipse, false)] {
            let harness = try Harness()
            harness.session.tool = .shape(shape)
            try harness.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 150))
            let added = try #require(harness.committed.first)
            #expect(close(added.bounds, CGRect(x: 100, y: 100, width: 200, height: regular ? 200 : 50)))
            guard case .shape(let drawn, _, _, _, _) = added.content else { Issue.record("Not a shape"); continue }
            #expect(drawn == shape)
            // A finished shape is selected, ready to be adjusted.
            #expect(harness.session.tool == .select)
            #expect(harness.session.selectedAnnotation == added.id)
        }
    }

    @Test func regularShapesStopAtTheSlideEdge() throws {
        let harness = try Harness()
        harness.session.tool = .shape(.square)
        try harness.drag(from: CGPoint(x: 700, y: 100), to: CGPoint(x: 790, y: 390))
        let box = try #require(harness.committed.first).bounds
        #expect(abs(box.width - box.height) < 1)
        #expect(box.maxX <= 800.5)
    }

    @Test func linesKeepTheirDirectionAndShiftSnapsThem() throws {
        let harness = try Harness()
        harness.session.tool = .shape(.line)
        try harness.drag(from: CGPoint(x: 300, y: 200), to: CGPoint(x: 100, y: 100))
        guard case .shape(.line, let start, let end, _, _)? = harness.committed.first?.content else { Issue.record("Not a line"); return }
        #expect(abs(start.x - 300) < 1 && abs(end.x - 100) < 1)
        harness.session.tool = .shape(.line)
        try harness.drag(from: CGPoint(x: 100, y: 300), to: CGPoint(x: 300, y: 310), flags: .shift)
        guard case .shape(.line, let snappedStart, let snappedEnd, _, _)? = harness.committed.last?.content else { Issue.record("Not a line"); return }
        #expect(abs(snappedStart.y - snappedEnd.y) < 1)
    }

    @Test func aClickWithoutDraggingDrawsNoShape() throws {
        let harness = try Harness()
        harness.session.tool = .shape(.rectangle)
        try harness.click(CGPoint(x: 100, y: 100))
        #expect(harness.committed.isEmpty)
    }

    @Test(arguments: [0, 90, 180, 270]) func penUsesDisplayedCoordinatesOnEveryRotation(rotation: Int) throws {
        let harness = try Harness(rotation: rotation)
        harness.session.tool = .pen
        try harness.drag(from: CGPoint(x: 20, y: 30), to: CGPoint(x: 120, y: 60))
        let box = try #require(harness.committed.first).bounds
        #expect(close(box, CGRect(x: 20, y: 30, width: 100, height: 30)))
        // The pen stays in hand.
        #expect(harness.session.tool == .pen)
    }

    @Test func selectingMovingAndDeleting() throws {
        let harness = try Harness()
        harness.session.tool = .shape(.rectangle)
        try harness.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200))
        try harness.click(CGPoint(x: 500, y: 300))
        #expect(harness.session.selectedAnnotation == nil)
        // Inside an outlined shape is not on it.
        try harness.click(CGPoint(x: 150, y: 150))
        #expect(harness.session.selectedAnnotation == nil)
        try harness.drag(from: CGPoint(x: 100, y: 150), to: CGPoint(x: 300, y: 250))
        #expect(harness.session.selectedAnnotation == harness.committed.first?.id)
        let moved = try #require(harness.committed.first)
        #expect(close(moved.bounds, CGRect(x: 300, y: 200, width: 100, height: 100)))
        // Far beyond the edge, it stops at the slide.
        try harness.drag(from: CGPoint(x: 300, y: 250), to: CGPoint(x: 790, y: 395))
        let atEdge = try #require(harness.committed.first)
        #expect(close(atEdge.bounds, CGRect(x: 700, y: 300, width: 100, height: 100)))
        harness.canvas.overlay.deleteSelection()
        harness.update()
        #expect(harness.committed.isEmpty)
        #expect(harness.session.selectedAnnotation == nil)
    }

    @Test func handlesResizeAndAspectIsKeptForImages() throws {
        let harness = try Harness()
        harness.canvas.overlay.insertImage(try imageData(width: 400, height: 200))
        harness.update()
        let image = try #require(harness.committed.first).bounds
        #expect(abs(image.midX - 400) < 1 && abs(image.midY - 200) < 1)
        #expect(abs(image.width / image.height - 2) < 0.01)
        try harness.drag(from: CGPoint(x: image.maxX, y: image.maxY), to: CGPoint(x: image.maxX + 100, y: image.maxY))
        let resized = try #require(harness.committed.first).bounds
        #expect(resized.width > image.width)
        #expect(abs(resized.width / resized.height - 2) < 0.01)
        #expect(abs(resized.minX - image.minX) < 1 && abs(resized.minY - image.minY) < 1)
    }

    @Test func styleChangesApplyToTheSelection() throws {
        let harness = try Harness()
        harness.session.tool = .shape(.circle)
        try harness.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200))
        let green = AnnotationColor(InkColor.green)
        harness.session.style.color = green
        harness.session.style.lineWidth = 8
        harness.canvas.overlay.applyStyle()
        guard case .shape(_, _, _, let color, let width)? = harness.committed.first?.content else { Issue.record("Not a shape"); return }
        #expect(color == green)
        #expect(width == 8)
    }

    @Test func undoUpdatesTheBarAndDropsAVanishedSelection() throws {
        let harness = try Harness()
        harness.session.tool = .shape(.circle)
        try harness.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200))
        let drawn = harness.committed
        let original = harness.session.style.color
        harness.session.style.color = AnnotationColor(InkColor.green)
        harness.canvas.overlay.applyStyle()
        harness.committed = drawn
        harness.update()
        #expect(harness.session.style.color == original)
        harness.committed = []
        harness.update()
        #expect(harness.session.selectedAnnotation == nil)
    }

    @Test func imagesAndCopiesCanBePasted() throws {
        let harness = try Harness()
        let board = NSPasteboard(name: NSPasteboard.Name("de.unipdf.tests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setData(try imageData(width: 40, height: 40), forType: .png)
        harness.canvas.overlay.paste(from: board)
        harness.update()
        let image = try #require(harness.committed.first)
        guard case .image = image.content else { Issue.record("Not an image"); return }

        harness.canvas.overlay.copySelection(to: board)
        harness.canvas.overlay.paste(from: board)
        harness.update()
        #expect(harness.committed.count == 2)
        #expect(harness.committed[1].id != image.id)
        #expect(close(harness.committed[1].bounds, image.bounds.offsetBy(dx: 16, dy: 16)))

        board.clearContents()
        board.setString("Eingefügter Text", forType: .string)
        harness.canvas.overlay.paste(from: board)
        harness.update()
        guard case .text(let string, _, _, _, _)? = harness.committed.last?.content else { Issue.record("Not a text"); return }
        #expect(string == "Eingefügter Text")
    }

    @Test func theTextToolEditsInsideABoxAndMovesItByItsEdge() throws {
        for locked in [true, false] {
            let harness = try Harness()
            let previous = harness.session.keepsTextTool
            defer { harness.session.keepsTextTool = previous }
            harness.session.keepsTextTool = locked
            let frame = CGRect(x: 100, y: 100, width: 300, height: 40)
            let box = SlideAnnotation(content: .text("Hallo Welt und mehr", frame: frame, style: SlideTextStyle(),
                                                     color: AnnotationColor(InkColor.blue)))
            harness.committed = [box]
            harness.update()

            // Inside: the caret goes where the click was, nothing new appears.
            harness.session.tool = .text
            try harness.click(CGPoint(x: 160, y: 120))
            let editor = try #require(harness.window.firstResponder as? NSTextView)
            #expect(editor.selectedRange().length == 0)
            #expect((1..<19).contains(editor.selectedRange().location))
            #expect(harness.committed.count == 1)
            #expect(harness.session.tool == (locked ? .text : .select))

            // On the edge: dragging moves the box.
            harness.session.tool = .text
            try harness.drag(from: CGPoint(x: 101, y: 120), to: CGPoint(x: 201, y: 170))
            #expect(harness.committed.count == 1)
            #expect(close(harness.committed[0].bounds, frame.offsetBy(dx: 100, dy: 50)))
        }
    }

    @Test func scrollingDrawsOnTheSlideUnderThePointer() throws {
        let harness = try Harness()
        var stored: [Int: [SlideAnnotation]] = [:]
        harness.session.pageAnnotations = { stored[$0] ?? [] }
        harness.session.setPageAnnotations = { stored[$0] = $1 }
        let previous = harness.session.scrollsContinuously
        defer { harness.session.scrollsContinuously = previous }
        harness.session.scrollsContinuously = true
        let view = harness.canvas.pdfView
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.layoutDocumentView()
        let second = try #require(view.document?.page(at: 1))
        view.go(to: second)
        view.layoutDocumentView()
        try #require(view.visiblePages.contains { $0 === second })
        let rect = view.convert(second.bounds(for: .cropBox), from: second)
        func event(_ type: NSEvent.EventType, _ point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                                            windowNumber: harness.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        harness.session.tool = .pen
        let overlay = harness.canvas.overlay
        overlay.mouseDown(with: try event(.leftMouseDown, CGPoint(x: rect.midX - 60, y: rect.midY)))
        overlay.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: rect.midX, y: rect.midY + 20)))
        overlay.mouseUp(with: try event(.leftMouseUp, CGPoint(x: rect.midX + 60, y: rect.midY)))
        // The second slide became the current one, and the stroke belongs to it.
        #expect(harness.session.selection == 1)
        #expect(stored[1]?.count == 1)
        #expect(harness.committed.isEmpty)
    }

    @Test func theCommentToolCommentsAnAreaWhereThereIsNoText() throws {
        let harness = try Harness()
        var created: [SlideAnnotation] = []
        harness.session.createComment = { created.append($0) }
        harness.session.tool = .comment
        // The test slide has no text, so the drag becomes an area.
        try harness.drag(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
        let comment = try #require(created.first)
        guard case .comment(let content) = comment.content else { Issue.record("Not a comment"); return }
        #expect(content.isArea)
        #expect(close(comment.bounds, CGRect(x: 100, y: 100, width: 200, height: 100)))
        // Each new comment takes the next colour.
        #expect(harness.session.style.commentColor == content.color.next)
        // A click without a drag comments nothing.
        try harness.click(CGPoint(x: 500, y: 300))
        #expect(created.count == 1)
    }

    @Test func clickingACommentOpensItsCardAndOnlyAreasMove() throws {
        let harness = try Harness()
        let passage = SlideAnnotation(content: .comment(SlideComment(rects: [CGRect(x: 100, y: 100, width: 200, height: 20)], quote: "Text")))
        let area = SlideAnnotation(content: .comment(SlideComment(rects: [CGRect(x: 100, y: 250, width: 200, height: 80)], isArea: true)))
        harness.committed = [passage, area]
        harness.update()
        var opened: [UUID] = []
        harness.session.openComment = { opened.append($0) }
        try harness.drag(from: CGPoint(x: 150, y: 110), to: CGPoint(x: 250, y: 160))
        try harness.drag(from: CGPoint(x: 150, y: 290), to: CGPoint(x: 200, y: 300))
        #expect(opened == [passage.id, area.id])
        #expect(harness.committed[0].bounds == passage.bounds)
        #expect(close(harness.committed[1].bounds, area.bounds.offsetBy(dx: 50, dy: 10)))
    }

    @Test func searchSelectsAFoundTextBoxWithTheArrow() throws {
        let harness = try Harness()
        let box = SlideAnnotation(content: .text("Gesucht", frame: CGRect(x: 50, y: 50, width: 200, height: 30),
                                                 style: SlideTextStyle(), color: AnnotationColor(InkColor.blue)))
        harness.committed = [box]
        harness.update()
        harness.session.tool = .pen
        harness.canvas.overlay.reveal(box.id)
        #expect(harness.session.tool == .select)
        #expect(harness.session.selectedAnnotation == box.id)
    }

    @Test func aLockedTextToolStaysActiveForTheNextBox() throws {
        for locked in [false, true] {
            let harness = try Harness()
            let previous = harness.session.keepsTextTool
            defer { harness.session.keepsTextTool = previous }
            harness.session.keepsTextTool = locked
            harness.session.tool = .text
            try harness.click(CGPoint(x: 100, y: 100))
            let editor = try #require(harness.window.firstResponder as? NSTextView)
            editor.insertText("Erstes", replacementRange: editor.selectedRange())
            harness.update()
            try harness.click(CGPoint(x: 400, y: 300))
            #expect(harness.session.tool == (locked ? .text : .select))
            // Locked, the click starts the next box right away; otherwise it only ends the first.
            #expect((harness.window.firstResponder is NSTextView) == locked)
            #expect(harness.committed.count == 1)
        }
    }

    @Test func unreadableImagesReportAnError() throws {
        let harness = try Harness()
        harness.canvas.overlay.insertImage(Data("kein Bild".utf8))
        #expect(harness.committed.isEmpty)
        #expect(harness.session.annotationError != nil)
    }

    @Test func changingTheSlideDropsTheSelectionAndKeepsSlidesApart() throws {
        let harness = try Harness()
        harness.session.tool = .pen
        try harness.drag(from: CGPoint(x: 20, y: 30), to: CGPoint(x: 120, y: 60))
        harness.session.tool = .select
        try harness.click(CGPoint(x: 120, y: 60))
        #expect(harness.session.selectedAnnotation != nil)
        let firstSlide = harness.committed
        var secondSlide: [SlideAnnotation] = []
        harness.canvas.overlay.show([], pageIndex: 1) { secondSlide = $0 }
        #expect(harness.session.selectedAnnotation == nil)
        #expect(harness.committed == firstSlide)
        #expect(secondSlide.isEmpty)
    }

    private func imageData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.green.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
