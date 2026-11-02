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
