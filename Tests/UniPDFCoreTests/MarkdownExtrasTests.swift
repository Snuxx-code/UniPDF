import AppKit
import Foundation
import PDFKit
import Testing
@testable import UniPDFCore

/// Tasks, boxes, links, code blocks and rules, as GitHub writes them.
struct MarkdownExtrasTests {
    @Test func tasksAreBulletsWithABox() {
        let text = "- [ ] Übung 3\n  - [x] Skript lesen\n- [] kein Kasten"
        let parsed = NotesMarkup.parse(text)
        #expect(parsed.lines.map { $0.checkbox != nil } == [true, true, false])
        #expect(parsed.lines.map(\.isChecked) == [false, true, false])
        #expect(parsed.lines.map(\.indentationLevel) == [0, 1, 0])
        let rendered = NotesMarkup.rendered(text, appearance: .print(size: 12)).string
        #expect(rendered.hasPrefix("☐\tÜbung 3\n☑\tSkript lesen\n•\t"))
    }

    @Test func boxesTakeTheQuoteLinesBeneathThem() {
        let text = "> [!DEFINITION]\n> Ein Eigenwert $\\lambda$.\n> Zweite Zeile\nDanach\n> [!tip]\n> Merken\n> [!UNBEKANNT]\n> bleibt Zitat"
        let parsed = NotesMarkup.parse(text)
        #expect(parsed.callouts.map(\.kind) == [.definition, .remember])
        // One box right after another stays apart.
        #expect(NotesMarkup.parse("> [!NOTE]\n> a\n> [!WARNING]\n> b").callouts.map(\.kind) == [.definition, .caution])
        let string = text as NSString
        #expect(string.substring(with: parsed.callouts[0].range) == "> [!DEFINITION]\n> Ein Eigenwert $\\lambda$.\n> Zweite Zeile")
        // In the PDF: the name of the box, the text without its quote markers, and a fill.
        let rendered = NotesMarkup.rendered(text, appearance: .print(size: 12))
        #expect(rendered.string.hasPrefix("Definition\nEin Eigenwert "))
        let block = rendered.attribute(NotesMarkup.blockKey, at: (rendered.string as NSString).range(of: "Zweite").location, effectiveRange: nil)
        #expect((block as? NotesMarkup.Block)?.callout == .definition)
        // The text in a box is not set as a quote.
        let font = rendered.attribute(.font, at: (rendered.string as NSString).range(of: "Zweite").location, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == false)
    }

    @Test func linksKeepUnderscoresAndLead() {
        let text = "Siehe [Moodle](https://moodle.example.de/kurs_1) und www.example.de/a_b_c, nicht mail@www.x.de"
        let parsed = NotesMarkup.parse(text)
        #expect(parsed.links.map(\.url.absoluteString) == ["https://moodle.example.de/kurs_1", "https://www.example.de/a_b_c"])
        #expect(parsed.spans.isEmpty)
        let rendered = NotesMarkup.rendered(text, appearance: .print(size: 12))
        #expect(rendered.string.hasPrefix("Siehe Moodle und www.example.de/a_b_c"))
        let url = rendered.attribute(NotesMarkup.linkKey, at: 7, effectiveRange: nil) as? URL
        #expect(url?.host == "moodle.example.de")
    }

    @Test func codeBlocksAreNotFormatted() {
        let text = "Vorher\n```python\ndef f(x):\n    return x * 2 * $a$ # **kein fett**\n```\nNachher **fett**"
        let parsed = NotesMarkup.parse(text)
        #expect(parsed.codeBlocks.count == 1)
        #expect(parsed.codeBlocks.first?.language == "python")
        #expect(parsed.formulas.isEmpty)
        #expect(parsed.spans.count == 1)
        let rendered = NotesMarkup.rendered(text, appearance: .print(size: 12))
        #expect(rendered.string == "Vorher\ndef f(x):\n    return x * 2 * $a$ # **kein fett**\nNachher fett")
        // Without a closing fence the block runs to the end.
        #expect(NotesMarkup.parse("```\nfrei\n**offen**").spans.isEmpty)
    }

    @Test func rulesAreLinesOfTheirOwn() {
        let parsed = NotesMarkup.parse("Teil 1\n---\n***\n- - -\n--\nTeil 2")
        #expect(parsed.rules.count == 3)
        #expect(parsed.lines.isEmpty)
        let rendered = NotesMarkup.rendered("A\n---\nB", appearance: .print(size: 12))
        #expect(rendered.string == "A\n\u{200B}\nB")
        #expect(rendered.attribute(NotesMarkup.ruleKey, at: 2, effectiveRange: nil) != nil)
    }

    @Test func theStudyPDFHasTheBoxesAndTheLinks() throws {
        let pdf = try CommentTests.pdf()
        var notes = PageNotes()
        notes.text = "> [!PRÜFUNG]\n> Kommt dran.\n\n```\ncode\n```\n---\n[Skript](https://example.de/skript)\n- [x] erledigt"
        let project = StudyProject(title: "Test", pdfData: pdf, pages: [0: notes])
        let data = try PDFExporter.export(project)
        let document = try #require(PDFDocument(data: data))
        let text = document.page(at: 0)?.string ?? ""
        #expect(text.contains("Exam") || text.contains("Prüfung"))
        #expect(text.contains("Kommt dran."))
        #expect(!text.contains("[!"))
        #expect(!text.contains("```"))
        let links = document.page(at: 0)?.annotations.compactMap { $0.url } ?? []
        #expect(links.contains(URL(string: "https://example.de/skript")!))
    }
}
