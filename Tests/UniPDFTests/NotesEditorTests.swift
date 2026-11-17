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

    @Test func tabIndentsAndBacktabRestoresBulletWithUnicodeCaret() {
        let original = "- Erklärung 🧠\n- Zweiter"
        let caret = ("- Erklärung 🧠" as NSString).length
        let view = editor(original, caret: caret)
        view.insertTab(nil)
        #expect(view.string == "  - Erklärung 🧠\n- Zweiter")
        #expect(view.selectedRange() == NSRange(location: caret + 2, length: 0))
        #expect(view.parsed.lines.first?.indentationLevel == 1)
        view.insertBacktab(nil)
        #expect(view.string == original)
        #expect(view.selectedRange() == NSRange(location: caret, length: 0))
        view.insertBacktab(nil)
        #expect(view.string == original)
    }

    @Test func indentingASelectionLeavesTheFollowingLineAlone() {
        let view = editor("- Eins\n2. Zwei\n- Drei")
        let selected = ("- Eins\n2. Zwei\n" as NSString).length
        view.setSelectedRange(NSRange(location: 0, length: selected))
        view.insertTab(nil)
        #expect(view.string == "  - Eins\n  2. Zwei\n- Drei")
        #expect(view.parsed.lines.map(\.indentationLevel) == [1, 1, 0])
        view.insertBacktab(nil)
        #expect(view.string == "- Eins\n2. Zwei\n- Drei")
    }

    @Test func returnKeepsDepthAndEmptySubpointsOutdentBeforeEndingList() {
        let view = editor("    - Unterpunkt")
        view.insertNewline(nil)
        #expect(view.string == "    - Unterpunkt\n    - ")
        view.insertNewline(nil)
        #expect(view.string == "    - Unterpunkt\n  - ")
        view.insertNewline(nil)
        #expect(view.string == "    - Unterpunkt\n- ")
        view.insertNewline(nil)
        #expect(view.string == "    - Unterpunkt\n")
    }

    @Test func importedTabIndentationCanBeOutdented() {
        let view = editor("\t* Unterpunkt")
        #expect(view.parsed.lines.first?.indentationLevel == 1)
        view.insertBacktab(nil)
        #expect(view.string == "* Unterpunkt")
        let plain = editor("Normaler Text")
        plain.insertTab(nil)
        #expect(plain.string == "Normaler Text\t")
    }

    @Test func nestedBulletsMoveByOneVisibleIndentStep() throws {
        let view = editor("- Hauptpunkt\n  - Unterpunkt\n    - Detail")
        let layout = try #require(view.layoutManager)
        layout.ensureLayout(for: try #require(view.textContainer))
        let source = view.string as NSString
        func x(_ word: String) -> CGFloat {
            let glyph = layout.glyphIndexForCharacter(at: source.range(of: word).location)
            return layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: view.textContainer!).minX
        }
        let step = NotesMarkup.listIndent(for: view.fontSize)
        let offsets = [x("Hauptpunkt"), x("Unterpunkt"), x("Detail")]
        #expect(abs(offsets[1] - offsets[0] - step) < 1, "Visible list positions: \(offsets)")
        #expect(abs(offsets[2] - offsets[1] - step) < 1, "Visible list positions: \(offsets)")
    }

    @Test func indentationIsOneUndoableNativeEdit() throws {
        let view = editor("- Punkt")
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = view
        let undo = try #require(view.undoManager)
        undo.removeAllActions()
        undo.beginUndoGrouping()
        view.insertTab(nil)
        undo.endUndoGrouping()
        #expect(view.string == "  - Punkt")
        undo.undo()
        #expect(view.string == "- Punkt")
        undo.redo()
        #expect(view.string == "  - Punkt")
    }

    @Test func spellingIsEnabledWithoutChangingMarkupSubstitutionRules() {
        let view = editor("Notizen")
        #expect(view.isContinuousSpellCheckingEnabled)
        #expect(view.isAutomaticSpellingCorrectionEnabled)
        #expect(!view.isAutomaticDashSubstitutionEnabled)
        #expect(!view.isAutomaticQuoteSubstitutionEnabled)
    }

    @Test func bulletsShowADotButKeepTheDash() throws {
        let view = editor("- Punkt\n* Noch einer")
        let layoutManager = try #require(view.layoutManager)
        let font = NSFont.systemFont(ofSize: view.fontSize) as CTFont
        var dot: CGGlyph = 0, dash: CGGlyph = 0
        var bullet: UniChar = 0x2022, minus: UniChar = 0x2D
        CTFontGetGlyphsForCharacters(font, &bullet, &dot, 1)
        CTFontGetGlyphsForCharacters(font, &minus, &dash, 1)
        for index in [0, 8] {
            #expect(layoutManager.cgGlyph(at: layoutManager.glyphIndexForCharacter(at: index)) == dot)
        }
        #expect(view.string == "- Punkt\n* Noch einer")
        // A dash inside the text stays a dash.
        let plain = editor("a - b")
        #expect(try #require(plain.layoutManager).cgGlyph(at: 2) == dash)
    }

    @Test func commentTagsAreOnePieceForTheCaretAndForDeleting() {
        let id = UUID()
        let token = CommentLinks.token(for: id)
        let view = editor("Vor \(token) nach")
        let tag = NSRange(location: 4, length: (token as NSString).length)
        // The caret cannot stop inside.
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.setSelectedRange(NSRange(location: 10, length: 0))
        #expect(view.selectedRange().location == NSMaxRange(tag))
        // Backspace behind the tag removes all of it.
        view.deleteBackward(nil)
        #expect(view.string == "Vor  nach")
    }

    @Test func clickingATagTogglesItsCard() {
        let id = UUID()
        let view = editor("Text \(CommentLinks.token(for: id))")
        var toggled: [UUID] = []
        view.comments = CommentContext(comments: [id: SlideComment(rects: [CGRect(x: 0, y: 0, width: 10, height: 10)], quote: "Stelle")],
                                       expanded: nil, update: { _, _ in }, delete: { _ in }, jump: { _ in },
                                       toggle: { toggled.append($0) })
        view.restyle()
        view.display()
        let tagRect = view.tagRects.first?.rect ?? .zero
        #expect(tagRect.width > 20)
        #expect(view.toggleTag(at: NSPoint(x: tagRect.midX, y: tagRect.midY)))
        #expect(!view.toggleTag(at: NSPoint(x: tagRect.maxX + 40, y: tagRect.midY)))
        #expect(toggled == [id])
    }

    @Test func theTextCursorIsOnlyOverText() {
        let id = UUID()
        let view = editor("Vor \(CommentLinks.token(for: id)) nach")
        view.comments = CommentContext(comments: [id: SlideComment(rects: [CGRect(x: 0, y: 0, width: 10, height: 10)], quote: "Stelle")],
                                       expanded: nil, update: { _, _ in }, delete: { _ in }, jump: { _ in }, toggle: { _ in })
        view.restyle()
        let tag = try! #require(view.tagRects.first?.rect)
        let text = view.textCursorRects
        // The text before and after the tag, not the tag itself, nor the empty space below.
        #expect(text.count == 2)
        #expect(!text.contains { $0.intersects(tag.insetBy(dx: 1, dy: 1)) })
        #expect(!text.contains { $0.contains(NSPoint(x: 20, y: 200)) })
        // An empty field still offers its first line.
        #expect(editor("").textCursorRects.count == 1)
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
