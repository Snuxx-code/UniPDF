import Foundation
import Testing
@testable import UniPDFCore

struct TextSearchTests {
    private func notes(_ text: String, boxes: [String] = []) -> PageNotes {
        var notes = PageNotes()
        notes.text = text
        notes.annotations = boxes.map {
            SlideAnnotation(content: .text($0, frame: CGRect(x: 0, y: 0, width: 100, height: 20), style: SlideTextStyle(),
                                           color: AnnotationColor(red: 0, green: 0, blue: 0)))
        }
        return notes
    }

    @Test func findsSlidesNotesAndTextBoxesInReadingOrder() {
        let pages = [0: notes("Vektorraum in der Mitschrift", boxes: ["Merke: Vektor"]), 2: notes("Kein Treffer")]
        let hits = TextSearch.hits(for: "vektor", pageTexts: ["Folie über Vektoren", "", "Basis und VEKTOR"], pages: pages)
        #expect(hits.map(\.page) == [0, 0, 0, 2])
        #expect(hits.map(\.source) == [.slide, .textBox(pages[0]!.annotations[0].id), .notes, .slide])
        #expect(hits[0].match == "Vektor")
        #expect(hits[3].match == "VEKTOR")
    }

    @Test func ignoresCaseAndAccentsAndFindsEveryOccurrence() {
        let hits = TextSearch.hits(for: "uber", pageTexts: ["Über alles, über nichts, ÜBER"], pages: [:])
        #expect(hits.count == 3)
        #expect(hits.map(\.range.location) == [0, 12, 25])
    }

    @Test func snippetsAreShortSingleLinesAroundTheMatch() {
        let text = "Einleitung mit sehr vielen Wörtern davor\nund dann das Stichwort\nmitten im Text, gefolgt von noch mehr Wörtern bis zum Ende der langen Zeile hier"
        let hit = try! #require(TextSearch.hits(for: "Stichwort", pageTexts: [text], pages: [:]).first)
        #expect(hit.before.hasPrefix("…"))
        #expect(!hit.before.contains("\n") && !hit.after.contains("\n"))
        #expect(hit.after.hasSuffix("…"))
        #expect((hit.before + hit.match + hit.after).contains("das Stichwort mitten"))
    }

    @Test func emptyQueriesFindNothingAndManyHitsStop() {
        #expect(TextSearch.hits(for: "  ", pageTexts: ["abc"], pages: [:]).isEmpty)
        let hits = TextSearch.hits(for: "a", pageTexts: Array(repeating: String(repeating: "a", count: 100), count: 10), pages: [:])
        #expect(hits.count == TextSearch.limit)
    }
}
