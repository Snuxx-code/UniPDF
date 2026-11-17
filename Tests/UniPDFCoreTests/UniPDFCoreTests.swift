import AppKit
import CoreText
import PDFKit
import Testing
@testable import UniPDFCore

@Suite struct ProjectTests {
    @Test func portableProjectRoundTrip() throws {
        var notes = PageNotes()
        notes.text = "Änderung der Größe – 中文 🎓"
        notes.formula = "E = m c^{2}"
        notes.drawing = [InkElement(tool: .arrow, color: .blue, points: [InkPoint(x: 5, y: 6), InkPoint(x: 500, y: 400)])]
        let original = StudyProject(title: "Mathematik", pdfData: Data([1, 2, 3]), pages: [0: notes])
        let restored = try StudyProject.decode(original.encoded())
        #expect(restored.title == original.title)
        #expect(restored.pdfData == original.pdfData)
        #expect(restored.pages[0] == notes)
    }

    @Test func rejectsFutureVersionAndInvalidCoordinates() throws {
        var project = StudyProject()
        project.version = StudyProject.currentVersion + 1
        #expect(throws: ProjectError.self) { try StudyProject.decode(project.encoded()) }
        project.version = StudyProject.currentVersion
        var notes = PageNotes()
        notes.drawing = [InkElement(tool: .pen, color: .graphite, points: [InkPoint(x: -1, y: 10)])]
        project.pages[0] = notes
        #expect(throws: ProjectError.self) { try StudyProject.decode(project.encoded()) }
        #expect(throws: ProjectError.self) { try PDFExporter.validatedDocument(data: Data("kein PDF".utf8)) }
    }

    @Test func mathPreservesUnknownNotationAndFormatsScripts() {
        let formatted = MathNotation.formatted("x^{2} + a_{n} = \\alpha \\unknown")
        #expect(formatted.string == "x2 + an = α \\unknown")
        #expect((formatted.attribute(.baselineOffset, at: 1, effectiveRange: nil) as? CGFloat ?? 0) > 0)
        #expect(MathNotation.formatted("\\frac{a}{b}").string.contains("a ⁄ b"))
        #expect(MathNotation.formatted("x^{unfinished").string.contains("{unfinished"))
        #expect(MathNotation.formatted("\\frac{\\alpha^{2}}{\\sqrt{x}}").string == "(α2 ⁄ √(x))")
    }
}

@Suite @MainActor struct ExportTests {
    private func sourcePDF(rotation: Int = 0, metadata: Data? = nil) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 640, height: 360)
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        if let metadata { context.addDocumentMetadata(metadata as CFData) }
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor); context.fill(box)
        context.textPosition = CGPoint(x: 35, y: 280)
        let text = NSAttributedString(string: "TESTVORLESUNG: Lineare Algebra", attributes: [.font: NSFont.systemFont(ofSize: 24)])
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 40, y: 50, width: 240, height: 120))
        context.endPDFPage(); context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        document.page(at: 0)?.rotation = rotation
        return try #require(document.dataRepresentation())
    }

    @Test func longNotesContinueWithoutLosingText() throws {
        var notes = PageNotes()
        notes.text = "ANFANG DER MITSCHRIFT\n" + String(repeating: "Ein Vektor ist ein Element eines Vektorraums. Äquivalenz und Größe.\n", count: 180) + "\nENDE DER MITSCHRIFT"
        notes.formula = "E = m c^{2}"
        notes.drawing = [InkElement(tool: .rectangle, color: .green, points: [InkPoint(x: 20, y: 20), InkPoint(x: 700, y: 450)])]
        let result = try PDFExporter.export(StudyProject(title: "Test", pdfData: sourcePDF(), pages: [0: notes]))
        let document = try #require(PDFDocument(data: result))
        #expect(document.pageCount > 2)
        let text = document.string ?? ""
        #expect(text.contains("ANFANG DER MITSCHRIFT"))
        #expect(text.contains("ENDE DER MITSCHRIFT"))
        #expect(text.contains("TESTVORLESUNG"))
        #expect(text.contains("CONTINUED"))
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).width == 841.89)
    }

    @Test(arguments: [0, 90, 180, 270]) func rotatedSlidesRemainReadable(rotation: Int) throws {
        let result = try PDFExporter.export(StudyProject(title: "Rotation", pdfData: sourcePDF(rotation: rotation)))
        let document = try #require(PDFDocument(data: result))
        #expect(document.pageCount == 1)
        #expect(document.string?.contains("TESTVORLESUNG") == true)
        #expect(document.string?.contains("No notes") == true)
    }

    @Test func drawingOnlyStillExportsOnePage() throws {
        var notes = PageNotes()
        notes.drawing = [InkElement(tool: .pen, color: .red, points: [InkPoint(x: 100, y: 100)])]
        let result = try PDFExporter.export(StudyProject(pdfData: sourcePDF(), pages: [0: notes]))
        #expect(PDFDocument(data: result)?.pageCount == 1)
    }

    @Test func unbrokenTextIsNotClippedOrDropped() throws {
        var notes = PageNotes()
        notes.text = String(repeating: "Q", count: 12000) + "\nENDE"
        let result = try PDFExporter.export(StudyProject(pdfData: sourcePDF(), pages: [0: notes]))
        let document = try #require(PDFDocument(data: result))
        let text = document.string ?? ""
        #expect(text.filter { $0 == "Q" }.count == 12000)
        #expect(text.contains("ENDE"))
    }

    @Test func largeEmbeddedLectureCanBeRestored() throws {
        // Lecture PDFs routinely exceed XML parsers' single-text-node limits.
        let original = Data(repeating: 0xAD, count: 8 * 1024 * 1024)
        let project = StudyProject(title: "Große Vorlesung", pdfData: original)
        let saved = try sourcePDF(metadata: PDFProjectMetadata.encode(project))
        let decoded = try PDFProjectMetadata.decode(from: saved)
        let restored = try #require(decoded)
        #expect(restored.pdfData == original)
    }
}
