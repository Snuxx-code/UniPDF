import AppKit
import Testing
import UniPDFCore
@testable import UniPDF

@Suite @MainActor struct NotesSpellCheckingTests {
    @Test func GermanAndEnglishParagraphsUseTheirRespectiveLanguages() {
        let german = NotesSpellChecking.orthography(for: "Diese Vorlesung erklärt die wichtigsten Zusammenhänge und beantwortet unsere Fragen.")
        let english = NotesSpellChecking.orthography(for: "This lecture explains the most important concepts and answers all our questions.")
        #expect(german.dominantLanguage == "de")
        #expect(english.dominantLanguage == "en")
        #expect(Set(german.allLanguages) == Set(["de", "en"]))
        #expect(Set(english.allLanguages) == Set(["de", "en"]))
    }

    @Test func nativeCorrectionsOnlyApplyToProse() {
        let token = CommentLinks.token(for: UUID())
        let text = "Vorlesugn **leccture** $\\alpah$ `coed` \(token)"
        let source = text as NSString
        let words = ["Vorlesugn", "leccture", "alpah", "coed", "kommentar"]
        let results = words.map { NSTextCheckingResult.correctionCheckingResult(range: source.range(of: $0), replacementString: "Korrektur") }
        let allowed = NotesSpellChecking.proseResults(results, in: text)
        #expect(allowed.map(\.range) == [source.range(of: "Vorlesugn"), source.range(of: "leccture")])
    }

    @Test func unfinishedMathAndCodeAreProtectedWhileTyping() {
        for text in ["Normal $\\alpah", "Normal `coed", "Normal\n$$\n\\alpah"] {
            let source = text as NSString
            let wrong = text.contains("coed") ? "coed" : "alpah"
            let result = NSTextCheckingResult.correctionCheckingResult(range: source.range(of: wrong), replacementString: "Korrektur")
            #expect(NotesSpellChecking.proseResults([result], in: text).isEmpty)
        }
        let text = "Kostet 5$ und helo"
        let result = NSTextCheckingResult.correctionCheckingResult(range: (text as NSString).range(of: "helo"), replacementString: "hello")
        #expect(NotesSpellChecking.proseResults([result], in: text).count == 1)
    }
}
