import AppKit
import SwiftUI
import UniPDFCore

/// Connects the formula palette and the format buttons with the notes editor of the current slide.
@Observable
final class NotesEditorController {
    /// The editor the formula palette writes into: the notes, or a comment card that has the focus.
    weak var textView: NotesTextView?
    /// The notes of the current slide themselves.
    weak var notesView: NotesTextView?
    /// Whether the caret is inside a formula.
    var isInFormula = false
    /// The comment whose card is open in the notes.
    var expandedComment: UUID?
    /// A card whose text should get the focus once it is open, such as a new comment's.
    var focusComment: UUID?
    /// Where the caret was put in the notes by hand, so that a new comment's tag lands there.
    var notesCaret: Int?

    func expand(_ id: UUID?, focus: Bool = false) {
        expandedComment = id
        focusComment = focus ? id : nil
    }

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
    var page = 0
    /// Matches of the document search, marked in the text.
    var searchQuery = ""
    var reveal: SearchReveal?
    var revealed: () -> Void = {}
    /// The slide's comments, for the tags and their cards. Only the notes have them, not a comment card.
    var comments: CommentContext?
    var minimumHeight: CGFloat = 260
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
        view.minimumHeight = minimumHeight
        view.comments = comments
        view.restyle()
        if comments != nil {
            controller.notesView = view
            controller.notesCaret = nil
            controller.textView = view
        } else if controller.textView == nil {
            controller.textView = view
        }
        return view
    }

    func updateNSView(_ view: NotesTextView, context: Context) {
        context.coordinator.text = $text
        if comments != nil {
            controller.notesView = view
            if controller.textView == nil { controller.textView = view }
        }
        view.controller = controller
        view.setAccessibilityLabel(accessibilityLabel)
        var changed = false
        if view.string != text, !view.hasMarkedText() { view.string = text; changed = true }
        if view.fontSize != fontSize { view.fontSize = fontSize; changed = true }
        let accent = NSColor(Color.studyAccent(for: colorScheme))
        if view.accent != accent { view.accent = accent; changed = true }
        if view.searchQuery != searchQuery { view.searchQuery = searchQuery; changed = true }
        if view.minimumHeight != minimumHeight { view.minimumHeight = minimumHeight; changed = true }
        if view.comments?.comments != comments?.comments || view.comments?.expanded != comments?.expanded { changed = true }
        view.comments = comments
        if changed { view.restyle() }
        view.layoutCard()
        if let reveal, reveal.page == page, reveal.source == .notes, view.lastReveal != reveal.token {
            view.lastReveal = reveal.token
            let revealed = revealed
            // After SwiftUI has laid out the text, so that it can scroll to the hit.
            DispatchQueue.main.async {
                view.reveal(reveal.range)
                revealed()
            }
        }
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
    static let listIndentation = NSAttributedString.Key("UniPDFListIndentation")
}

/// What the notes show in place of hidden source: a set formula or a comment's tag.
/// A class, so that two neighbours stay apart as attribute runs.
private class InlineRendering: NSObject {
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let isBlock: Bool

    init(width: CGFloat, ascent: CGFloat, descent: CGFloat, isBlock: Bool) {
        self.width = width; self.ascent = ascent; self.descent = descent; self.isBlock = isBlock
    }

    /// Draws with the baseline at `y`, in the text view's flipped coordinates.
    func draw(in context: CGContext, x: CGFloat, baseline y: CGFloat) {}
}

private final class FormulaRendering: InlineRendering {
    let line: CTLine

    init(_ math: NSAttributedString, isBlock: Bool) {
        line = CTLineCreateWithAttributedString(math)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        // Superscripts lie above the font's ascent.
        let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        super.init(width: width, ascent: max(ascent, bounds.maxY), descent: max(descent, -bounds.minY), isBlock: isBlock)
    }

    override func draw(in context: CGContext, x: CGFloat, baseline y: CGFloat) {
        context.saveGState()
        // Upright, so that superscripts go up: the view itself is flipped.
        context.translateBy(x: x, y: y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

/// A comment's tag: its colour's pastel behind, the passage in the darker shade, rounded, without a border.
private final class TagRendering: InlineRendering {
    let id: UUID
    let line: CTLine
    let icon: NSImage?
    let chevron: NSImage?
    let fill: NSColor
    let ink: NSColor
    let textWidth: CGFloat
    let iconSize: CGFloat
    static let margin: CGFloat = 2
    static let padding: CGFloat = 7

    init(id: UUID, label: String, color: CommentColor?, size: CGFloat, dark: Bool, expanded: Bool) {
        self.id = id
        let strong = color?.strong.nsColor ?? .secondaryLabelColor
        let pastel = color?.pastel.nsColor ?? NSColor.secondaryLabelColor.withAlphaComponent(0.15)
        fill = color == nil ? pastel : dark ? strong.withAlphaComponent(0.32) : pastel
        ink = color == nil ? .secondaryLabelColor : dark ? pastel : strong
        let font = NSFont.systemFont(ofSize: size * 0.82, weight: .semibold)
        line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: ink]))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        textWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        iconSize = size * 0.78
        let configuration = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
            .applying(.init(paletteColors: [ink]))
        icon = NSImage(systemSymbolName: color == nil ? "exclamationmark.bubble" : "text.bubble.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        chevron = NSImage(systemSymbolName: expanded ? "chevron.up" : "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .bold).applying(.init(paletteColors: [ink])))
        let vertical: CGFloat = 3
        let chevronWidth = (chevron?.size.width ?? 0) + 5
        super.init(width: Self.margin * 2 + Self.padding * 2 + iconSize + 4 + textWidth + chevronWidth,
                   ascent: ascent + vertical, descent: descent + vertical, isBlock: false)
    }

    /// The tag itself, without the margin around it.
    func chip(x: CGFloat, baseline y: CGFloat) -> NSRect {
        NSRect(x: x + Self.margin, y: y - ascent, width: width - 2 * Self.margin, height: ascent + descent)
    }

    override func draw(in context: CGContext, x: CGFloat, baseline y: CGFloat) {
        let rect = chip(x: x, baseline: y)
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        var cursor = rect.minX + Self.padding
        if let icon {
            let height = icon.size.height * iconSize / max(icon.size.width, 1)
            icon.draw(in: NSRect(x: cursor, y: rect.midY - height / 2, width: iconSize, height: height))
        }
        cursor += iconSize + 4
        context.saveGState()
        context.translateBy(x: cursor, y: y)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
        if let chevron {
            cursor += textWidth + 5
            chevron.draw(in: NSRect(x: cursor, y: rect.midY - chevron.size.height / 2, width: chevron.size.width, height: chevron.size.height))
        }
    }
}

/// What a slide's comments need in the notes: the comments, the open card, and what the card can do.
struct CommentContext {
    var comments: [UUID: SlideComment]
    var expanded: UUID?
    var update: (UUID, SlideComment) -> Void
    var delete: (UUID) -> Void
    var jump: (UUID) -> Void
    var toggle: (UUID) -> Void
}

/// The card in the notes keeps the normal pointer, apart from the text field inside it.
final class CardHostingView: NSHostingView<CommentCard> {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

final class NotesTextView: NSTextView, NSLayoutManagerDelegate {
    weak var controller: NotesEditorController?
    var fontSize: CGFloat = 15
    var accent: NSColor = .controlAccentColor
    var searchQuery = ""
    var lastReveal: UUID?
    private(set) var parsed = NotesMarkup.Parsed()
    /// The formulas showing as source, because the caret is inside them.
    private var expanded: [NSRange] = []
    /// Where set formulas were drawn, so that a click on one opens it.
    private var drawnFormulas: [(rect: NSRect, formula: NotesMarkup.Formula)] = []
    /// While a formula is being written: how it will look, shown beneath it.
    private var previews: [(formula: NotesMarkup.Formula, rendering: FormulaRendering)] = []
    private static let previewPadding: CGFloat = 6
    var minimumHeight: CGFloat = 260
    var comments: CommentContext?
    /// Where tags were drawn, so that a click on one opens its card.
    /// Where the tags are, from the layout, for clicks and the pointer.
    var tagRects: [(rect: NSRect, id: UUID)] {
        guard let layoutManager, let textContainer else { return [] }
        layoutManager.ensureLayout(for: textContainer)
        return tagPlacements(layoutManager).map { ($0.rendering.chip(x: $0.x, baseline: $0.baseline), $0.id) }
    }

    private func tagPlacements(_ layoutManager: NSLayoutManager) -> [(id: UUID, rendering: TagRendering, x: CGFloat, baseline: CGFloat)] {
        let length = (string as NSString).length
        let origin = textContainerOrigin
        return parsed.comments.compactMap { tag in
            guard NSMaxRange(tag.range) <= length, let (rendering, range) = self.rendering(at: tag.range.location, in: layoutManager),
                  range.location == tag.range.location, let tagRendering = rendering as? TagRendering else { return nil }
            let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let position = layoutManager.location(forGlyphAt: glyph)
            return (tag.id, tagRendering, origin.x + line.minX + position.x, origin.y + line.minY + position.y)
        }
    }
    private var card: (id: UUID, view: CardHostingView)?
    private var cardHeight: CGFloat = 140
    private var layingOutCard = false
    /// Between a change of the text and its new styling, the parsed tags are out of date.
    private var pendingEdit = false
    private var expandingTag = false

    /// Opens, moves and sizes the card of the expanded comment beneath its tag's line.
    func layoutCard() {
        guard !layingOutCard else { return }
        layingOutCard = true
        defer { layingOutCard = false }
        let length = (string as NSString).length
        guard let comments, let id = comments.expanded, let tag = parsed.comments.first(where: { $0.id == id }),
              let comment = comments.comments[id], NSMaxRange(tag.range) <= length,
              let layoutManager, let textContainer else {
            card?.view.removeFromSuperview()
            card = nil
            return
        }
        let root = CommentCard(
            comment: comment, fontSize: max(fontSize - 1, 11), controller: controller,
            setText: { text in var changed = comment; changed.text = text; comments.update(id, changed) },
            setColor: { color in var changed = comment; changed.color = color; comments.update(id, changed) },
            jump: { comments.jump(id) }, delete: { comments.delete(id) }, collapse: { comments.toggle(id) })
        let hosting: CardHostingView
        var isNew = false
        if let card, card.id == id {
            hosting = card.view
            hosting.rootView = root
        } else {
            card?.view.removeFromSuperview()
            hosting = CardHostingView(rootView: root)
            addSubview(hosting)
            card = (id, hosting)
            isNew = true
        }
        let inset = textContainer.lineFragmentPadding
        let width = max(bounds.width - 2 * (textContainerOrigin.x + inset), 160)
        // The card's height at this width; its text grows it.
        let height = ceil(NSHostingController(rootView: root).sizeThatFits(in: NSSize(width: width, height: 10_000)).height)
        if abs(height - cardHeight) > 0.5 {
            cardHeight = height
            layingOutCard = false
            restyle()
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let paragraph = (string as NSString).paragraphRange(for: NSRange(location: tag.range.location, length: 0))
        let last = max(min(NSMaxRange(paragraph) - 1, length - 1), tag.range.location)
        let line = layoutManager.lineFragmentUsedRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: last), effectiveRange: nil)
        hosting.frame = NSRect(x: textContainerOrigin.x + inset, y: textContainerOrigin.y + line.maxY + 9, width: width, height: height)
        window?.invalidateCursorRects(for: self)
        window?.invalidateCursorRects(for: hosting)
        invalidateIntrinsicContentSize()
        if isNew { DispatchQueue.main.async { [weak self] in self?.scrollToVisible(hosting.frame.insetBy(dx: 0, dy: -12)) } }
        if controller?.focusComment == id {
            controller?.focusComment = nil
            focusCard(hosting, attempts: 20)
        }
    }

    /// The open card belongs to the notes for VoiceOver too.
    override func accessibilityChildren() -> [Any]? {
        var children = super.accessibilityChildren() ?? []
        if let card { children.append(card.view) }
        return children
    }

    /// SwiftUI builds the card's text view a moment later; until then the focus waits.
    private func focusCard(_ hosting: NSView, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, hosting.superview === self else { return }
            if let editor = Self.firstNotesView(in: hosting), let window = editor.window {
                window.makeFirstResponder(editor)
            } else if attempts > 0 {
                self.focusCard(hosting, attempts: attempts - 1)
            }
        }
    }

    private static func firstNotesView(in view: NSView) -> NotesTextView? {
        for subview in view.subviews {
            if let found = subview as? NotesTextView ?? firstNotesView(in: subview) { return found }
        }
        return nil
    }

    /// A tag is one piece: an edit that touches part of it takes all of it.
    override func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool {
        if !expandingTag {
            let touched = parsed.comments.filter {
                let overlap = NSIntersectionRange($0.range, range).length
                return overlap > 0 && overlap < $0.range.length
            }
            if !touched.isEmpty {
                let whole = touched.reduce(range) { NSUnionRange($0, $1.range) }
                expandingTag = true
                insertText(replacementString ?? "", replacementRange: whole)
                expandingTag = false
                return false
            }
        }
        let allowed = super.shouldChangeText(in: range, replacementString: replacementString)
        if allowed { pendingEdit = true }
        return allowed
    }

    static func make() -> NotesTextView {
        // TextKit 1, whose layout manager can hide the source of a formula.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 5
        layout.addTextContainer(container)
        let view = NotesTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 260), textContainer: container)
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
        view.isContinuousSpellCheckingEnabled = true
        view.isAutomaticSpellingCorrectionEnabled = true
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
            let prefix = string.substring(with: line.marker).prefix { $0 == " " || $0 == "\t" }
            if !prefix.isEmpty {
                storage.addAttribute(.listIndentation, value: true,
                                     range: NSRange(location: line.marker.location, length: prefix.utf16.count))
            }
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
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for tag in parsed.comments {
            let comment = comments?.comments[tag.id]
            let expanded = comments?.expanded == tag.id && comment != nil
            let rendering = TagRendering(id: tag.id, label: comment?.label ?? String(localized: "Comment missing"), color: comment?.color,
                                         size: fontSize, dark: dark, expanded: expanded)
            storage.addAttribute(.collapsedFormula, value: rendering, range: tag.range)
            if expanded {
                // Room beneath the tag's line for its card.
                let paragraphRange = string.paragraphRange(for: NSRange(location: tag.range.location, length: 0))
                let paragraph = (storage.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil)
                                 as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                paragraph.paragraphSpacing = cardHeight + 18
                storage.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)
            }
        }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            for hit in TextSearch.hits(for: query, pageTexts: [""], pages: [0: { var notes = PageNotes(); notes.text = storage.string; return notes }()]) {
                storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.35), range: hit.range)
            }
        }
        storage.endEditing()

        let base = NSMutableParagraphStyle()
        base.lineSpacing = 5
        typingAttributes = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.textColor, .paragraphStyle: base]
        controller?.isInFormula = NotesMarkup.formula(containing: selection.location, in: parsed) != nil
        invalidateIntrinsicContentSize()
        needsDisplay = true
        layoutCard()
        window?.invalidateCursorRects(for: self)
    }

    private func isEditing(_ formula: NotesMarkup.Formula, selection: NSRange) -> Bool {
        let inside = NSRange(location: formula.range.location + 1, length: max(formula.range.length - 1, 0))
        return NSLocationInRange(selection.location, inside) && selection.location < NSMaxRange(formula.range)
            || (selection.length > 0 && NSIntersectionRange(selection, formula.range).length > 0)
    }

    override func didChangeText() {
        pendingEdit = false
        restyle()
        super.didChangeText()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        // The caret steps over a tag, and a selection takes it whole.
        var ranges = ranges
        if !pendingEdit, !parsed.comments.isEmpty {
            let previous = selectedRange().location
            ranges = ranges.map { value in
                var range = value.rangeValue
                for tag in parsed.comments {
                    let start = tag.range.location, end = NSMaxRange(tag.range)
                    if range.length == 0, range.location > start, range.location < end {
                        range.location = previous <= start ? end : start
                    } else if range.length > 0, NSIntersectionRange(range, tag.range).length > 0 {
                        range = NSUnionRange(range, tag.range)
                    }
                }
                return NSValue(range: range)
            }
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if comments != nil, window?.firstResponder === self, !pendingEdit { controller?.notesCaret = selectedRange().location }
        // Only when the caret enters or leaves a formula; typing restyles anyway.
        guard textStorage != nil, !hasMarkedText() else { return }
        let selection = selectedRange()
        let now = parsed.formulas.filter { isEditing($0, selection: selection) }.map(\.range)
        if now != expanded { restyle() }
        controller?.isInFormula = NotesMarkup.formula(containing: selection.location, in: parsed) != nil
    }

    /// Shows a search hit: selected, scrolled into view and briefly pulsing, without taking the focus from the search field.
    func reveal(_ range: NSRange) {
        guard NSMaxRange(range) <= (string as NSString).length else { return }
        setSelectedRange(range)
        scrollRangeToVisible(range)
        if let layoutManager, let textContainer {
            let rect = layoutManager.boundingRect(forGlyphRange: layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil),
                                                  in: textContainer).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            scrollToVisible(rect.insetBy(dx: 0, dy: -40))
        }
        showFindIndicator(for: range)
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

    private func rendering(at index: Int, in layoutManager: NSLayoutManager) -> (InlineRendering, NSRange)? {
        guard let storage = layoutManager.textStorage, index < storage.length else { return nil }
        var range = NSRange()
        guard let rendering = storage.attribute(.collapsedFormula, at: index, longestEffectiveRange: &range,
                                                in: NSRange(location: 0, length: storage.length)) as? InlineRendering else { return nil }
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
            if index < storage.length, storage.attribute(.listIndentation, at: index, effectiveRange: nil) != nil {
                if adjusted == nil { adjusted = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length)) }
                adjusted?[offset] = .controlCharacter
                continue
            }
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
        if let storage = layoutManager.textStorage, charIndex < storage.length,
           storage.attribute(.listIndentation, at: charIndex, effectiveRange: nil) != nil { return .whitespace }
        return rendering(at: charIndex, in: layoutManager) == nil ? action : .whitespace
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
            rendering.draw(in: context, x: x, baseline: baseline)
        }
        for placement in tagPlacements(layoutManager) {
            placement.rendering.draw(in: context, x: placement.x, baseline: placement.baseline)
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

    /// A click on a tag opens or closes its card.
    @discardableResult
    func toggleTag(at point: NSPoint) -> Bool {
        guard let hit = tagRects.first(where: { $0.rect.contains(point) }) else { return false }
        comments?.toggle(hit.id)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if toggleTag(at: point) { return }
        // A click on a set formula opens its source, with the caret before the closing dollar signs.
        if let hit = drawnFormulas.first(where: { $0.rect.contains(point) }) {
            window?.makeFirstResponder(self)
            setSelectedRange(NSRange(location: NSMaxRange(hit.formula.source), length: 0))
            return
        }
        super.mouseDown(with: event)
    }

    /// The text cursor only where there is text: not beside or below it, not over tags, set formulas or a card.
    var textCursorRects: [NSRect] {
        guard let layoutManager, let textContainer else { return [] }
        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin
        var lines: [NSRect] = []
        if (string as NSString).length == 0 {
            // An empty field still takes a click on its first line.
            let height = AnnotationRenderer.textHeight("", style: SlideTextStyle(size: Double(fontSize)), width: 100)
            lines.append(NSRect(x: origin.x, y: origin.y, width: bounds.width - 2 * origin.x, height: height))
        } else {
            layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: textContainer)) { _, used, _, _, _ in
                if used.width > 0 { lines.append(used.offsetBy(dx: origin.x, dy: origin.y)) }
            }
        }
        let excluded = tagRects.map(\.rect) + drawnFormulas.map(\.rect) + (card.map { [$0.view.frame] } ?? [])
        return lines.flatMap { line in
            // What lies on the line comes out of it, leaving the pieces of text beside it.
            excluded.filter { $0.intersects(line) }.sorted { $0.minX < $1.minX }.reduce(into: [line]) { pieces, cut in
                guard let last = pieces.popLast() else { return }
                if cut.minX > last.minX { pieces.append(NSRect(x: last.minX, y: last.minY, width: cut.minX - last.minX, height: last.height)) }
                if cut.maxX < last.maxX { pieces.append(NSRect(x: cut.maxX, y: last.minY, width: last.maxX - cut.maxX, height: last.height)) }
            }
        }.filter { $0.width > 0.5 }
    }

    override func resetCursorRects() {
        // Not the text view's own rect over all of it: elsewhere the normal pointer stays.
        for rect in textCursorRects { addCursorRect(rect, cursor: .iBeam) }
    }

    /// The text view also sets its cursor while the mouse moves; this keeps it to the text.
    private func updateCursor(at point: NSPoint) {
        (textCursorRects.contains { $0.contains(point) } ? NSCursor.iBeam : NSCursor.arrow).set()
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        // Over the card, its own views decide.
        if let card, card.view.frame.contains(point) { return }
        updateCursor(at: point)
    }

    // MARK: Size

    func height(forWidth width: CGFloat) -> CGFloat {
        guard let layoutManager, let textContainer else { return minimumHeight }
        if abs(textContainer.size.width - width) > 0.5 {
            textContainer.size = NSSize(width: max(width, 50), height: .greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        var used = layoutManager.usedRect(for: textContainer).height + layoutManager.extraLineFragmentRect.height
        // A card under the last line lies below the used rect.
        if let card { used = max(used, card.view.frame.maxY - textContainerOrigin.y + 8) }
        // A preview beneath the last line lies outside the used rect.
        let preview = previews.map { $0.rendering.ascent + $0.rendering.descent + 4 * Self.previewPadding }.max() ?? 0
        return max(ceil(used + preview) + 8, minimumHeight)
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

    override func checkText(in range: NSRange, types: NSTextCheckingTypes,
                            options: [NSSpellChecker.OptionKey: Any] = [:]) {
        let source = string as NSString
        guard range.location != NSNotFound, range.location <= source.length else { return }
        let requested = NSIntersectionRange(range, NSRange(location: 0, length: source.length))
        var position = requested.location
        while position < NSMaxRange(requested) {
            let paragraph = source.paragraphRange(for: NSRange(location: position, length: 0))
            var options = options
            options[.orthography] = NotesSpellChecking.orthography(for: source.substring(with: paragraph))
            // Supply our per-paragraph language instead of the system's preferred-language subset.
            super.checkText(in: NSIntersectionRange(paragraph, requested),
                            types: types & ~NSTextCheckingResult.CheckingType.orthography.rawValue, options: options)
            position = NSMaxRange(paragraph)
        }
    }

    override func handleTextCheckingResults(_ results: [NSTextCheckingResult], forRange range: NSRange,
                                            types: NSTextCheckingTypes, options: [NSSpellChecker.OptionKey: Any],
                                            orthography: NSOrthography, wordCount: Int) {
        super.handleTextCheckingResults(NotesSpellChecking.proseResults(results, in: string), forRange: range,
                                        types: types, options: options, orthography: orthography, wordCount: wordCount)
    }

    override func insertTab(_ sender: Any?) {
        if !changeListIndent(outdent: false) { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        if !changeListIndent(outdent: true) { super.insertBacktab(sender) }
    }

    /// Change the leading whitespace as one native edit, keeping selection offsets in UTF-16.
    @discardableResult
    private func changeListIndent(outdent: Bool) -> Bool {
        guard !hasMarkedText() else { return false }
        let source = string as NSString
        let selection = selectedRange()
        let touched = source.lineRange(for: NSRange(location: selection.location, length: max(selection.length - 1, 0)))
        let lines = parsed.lines.filter {
            ($0.kind == .bullet || $0.kind == .numbered) && NSLocationInRange($0.range.location, touched)
        }
        guard !lines.isEmpty else { return false }
        var edits: [(range: NSRange, replacement: String)] = []
        for line in lines {
            let marker = source.substring(with: line.marker)
            let removed = marker.first == "\t" ? 1 : marker.prefix(2).prefix { $0 == " " }.count
            if !outdent || removed > 0 {
                edits.append((NSRange(location: line.range.location, length: outdent ? removed : 0), outdent ? "" : "  "))
            }
        }
        guard !edits.isEmpty else { return true }
        func adjusted(_ location: Int) -> Int {
            var delta = 0
            for edit in edits {
                let added = edit.replacement.utf16.count
                if location >= NSMaxRange(edit.range) { delta += added - edit.range.length }
                else if location > edit.range.location { return edit.range.location + delta + min(location - edit.range.location, added) }
            }
            return location + delta
        }
        let replacement = NSMutableString(string: source.substring(with: touched))
        for edit in edits.reversed() {
            replacement.replaceCharacters(in: NSRange(location: edit.range.location - touched.location, length: edit.range.length),
                                           with: edit.replacement)
        }
        let start = adjusted(selection.location), end = adjusted(NSMaxRange(selection))
        insertText(replacement as String, replacementRange: touched)
        setSelectedRange(NSRange(location: start, length: end - start))
        return true
    }

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
            if line.indentationLevel > 0 { changeListIndent(outdent: true); return }
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

