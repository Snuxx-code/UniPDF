import AppKit
import Testing
@testable import UniPDF
@testable import UniPDFCore

@MainActor
struct NotesEditorTests {
    private func editor(_ text: String, caret: Int? = nil) -> NotesTextView {
        let view = NotesTextView.make()
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        view.string = text
        view.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        view.restyle()
        return view
    }

    private func isSet(_ view: NotesTextView, at location: Int) -> Bool {
        view.textStorage?.attribute(NSAttributedString.Key("UniPDFCollapsedFormula"), at: location, effectiveRange: nil) != nil
    }

    @Test func returnContinuesAndEndsLists() {
        let view = editor("- Erster")
        view.insertNewline(nil)
        #expect(view.string == "- Erster\n- ")
        view.insertNewline(nil)
        // An empty item ends the list.
        #expect(view.string == "- Erster\n")

        let numbered = editor("3. Drei")
        numbered.insertNewline(nil)
        #expect(numbered.string == "3. Drei\n4. ")
    }

    @Test func boldWrapsTheSelectionAndUnwrapsIt() {
        let view = editor("ganz wichtig")
        view.setSelectedRange(NSRange(location: 5, length: 7))
        view.toggle(.bold)
        #expect(view.string == "ganz **wichtig**")
        view.toggle(.bold)
        #expect(view.string == "ganz wichtig")
    }

    @Test func superscriptTurnsTheWordBeforeIntoAFormula() {
        let view = editor("Fläche x")
        view.insert(.superscript)
        view.insertText("2", replacementRange: view.selectedRange())
        #expect(view.string == "Fläche $x^{2}$")
        // Inside a formula it only adds the index, here after the exponent's brace.
        view.setSelectedRange(NSRange(location: (view.string as NSString).length - 1, length: 0))
        view.insert(.subscript)
        #expect(view.string == "Fläche $x^{2}_{}$")
    }

    @Test func symbolsAndBlocksGoWhereTheCaretIs() {
        let view = editor("A")
        view.insert(.block)
        #expect(view.string == "A\n$$  $$")
        view.insert(.symbol("∈"))
        #expect(view.string == "A\n$$ ∈ $$")
        view.insert(.template("\\frac{‸}{}"))
        #expect(view.string == "A\n$$ ∈\\frac{}{} $$")
    }

    @Test func formulasShowSetUnlessTheCaretIsInside() {
        let text = "Satz $x^{2}$ Ende"
        let view = editor(text)
        #expect(isSet(view, at: 5))
        view.setSelectedRange(NSRange(location: 7, length: 0))
        #expect(!isSet(view, at: 5))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(isSet(view, at: 5))
    }
}
