import AppKit
import Foundation
import PDFKit
import Testing
@testable import UniPDFCore

struct CommentTests {
    private func notes(comments: [(UUID, String)], text: (([UUID]) -> String)? = nil) -> PageNotes {
        var notes = PageNotes()
        notes.annotations = comments.map { id, body in
            SlideAnnotation(id: id, content: .comment(SlideComment(rects: [CGRect(x: 10, y: 10, width: 100, height: 14)],
                                                                   quote: "Satz von Bayes", text: body, color: .mint)))
        }
        notes.text = text?(comments.map(\.0)) ?? comments.map { CommentLinks.token(for: $0.0) }.joined(separator: " ")
        return notes
    }

    @Test func tokensAreFoundAndCommentsKeepTheirOrder() {
        let a = UUID(), b = UUID()
        let page = notes(comments: [(a, "erst"), (b, "dann")]) { ids in "Text \(CommentLinks.token(for: ids[1])) und \(CommentLinks.token(for: ids[0]))" }
        #expect(CommentLinks.tokens(in: page.text).map(\.id) == [b, a])
        #expect(CommentLinks.ordered(page).map(\.id) == [b, a])
        #expect(NotesMarkup.parse(page.text).comments.map(\.id) == [b, a])
        // Nothing inside a tag counts as formatting.
        #expect(NotesMarkup.parse(page.text).spans.isEmpty)
    }

    @Test func deletingEitherSideDeletesTheOther() {
        let a = UUID(), b = UUID()
        let before = notes(comments: [(a, ""), (b, "")]) { ids in "Anfang\n\(CommentLinks.token(for: ids[0]))\nMitte \(CommentLinks.token(for: ids[1])) Ende" }

        // The tag goes: the comment leaves the slide.
        var withoutTag = before
        withoutTag.text = "Anfang\n\nMitte \(CommentLinks.token(for: b)) Ende"
        #expect(CommentLinks.reconcile(withoutTag, previous: before).annotations.map(\.id) == [b])

        // The comment goes: its tag leaves the notes, a tag alone on its line with the line.
        var withoutComment = before
        withoutComment.annotations.removeAll { $0.id == a }
        #expect(CommentLinks.reconcile(withoutComment, previous: before).text == "Anfang\nMitte \(CommentLinks.token(for: b)) Ende")

        // Also at the very start, without an empty line left behind.
        let first = notes(comments: [(a, ""), (b, "")]) { ids in "\(CommentLinks.token(for: ids[0]))\n\(CommentLinks.token(for: ids[1]))" }
        var firstGone = first
        firstGone.annotations.removeAll { $0.id == a }
        #expect(CommentLinks.reconcile(firstGone, previous: first).text == CommentLinks.token(for: b))

        // Ordinary edits change nothing.
        var typed = before
        typed.text += " noch mehr"
        #expect(CommentLinks.reconcile(typed, previous: before) == typed)
    }

    @Test func aTagThatComesBackBringsItsComment() {
        let a = UUID(), b = UUID()
        let kept = CommentLinks.Removed()
        let before = notes(comments: [(a, "erst"), (b, "dann")]) { ids in "Eins \(CommentLinks.token(for: ids[0]))\nZwei \(CommentLinks.token(for: ids[1]))" }

        // ⌘X takes the tag and the comment; ⌘V elsewhere brings both back.
        var cut = before
        cut.text = "Eins \nZwei \(CommentLinks.token(for: b))"
        let afterCut = CommentLinks.reconcile(cut, previous: before, kept: kept)
        #expect(afterCut.annotations.map(\.id) == [b])
        var pasted = afterCut
        pasted.text += "\nDrei \(CommentLinks.token(for: a))"
        let afterPaste = CommentLinks.reconcile(pasted, previous: afterCut, kept: kept)
        #expect(afterPaste.annotations.map(\.id) == [b, a])
        guard case .comment(let comment) = afterPaste.annotations.last?.content else { Issue.record("No comment"); return }
        #expect(comment.text == "erst" && comment.color == .mint)

        // Deleted with its card, the comment returns with its tag when the notes undo the deletion.
        var deleted = before
        deleted.annotations.removeAll { $0.id == b }
        let afterDelete = CommentLinks.reconcile(deleted, previous: before, kept: kept)
        #expect(!afterDelete.text.contains(CommentLinks.token(for: b)))
        var undone = afterDelete
        undone.text = before.text
        #expect(CommentLinks.reconcile(undone, previous: afterDelete, kept: kept).annotations.map(\.id) == [a, b])

        // A tag nobody knows stays a tag without a comment.
        var unknown = before
        unknown.text += " " + CommentLinks.token(for: UUID())
        #expect(CommentLinks.reconcile(unknown, previous: before, kept: kept).annotations.count == 2)
    }

    @Test func commentsSurviveSavingAndAreSearchable() throws {
        let id = UUID()
        let page = notes(comments: [(id, "Prüfungsrelevant: **Formel** merken")])
        var project = StudyProject(title: "Test", pdfData: try Self.pdf(), pages: [0: page])
        project = try StudyProject.decode(project.encoded())
        #expect(project.pages[0] == page)
        let hits = TextSearch.hits(for: "prüfungsrelevant", pageTexts: [""], pages: [0: page])
        #expect(hits.map(\.source) == [.comment(id)])
    }

    @Test func labelsAreShortAndAreasSaySo() {
        #expect(SlideComment(rects: [], quote: "Kurz").label == "Kurz")
        #expect(SlideComment(rects: [], quote: "Ein ziemlich langer Satz über die Wahrscheinlichkeit").label == "Ein ziemlich langer Satz …")
        #expect(SlideComment(rects: [], isArea: true).label == "Area")
        #expect(CommentColor.lavender.next == .rose)
    }

    @Test func theStudyPDFNumbersCommentsAndListsThemAsFootnotes() throws {
        let a = UUID(), b = UUID()
        var page = notes(comments: [(a, "Gilt nur für **diskrete** Fälle"), (b, "")]) { ids in
            "Erst \(CommentLinks.token(for: ids[1])) dann \(CommentLinks.token(for: ids[0]))"
        }
        page.annotations[1].content = .comment(SlideComment(rects: [CGRect(x: 50, y: 50, width: 80, height: 60)], isArea: true))
        let project = StudyProject(title: "Test", pdfData: try Self.pdf(), pages: [0: page])
        let exported = try #require(PDFDocument(data: try PDFExporter.export(project)))
        // Tags keep their words together with non-breaking spaces.
        let text = try #require(exported.page(at: 0)?.string).replacingOccurrences(of: "\u{00A0}", with: " ")
        #expect(!text.contains("kommentar:"))
        #expect(text.contains("COMMENTS"))
        #expect(text.contains("Gilt nur für diskrete Fälle"))
        // Numbered in the order of the tags, the area first, and shortened to the tag's label as in the app.
        #expect(text.contains("1 · Area"))
        #expect(text.contains("2 · Satz von Bayes"))
        let footnotes = try #require(text.range(of: "COMMENTS"))
        let area = try #require(text.range(of: "1 · Area", range: footnotes.upperBound..<text.endIndex))
        let passage = try #require(text.range(of: "2 · Satz von Bayes", range: footnotes.upperBound..<text.endIndex))
        #expect(area.lowerBound < passage.lowerBound)
    }

    static func pdf() throws -> Data {
        let bytes = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        let consumer = try #require(CGDataConsumer(data: bytes))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        return bytes as Data
    }
}
