import PDFKit
import Testing
@testable import UniPDF
@testable import UniPDFCore

@MainActor
struct DocumentSearchTests {
    private func document(_ pages: Int) throws -> PDFDocument {
        let bytes = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 200, height: 100)
        let consumer = try #require(CGDataConsumer(data: bytes))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<pages { context.beginPDFPage(nil); context.endPDFPage() }
        context.closePDF()
        return try #require(PDFDocument(data: bytes as Data))
    }

    @Test func stepsThroughHitsAroundTheEndAndShowsEach() throws {
        let search = DocumentSearch()
        var shown: [Int] = []
        search.reveal = { shown.append($0.page) }
        var first = PageNotes(), third = PageNotes()
        first.text = "Satz eins"
        third.text = "Satz drei, noch ein Satz"
        search.query = "satz"
        search.update(document: try document(3), pages: [0: first, 2: third])
        #expect(search.hits.count == 3)
        search.step(1); search.step(1); search.step(1); search.step(1)
        #expect(shown == [0, 2, 2, 0])
        search.step(-1)
        #expect(shown.last == 2)
    }

    @Test func theCurrentHitStaysWhileTheNotesChange() throws {
        let search = DocumentSearch()
        let pdf = try document(2)
        var notes = PageNotes()
        notes.text = "Begriff"
        search.query = "begriff"
        search.update(document: pdf, pages: [1: notes])
        search.show(0)
        notes.text = "Neuer Text vor dem Begriff"
        search.update(document: pdf, pages: [1: notes])
        // The hit moved within the text, so it is a different hit now.
        #expect(search.current == nil)
        search.query = ""
        search.update(document: pdf, pages: [1: notes])
        #expect(search.hits.isEmpty)
    }
}
