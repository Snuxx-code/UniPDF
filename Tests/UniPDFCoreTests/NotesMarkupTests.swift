import AppKit
import Foundation
import PDFKit
import Testing
@testable import UniPDFCore

struct NotesMarkupTests {
    private func spans(_ text: String) -> [(NotesMarkup.Style, String)] {
        NotesMarkup.parse(text).spans.map { ($0.style, (text as NSString).substring(with: $0.content)) }
    }

    @Test func chatStyleMarkersBecomeStyles() {
        let found = spans("Das ist **wichtig**, *auch* _kursiv_ und ~weg~ mit `code`.")
        #expect(found.map(\.0) == [.bold, .bold, .italic, .strike, .code])
        #expect(found.map(\.1) == ["wichtig", "auch", "kursiv", "weg", "code"])
    }

    @Test func ordinaryTextIsLeftAlone() {
        // Snake case, lone asterisks, prices and arithmetic are not markers.
        #expect(spans("file_name_here, 3 * 4 * 5, a ~ b").isEmpty)
        #expect(NotesMarkup.parse("Kostet 5$ und 10$ im Monat").formulas.isEmpty)
    }

    @Test func linesBecomeHeadingsListsAndQuotes() {
        let parsed = NotesMarkup.parse("# Titel\n- Punkt\n* Noch einer\n  2. Zwei\n> Zitat\nText")
        #expect(parsed.lines.map(\.kind) == [.heading(1), .bullet, .bullet, .numbered, .quote])
        // "* Noch einer" is a bullet, not the start of bold text.
        #expect(parsed.spans.isEmpty)
    }

    @Test func formulasAreFoundInlineAndAsBlocks() {
        let text = "Es gilt $x^{2} \\in ℝ$ und\n$$ \\frac{a}{b} $$\nEnde **fett**"
        let parsed = NotesMarkup.parse(text)
        #expect(parsed.formulas.map(\.isBlock) == [false, true])
        #expect(parsed.formulas.map { (text as NSString).substring(with: $0.source) } == ["x^{2} \\in ℝ", " \\frac{a}{b} "])
        #expect(spans(text).map(\.1) == ["fett"])
        // Inside a formula, underscores and asterisks are notation.
        #expect(spans("$a_n * b_m$").isEmpty)
        #expect(NotesMarkup.formula(containing: 10, in: parsed)?.isBlock == false)
        #expect(NotesMarkup.formula(containing: 3, in: parsed) == nil)
    }

    @Test func exportHidesMarkersAndSetsFormulas() {
        let text = "# Titel\n**Fett** und _kursiv_\n- Punkt\n1. Eins\n$$ x^{2} \\cdot \\alpha $$"
        let rendered = NotesMarkup.rendered(text, appearance: .print(size: 12))
        #expect(rendered.string == "Titel\nFett und kursiv\n•\tPunkt\n1.\tEins\nx2 · α")
        let bold = rendered.attribute(.font, at: (rendered.string as NSString).range(of: "Fett").location, effectiveRange: nil) as? NSFont
        #expect(bold?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let italic = rendered.attribute(.font, at: (rendered.string as NSString).range(of: "kursiv").location, effectiveRange: nil) as? NSFont
        #expect(italic?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        let exponent = rendered.attribute(.baselineOffset, at: (rendered.string as NSString).range(of: "2").location, effectiveRange: nil) as? CGFloat
        #expect((exponent ?? 0) > 0)
    }

    @Test func paletteNotationRenders() {
        for (source, expected) in [("\\mathbb{R}", "ℝ"), ("\\{ x \\mid x \\in A \\}", "{ x ∣ x ∈ A }"),
                                   ("\\sqrt[3]{8}", "3√(8)"), ("\\|v\\|", "‖v‖"), ("\\lim_{x \\to 0}", "limx → 0")] {
            #expect(MathNotation.formatted(source).string == expected)
        }
    }

    @Test func formattedNotesAppearInTheStudyPDF() throws {
        let bytes = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        let consumer = try #require(CGDataConsumer(data: bytes))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        var notes = PageNotes()
        notes.text = "**MARKIERT** und $$ \\alpha + \\beta $$"
        let project = StudyProject(title: "Test", pdfData: bytes as Data, pages: [0: notes])
        let data = try PDFExporter.export(project)
        let exported = try #require(PDFDocument(data: data))
        let text = exported.string ?? ""
        #expect(text.contains("MARKIERT"))
        #expect(!text.contains("**"))
        #expect(text.contains("α + β"))
        // The project keeps the notes as written.
        let restored = try PDFProjectMetadata.decode(from: data)
        #expect(restored?.pages[0]?.text == notes.text)
    }
}
