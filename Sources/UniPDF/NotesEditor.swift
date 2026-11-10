import AppKit
import SwiftUI
import UniPDFCore

/// Connects the formula palette and the format buttons with the notes editor of the current slide.
@Observable
final class NotesEditorController {
    weak var textView: NotesTextView?
    /// Whether the caret is inside a formula.
    var isInFormula = false

    func insert(_ insertion: FormulaInsertion) { textView?.insert(insertion) }
    func toggle(_ style: NotesMarkup.Style) { textView?.toggle(style) }
    func toggleList(numbered: Bool) { textView?.toggleList(numbered: numbered) }
}

/// The notes as plain text, formatted while writing as in chat apps: markers stay visible but faint,
/// formulas show set as long as the caret is not inside them.
struct NotesEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var accessibilityLabel: String
    let controller: NotesEditorController
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NotesTextView {
        let view = NotesTextView.make()
        view.delegate = context.coordinator
        view.controller = controller
        view.fontSize = fontSize
        view.accent = NSColor(Color.studyAccent(for: colorScheme))
        view.string = text
        view.setAccessibilityLabel(accessibilityLabel)
        view.restyle()
        controller.textView = view
        return view
    }

    func updateNSView(_ view: NotesTextView, context: Context) {
        context.coordinator.text = $text
        controller.textView = view
        view.controller = controller
        view.setAccessibilityLabel(accessibilityLabel)
        var changed = false
        if view.string != text, !view.hasMarkedText() { view.string = text; changed = true }
        if view.fontSize != fontSize { view.fontSize = fontSize; changed = true }
        let accent = NSColor(Color.studyAccent(for: colorScheme))
        if view.accent != accent { view.accent = accent; changed = true }
        if changed { view.restyle() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NotesTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        return CGSize(width: width, height: nsView.height(forWidth: width))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NotesTextView else { return }
            if text.wrappedValue != view.string { text.wrappedValue = view.string }
        }
    }
}

private extension NSAttributedString.Key {
    /// On a formula that shows set: its rendering. The layout hides its source.
    static let collapsedFormula = NSAttributedString.Key("UniPDFCollapsedFormula")
    /// On the dash or asterisk of a bullet: it shows as a dot. The text keeps the character as typed.
    static let bulletDot = NSAttributedString.Key("UniPDFBulletDot")
}

/// The set form of one formula. A class, so that two neighbouring formulas stay apart as attribute runs.
private final class FormulaRendering: NSObject {
    let line: CTLine
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let isBlock: Bool

    init(_ math: NSAttributedString, isBlock: Bool) {
        line = CTLineCreateWithAttributedString(math)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        // Superscripts lie above the font's ascent.
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        self.ascent = max(ascent, bounds.maxY)
        self.descent = max(descent, -bounds.minY)
        self.isBlock = isBlock
    }
}

final class NotesTextView: NSTextView, NSLayoutManagerDelegate {
    weak var controller: NotesEditorController?
    var fontSize: CGFloat = 15
    var accent: NSColor = .controlAccentColor
    private(set) var parsed = NotesMarkup.Parsed()
    /// The formulas showing as source, because the caret is inside them.
    private var expanded: [NSRange] = []
    /// Where set formulas were drawn, so that a click on one opens it.
    private var drawnFormulas: [(rect: NSRect, formula: NotesMarkup.Formula)] = []
    /// While a formula is being written: how it will look, shown beneath it.
    private var previews: [(formula: NotesMarkup.Formula, rendering: FormulaRendering)] = []
    private static let previewPadding: CGFloat = 6
    private static let minimumHeight: CGFloat = 260

    static func make() -> NotesTextView {
        // TextKit 1, whose layout manager can hide the source of a formula.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 5
        layout.addTextContainer(container)
        let view = NotesTextView(frame: NSRect(x: 0, y: 0, width: 400, height: minimumHeight), textContainer: container)
        layout.delegate = view
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainerInset = .zero
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.smartInsertDeleteEnabled = false
        return view
    }

    private var markupAppearance: NotesMarkup.Appearance {
        NotesMarkup.Appearance(size: fontSize, color: .textColor, secondaryColor: .secondaryLabelColor,
                               codeBackground: NSColor.textColor.withAlphaComponent(0.07), lineSpacing: 5)
    }

    // MARK: Styling

    func restyle() {
        guard let storage = textStorage, !hasMarkedText() else { return }
        parsed = NotesMarkup.parse(storage.string)
        let string = storage.string as NSString
        let selection = selectedRange()
        expanded = parsed.formulas.filter { isEditing($0, selection: selection) }.map(\.range)

        previews = []
        var textColor = NSColor.textColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            textColor = NSColor(cgColor: NSColor.textColor.cgColor) ?? .textColor
        }
        storage.beginEditing()
        NotesMarkup.style(storage, parsed: parsed, appearance: markupAppearance)
        let faint = NSColor.tertiaryLabelColor
        for marker in NotesMarkup.markers(in: parsed) { storage.addAttribute(.foregroundColor, value: faint, range: marker) }
        for line in parsed.lines where line.kind == .bullet || line.kind == .numbered {
            storage.addAttribute(.foregroundColor, value: accent, range: line.marker)
            if line.kind == .bullet {
                let marker = string.substring(with: line.marker) as NSString
                let dash = marker.rangeOfCharacter(from: CharacterSet(charactersIn: "-*"))
                if dash.location != NSNotFound {
                    storage.addAttribute(.bulletDot, value: true,
                                         range: NSRange(location: line.marker.location + dash.location, length: 1))
                }
            }
        }
        for formula in parsed.formulas {
            let source = string.substring(with: formula.source)
            let isEmpty = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            // A formula over several lines would break its hidden source apart; it stays as text.
            if expanded.contains(formula.range) || isEmpty || source.contains(where: \.isNewline) {
                storage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: fontSize * 0.92, weight: .regular),
                    .foregroundColor: accent,
                    .backgroundColor: accent.withAlphaComponent(0.08)
                ], range: formula.range)
                if !isEmpty {
                    // The finished formula, live beneath the line that is being written.
                    let math = MathNotation.formatted(NotesMarkup.oneLine(source), size: fontSize * (formula.isBlock ? 1.3 : 1.1),
                                                      color: textColor)
                    let rendering = FormulaRendering(math, isBlock: formula.isBlock)
                    previews.append((formula, rendering))
                    let end = NSRange(location: max(NSMaxRange(formula.range) - 1, 0), length: 0)
                    let paragraphRange = string.paragraphRange(for: end)
                    let paragraph = (storage.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil)
                                     as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    paragraph.paragraphSpacing = ceil(rendering.ascent + rendering.descent + 4 * Self.previewPadding)
                    storage.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
                }
                for dollar in [NSRange(location: formula.range.location, length: formula.source.location - formula.range.location),
                               NSRange(location: NSMaxRange(formula.source), length: NSMaxRange(formula.range) - NSMaxRange(formula.source))] {
                    storage.addAttribute(.foregroundColor, value: faint, range: dollar)
                }
            } else {
                let math = MathNotation.formatted(NotesMarkup.oneLine(source), size: fontSize * (formula.isBlock ? 1.3 : 1.1),
                                                  color: textColor)
                let rendering = FormulaRendering(math, isBlock: formula.isBlock)
                storage.addAttribute(.collapsedFormula, value: rendering, range: formula.range)
                if formula.isBlock {
                    let paragraph = (storage.attribute(.paragraphStyle, at: formula.range.location, effectiveRange: nil)
                                     as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                    paragraph.minimumLineHeight = ceil(rendering.ascent + rendering.descent + fontSize * 0.8)
                    // Centred by the layout, so that the caret beside it is where it looks.
                    paragraph.alignment = .center
                    storage.addAttribute(.paragraphStyle, value: paragraph,
                                         range: string.paragraphRange(for: NSRange(location: formula.range.location, length: 0)))
                }
            }
        }
        storage.endEditing()

        let base = NSMutableParagraphStyle()
        base.lineSpacing = 5
        typingAttributes = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.textColor, .paragraphStyle: base]
        controller?.isInFormula = NotesMarkup.formula(containing: selection.location, in: parsed) != nil
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private func isEditing(_ formula: NotesMarkup.Formula, selection: NSRange) -> Bool {
        let inside = NSRange(location: formula.range.location + 1, length: max(formula.range.length - 1, 0))
        return NSLocationInRange(selection.location, inside) && selection.location < NSMaxRange(formula.range)
            || (selection.length > 0 && NSIntersectionRange(selection, formula.range).length > 0)
    }

    override func didChangeText() {
        restyle()
        super.didChangeText()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        // Only when the caret enters or leaves a formula; typing restyles anyway.
        guard textStorage != nil, !hasMarkedText() else { return }
        let selection = selectedRange()
        let now = parsed.formulas.filter { isEditing($0, selection: selection) }.map(\.range)
        if now != expanded { restyle() }
        controller?.isInFormula = NotesMarkup.formula(containing: selection.location, in: parsed) != nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Set formulas carry their colour; light and dark need them set again.
        restyle()
    }

    override func becomeFirstResponder() -> Bool {
        controller?.textView = self
        return super.becomeFirstResponder()
    }

    // MARK: Layout of set formulas

    private func rendering(at index: Int, in layoutManager: NSLayoutManager) -> (FormulaRendering, NSRange)? {
        guard let storage = layoutManager.textStorage, index < storage.length else { return nil }
        var range = NSRange()
        guard let rendering = storage.attribute(.collapsedFormula, at: index, longestEffectiveRange: &range,
                                                in: NSRange(location: 0, length: storage.length)) as? FormulaRendering else { return nil }
        return (rendering, range)
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        var adjusted: [NSLayoutManager.GlyphProperty]?
        var replaced: [CGGlyph]?
        for offset in 0..<glyphRange.length {
            let index = characterIndexes[offset]
            if index < storage.length, storage.attribute(.bulletDot, at: index, effectiveRange: nil) != nil {
                var dot: CGGlyph = 0
                var character: UniChar = 0x2022
                if CTFontGetGlyphsForCharacters(font as CTFont, &character, &dot, 1) {
                    if replaced == nil { replaced = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length)) }
                    replaced?[offset] = dot
                }
                continue
            }
            guard index < storage.length, storage.attribute(.collapsedFormula, at: index, effectiveRange: nil) != nil,
                  let (_, range) = rendering(at: index, in: layoutManager) else { continue }
            if adjusted == nil { adjusted = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length)) }
            // The first character stands for the whole formula; the rest takes no room.
            adjusted?[offset] = index == range.location ? .controlCharacter : .null
        }
        guard adjusted != nil || replaced != nil else { return 0 }
        let properties = adjusted ?? Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        let glyphs = replaced ?? Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        layoutManager.setGlyphs(glyphs, properties: properties, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        rendering(at: charIndex, in: layoutManager) == nil ? action : .whitespace
    }

    func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer,
                       proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex: Int) -> NSRect {
        guard let (rendering, _) = rendering(at: characterIndex, in: layoutManager) else { return .zero }
        return NSRect(x: 0, y: -rendering.descent, width: ceil(rendering.width) + 2, height: rendering.ascent + rendering.descent)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let layoutManager, let storage = textStorage, let context = NSGraphicsContext.current?.cgContext else { return }
        drawnFormulas = []
        let origin = textContainerOrigin
        for formula in parsed.formulas where NSMaxRange(formula.range) <= storage.length {
            guard let (rendering, range) = self.rendering(at: formula.range.location, in: layoutManager),
                  range.location == formula.range.location else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let position = layoutManager.location(forGlyphAt: glyph)
            let x = origin.x + line.minX + position.x
            let baseline = origin.y + line.minY + position.y
            let rect = NSRect(x: x - 2, y: baseline - rendering.ascent - 2, width: rendering.width + 4,
                              height: rendering.ascent + rendering.descent + 4)
            drawnFormulas.append((rect, formula))
            guard rect.intersects(dirtyRect) else { continue }
            context.saveGState()
            // Upright, so that superscripts go up: the view itself is flipped.
            context.translateBy(x: x, y: baseline)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(rendering.line, context)
            context.restoreGState()
        }
        drawPreviews(in: context, layoutManager: layoutManager, length: storage.length)
    }

    /// Beneath the formula being written, in the room its paragraph spacing keeps free.
    private func drawPreviews(in context: CGContext, layoutManager: NSLayoutManager, length: Int) {
        let origin = textContainerOrigin
        for (formula, rendering) in previews where NSMaxRange(formula.range) <= length {
            let glyph = layoutManager.glyphIndexForCharacter(at: max(NSMaxRange(formula.range) - 1, 0))
            let line = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let start = layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: formula.range.location))
            let padding = Self.previewPadding
            let width = rendering.width + 2 * padding
            var x = origin.x + (formula.isBlock ? (bounds.width - width) / 2 : line.minX + start.x)
            x = min(max(x, origin.x), max(bounds.width - width, origin.x))
            let box = NSRect(x: x, y: origin.y + line.maxY + padding, width: width,
                             height: rendering.ascent + rendering.descent + 2 * padding)
            accent.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
            accent.withAlphaComponent(0.35).setStroke()
            let outline = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            outline.lineWidth = 1
            outline.stroke()
            context.saveGState()
            context.translateBy(x: box.minX + padding, y: box.minY + padding + rendering.ascent)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(rendering.line, context)
            context.restoreGState()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // A click on a set formula opens its source, with the caret before the closing dollar signs.
        if let hit = drawnFormulas.first(where: { $0.rect.contains(point) }) {
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: NSMaxRange(hit.formula.source), length: 0))
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for formula in drawnFormulas { addCursorRect(formula.rect, cursor: .pointingHand) }
    }

    // MARK: Size

    func height(forWidth width: CGFloat) -> CGFloat {
        guard let layoutManager, let textContainer else { return Self.minimumHeight }
        if abs(textContainer.size.width - width) > 0.5 {
            textContainer.size = NSSize(width: max(width, 50), height: .greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer).height + layoutManager.extraLineFragmentRect.height
        // A preview beneath the last line lies outside the used rect.
        let preview = previews.map { $0.rendering.ascent + $0.rendering.descent + 4 * Self.previewPadding }.max() ?? 0
        return max(ceil(used + preview) + 8, Self.minimumHeight)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height(forWidth: bounds.width > 0 ? bounds.width : 400))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { invalidateIntrinsicContentSize() }
    }

    // MARK: Writing

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": toggle(.bold); return true
        case "i": toggle(.italic); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    /// Return continues a list; on an empty item it ends the list.
    override func insertNewline(_ sender: Any?) {
        let string = self.string as NSString
        let selection = selectedRange()
        let lineRange = string.lineRange(for: NSRange(location: selection.location, length: 0))
        guard selection.length == 0,
              let line = parsed.lines.first(where: { $0.range.location == lineRange.location }),
              line.kind == .bullet || line.kind == .numbered,
              selection.location >= NSMaxRange(line.marker) else { return super.insertNewline(sender) }
        let marker = string.substring(with: line.marker)
        let rest = string.substring(with: NSRange(location: NSMaxRange(line.marker), length: NSMaxRange(line.range) - NSMaxRange(line.marker)))
        if rest.trimmingCharacters(in: .whitespaces).isEmpty {
            insertText("", replacementRange: line.marker)
            return
        }
        var next = marker
        if line.kind == .numbered, let digits = marker.firstRange(of: /\d+/), let number = Int(marker[digits]) {
            next.replaceSubrange(digits, with: String(number + 1))
        }
        insertText("\n" + next, replacementRange: selection)
    }

    func toggle(_ style: NotesMarkup.Style) {
        window?.makeFirstResponder(self)
        let marker = switch style { case .bold: "**"; case .italic: "_"; case .strike: "~~"; case .code: "`" }
        let string = self.string as NSString
        let selection = selectedRange()
        let length = (marker as NSString).length
        // Already marked: remove the markers around the selection.
        if selection.location >= length, NSMaxRange(selection) + length <= string.length,
           string.substring(with: NSRange(location: selection.location - length, length: length)) == marker,
           string.substring(with: NSRange(location: NSMaxRange(selection), length: length)) == marker {
            let outer = NSRange(location: selection.location - length, length: selection.length + 2 * length)
            insertText(string.substring(with: selection), replacementRange: outer)
            setSelectedRange(NSRange(location: outer.location, length: selection.length))
            return
        }
        let selected = string.substring(with: selection)
        insertText(marker + selected + marker, replacementRange: selection)
        setSelectedRange(NSRange(location: selection.location + length, length: selection.length))
    }

    func toggleList(numbered: Bool) {
        window?.makeFirstResponder(self)
        let string = self.string as NSString
        let lineRange = string.lineRange(for: selectedRange())
        var result: [String] = []
        var number = 1
        let lines = string.substring(with: lineRange).components(separatedBy: "\n")
        let existing = parsed.lines.filter { NSLocationInRange($0.range.location, lineRange) || $0.range.location == lineRange.location }
        let allListed = !existing.isEmpty && existing.allSatisfy { $0.kind == (numbered ? .numbered : .bullet) }
            && existing.count >= lines.filter { !$0.isEmpty }.count
        for (offset, line) in lines.enumerated() {
            let stripped = line.replacing(/^[ \t]*([-*•]|\d{1,3}[.)])[ \t]+/, with: "")
            if offset == lines.count - 1 && line.isEmpty && lines.count > 1 { result.append(line); continue }
            if allListed { result.append(stripped) }
            else { result.append((numbered ? "\(number). " : "- ") + stripped); number += 1 }
        }
        insertText(result.joined(separator: "\n"), replacementRange: lineRange)
    }

    func insert(_ insertion: FormulaInsertion) {
        window?.makeFirstResponder(self)
        if parsed.formulas.isEmpty && string.contains("$") { restyle() }
        let string = self.string as NSString
        var range = selectedRange()
        let inFormula = NotesMarkup.formula(containing: range.location, in: parsed) != nil
        var text: String
        switch insertion {
        case .symbol(let symbol):
            text = symbol + "‸"
        case .template(let notation):
            let selected = string.substring(with: range)
            let filled = notation.replacingOccurrences(of: "‸", with: selected + "‸")
            text = inFormula ? filled : "$" + filled + "$"
        case .superscript, .subscript:
            let mark = insertion == .superscript ? "^" : "_"
            if inFormula {
                text = mark + "{" + string.substring(with: range) + "‸}"
            } else {
                if range.length == 0 {
                    // The word before the caret becomes the base: x, then x² gives x^{…}.
                    var start = range.location
                    while start > 0, range.location - start < 24 {
                        let character = string.character(at: start - 1)
                        guard let scalar = UnicodeScalar(character),
                              !CharacterSet.whitespacesAndNewlines.contains(scalar), scalar != "$" else { break }
                        start -= 1
                    }
                    range = NSRange(location: start, length: range.location - start)
                }
                text = "$" + string.substring(with: range) + mark + "{‸}$"
            }
        case .block:
            let atLineStart = range.location == 0 || string.character(at: range.location - 1) == 10
            let end = NSMaxRange(range)
            let atLineEnd = end >= string.length || string.character(at: end) == 10
            let selected = string.substring(with: range)
            text = (atLineStart ? "" : "\n") + "$$ " + selected + "‸ $$" + (atLineEnd ? "" : "\n")
        }
        let caret = (text as NSString).range(of: "‸").location
        text = text.replacingOccurrences(of: "‸", with: "")
        insertText(text, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + caret, length: 0))
    }
}
