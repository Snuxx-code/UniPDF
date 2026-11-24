import AppKit

/// Light formatting for the notes, written as in chat apps and Markdown.
/// The notes stay plain text: `**fett**` or `*fett*`, `_kursiv_`, `~durchgestrichen~`, `` `Code` ``,
/// `# Überschrift`, `- Stichpunkt`, `1. Aufzählung`, `> Zitat`, and formulas as `$x^{2}$` or `$$ … $$` blocks.
/// Also as on GitHub: `- [ ] Aufgabe`, `> [!DEFINITION]` boxes, links, ``` code blocks and `---` rules.
public enum NotesMarkup {
    public enum Style: Sendable, Equatable { case bold, italic, strike, code }

    /// Text between markers, such as `**…**`. The markers are the rest of `range`.
    public struct Span: Sendable, Equatable {
        public var style: Style
        public var range: NSRange
        public var content: NSRange
    }

    public struct Formula: Sendable, Equatable {
        /// With the dollar signs.
        public var range: NSRange
        public var source: NSRange
        public var isBlock: Bool
    }

    public enum LineKind: Sendable, Equatable { case heading(Int), bullet, numbered, quote }

    public struct Line: Sendable, Equatable {
        public var kind: LineKind
        /// The whole line, without its line break.
        public var range: NSRange
        /// `## `, `- `, `1. ` or `> `, with the indent before it; for a task `- [ ] `.
        public var marker: NSRange
        public var indentationLevel = 0
        /// A task's box, `[ ]` or `[x]`.
        public var checkbox: NSRange?
        public var isChecked = false
    }

    /// The kinds of box that `> [!…]` opens. GitHub's names count too.
    public enum CalloutKind: String, Sendable, Equatable, CaseIterable {
        case definition, remember, example, exam, caution

        init?(marker: String) {
            switch marker.uppercased() {
            case "DEFINITION", "NOTE", "HINWEIS": self = .definition
            case "MERKE", "TIP", "TIPP", "REMEMBER": self = .remember
            case "BEISPIEL", "EXAMPLE": self = .example
            case "PRÜFUNG", "PRUEFUNG", "IMPORTANT", "WICHTIG", "EXAM": self = .exam
            case "ACHTUNG", "WARNING", "CAUTION", "VORSICHT": self = .caution
            default: return nil
            }
        }

        /// How the box is written: `> [!MERKE]`.
        public var marker: String {
            switch self {
            case .definition: "DEFINITION"
            case .remember: "MERKE"
            case .example: "BEISPIEL"
            case .exam: "PRÜFUNG"
            case .caution: "ACHTUNG"
            }
        }

        public var label: String {
            switch self {
            case .definition: String(localized: "Definition")
            case .remember: String(localized: "Remember")
            case .example: String(localized: "Example")
            case .exam: String(localized: "Exam")
            case .caution: String(localized: "Caution")
            }
        }

        /// The label's colour; the box takes a light tint of it.
        public var color: AnnotationColor {
            switch self {
            case .definition: AnnotationColor(red: 0.216, green: 0.541, blue: 0.867)
            case .remember: AnnotationColor(red: 0.114, green: 0.620, blue: 0.459)
            case .example: AnnotationColor(red: 0.498, green: 0.467, blue: 0.867)
            case .exam: AnnotationColor(red: 0.729, green: 0.459, blue: 0.090)
            case .caution: AnnotationColor(red: 0.886, green: 0.294, blue: 0.290)
            }
        }

        public var tintAlpha: CGFloat { self == .exam ? 0.16 : 0.13 }

        public var symbol: String {
            switch self {
            case .definition: "book.closed"
            case .remember: "lightbulb"
            case .example: "flask"
            case .exam: "graduationcap"
            case .caution: "exclamationmark.triangle"
            }
        }
    }

    /// `> [!DEFINITION]` and the quote lines beneath it.
    public struct Callout: Sendable, Equatable {
        public var kind: CalloutKind
        /// All its lines, without the last line break.
        public var range: NSRange
        /// The line `> [!DEFINITION]`.
        public var header: NSRange
    }

    /// Lines between ``` fences. Without a closing fence it runs to the end, as on GitHub.
    public struct CodeBlock: Sendable, Equatable {
        public var range: NSRange
        public var opening: NSRange
        public var closing: NSRange?
        public var language: String
    }

    /// `[Text](https://…)`, or an address written out.
    public struct Link: Sendable, Equatable {
        public var range: NSRange
        /// What shows: the text in brackets, or the address itself.
        public var text: NSRange
        public var url: URL
    }

    /// A comment's tag, `[[kommentar:…]]`, which the editor shows as a coloured tag.
    public struct CommentTag: Sendable, Equatable {
        public var range: NSRange
        public var id: UUID
    }

    public struct Parsed: Sendable, Equatable {
        public var comments: [CommentTag] = []
        public var formulas: [Formula] = []
        public var spans: [Span] = []
        public var lines: [Line] = []
        public var callouts: [Callout] = []
        public var codeBlocks: [CodeBlock] = []
        public var links: [Link] = []
        /// Lines that are only `---`, `***` or `___`.
        public var rules: [NSRange] = []
        public init() {}
    }

    // MARK: Parsing

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are constants; a typo shows up in the tests.
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    private static let blockFormula = regex(#"\$\$([\s\S]+?)\$\$"#)
    /// Not after a letter or digit and not before a digit, so that "5$ und 10$" stays text.
    private static let inlineFormula = regex(#"(?<![\$\\\w])\$(?=[^\s$])([^\n$]+?)(?<=[^\s$\\])\$(?![\$\d])"#)
    private static let code = regex(#"`([^`\n]+)`"#)
    private static let inlineStyles: [(Style, NSRegularExpression)] = [
        (.bold, regex(#"(?<![*\w])\*\*(?=[^\s*])([^\n]+?)(?<=[^\s*])\*\*(?![*\w])"#)),
        (.bold, regex(#"(?<![*\w])\*(?=[^\s*])([^\n*]+?)(?<=[^\s*])\*(?![*\w])"#)),
        (.italic, regex(#"(?<![_\w])_(?=[^\s_])([^\n_]+?)(?<=[^\s_])_(?![_\w])"#)),
        (.strike, regex(#"(?<![~\w])~~(?=[^\s~])([^\n~]+?)(?<=[^\s~])~~(?![~\w])"#)),
        (.strike, regex(#"(?<![~\w])~(?=[^\s~])([^\n~]+?)(?<=[^\s~])~(?![~\w])"#))
    ]
    private static let fence = regex(#"^[ \t]*```[ \t]*([\w+#.-]*)[ \t]*$"#)
    private static let rule = regex(#"^[ \t]{0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,})$"#)
    private static let task = regex(#"^[ \t]*[-*•][ \t]+(\[[ xX]\])(?:[ \t]+|$)"#)
    private static let calloutHeader = regex(#"^>[ \t]?\[!([A-Za-zÄÖÜäöü]+)\][ \t]*$"#)
    private static let markdownLink = regex(#"\[([^\]\n]+)\]\(((?:https?://|www\.)[^\s)]+)\)"#)
    private static let bareLink = regex(#"(?<![\w@/.\-\]\(])((?:https?://|www\.)[^\s<>()\[\]]*[^\s<>()\[\].,;:!?'"])"#)
    private static let lineKinds: [(NSRegularExpression, @Sendable (NSTextCheckingResult) -> LineKind)] = [
        (regex(#"^(#{1,3})[ \t]+(?=\S)"#), { .heading($0.range(at: 1).length) }),
        (regex(#"^[ \t]*[-*•][ \t]+"#), { _ in .bullet }),
        (regex(#"^[ \t]*\d{1,3}[.)][ \t]+"#), { _ in .numbered }),
        (regex(#"^>[ \t]?"#), { _ in .quote })
    ]

    public static func parse(_ text: String) -> Parsed {
        let string = text as NSString
        let all = NSRange(location: 0, length: string.length)
        var parsed = Parsed()
        var taken: [NSRange] = []
        func isFree(_ range: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, range).length > 0 } }

        for (range, id) in CommentLinks.tokens(in: text) {
            parsed.comments.append(CommentTag(range: range, id: id))
            taken.append(range)
        }
        // Nothing inside a code block is formatting.
        var lineRanges: [NSRange] = []
        string.enumerateSubstrings(in: all, options: [.byLines, .substringNotRequired]) { _, line, _, _ in lineRanges.append(line) }
        var index = 0
        while index < lineRanges.count {
            let line = lineRanges[index]
            guard let open = fence.firstMatch(in: text, range: line), isFree(line) else { index += 1; continue }
            let language = string.substring(with: open.range(at: 1))
            var closing: NSRange?
            var end = index + 1
            while end < lineRanges.count {
                let candidate = lineRanges[end]
                if let close = fence.firstMatch(in: text, range: candidate), close.range(at: 1).length == 0 { closing = candidate; break }
                end += 1
            }
            let last = closing ?? lineRanges[min(end, lineRanges.count) - 1]
            let range = NSRange(location: line.location, length: NSMaxRange(last) - line.location)
            parsed.codeBlocks.append(CodeBlock(range: range, opening: line, closing: closing, language: language))
            taken.append(range.length > 0 ? range : NSRange(location: range.location, length: 1))
            index = end + 1
        }
        for match in blockFormula.matches(in: text, range: all) where isFree(match.range) {
            parsed.formulas.append(Formula(range: match.range, source: match.range(at: 1), isBlock: true))
            taken.append(match.range)
        }
        for match in code.matches(in: text, range: all) where isFree(match.range) {
            parsed.spans.append(Span(style: .code, range: match.range, content: match.range(at: 1)))
            taken.append(match.range)
        }
        for match in inlineFormula.matches(in: text, range: all) where isFree(match.range) {
            parsed.formulas.append(Formula(range: match.range, source: match.range(at: 1), isBlock: false))
            taken.append(match.range)
        }
        parsed.formulas.sort { $0.range.location < $1.range.location }
        // Links before emphasis: an address often holds underscores.
        for match in markdownLink.matches(in: text, range: all) where isFree(match.range) {
            guard let url = linkURL(string.substring(with: match.range(at: 2))) else { continue }
            parsed.links.append(Link(range: match.range, text: match.range(at: 1), url: url))
            taken.append(match.range)
        }
        for match in bareLink.matches(in: text, range: all) where isFree(match.range) {
            guard let url = linkURL(string.substring(with: match.range)) else { continue }
            parsed.links.append(Link(range: match.range, text: match.range, url: url))
            taken.append(match.range)
        }
        parsed.links.sort { $0.range.location < $1.range.location }

        string.enumerateSubstrings(in: all, options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            guard isFree(NSRange(location: line.location, length: min(line.length, 1))) || line.length == 0 else { return }
            if line.length > 0, rule.firstMatch(in: text, range: line) != nil {
                parsed.rules.append(line)
                taken.append(line)
                return
            }
            if let match = task.firstMatch(in: text, range: line) {
                let prefix = string.substring(with: match.range).prefix { $0 == " " || $0 == "\t" }
                let columns = prefix.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
                let box = match.range(at: 1)
                parsed.lines.append(Line(kind: .bullet, range: line, marker: match.range, indentationLevel: (columns + 1) / 2,
                                         checkbox: box, isChecked: string.substring(with: box).lowercased() == "[x]"))
                return
            }
            for (pattern, kind) in lineKinds {
                guard let match = pattern.firstMatch(in: text, range: line), match.range.location == line.location else { continue }
                let prefix = string.substring(with: match.range).prefix { $0 == " " || $0 == "\t" }
                let columns = prefix.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
                parsed.lines.append(Line(kind: kind(match), range: line, marker: match.range, indentationLevel: (columns + 1) / 2))
                break
            }
        }
        // A box: `> [!DEFINITION]`, then every quote line right beneath it.
        var lineIndex = 0
        while lineIndex < parsed.lines.count {
            let line = parsed.lines[lineIndex]
            guard line.kind == .quote, let match = calloutHeader.firstMatch(in: text, range: line.range),
                  let kind = CalloutKind(marker: string.substring(with: match.range(at: 1))) else { lineIndex += 1; continue }
            var last = line.range
            var next = lineIndex + 1
            // Until the quote ends or the next box begins.
            while next < parsed.lines.count, parsed.lines[next].kind == .quote,
                  parsed.lines[next].range.location == NSMaxRange(string.lineRange(for: last)),
                  calloutHeader.firstMatch(in: text, range: parsed.lines[next].range) == nil {
                last = parsed.lines[next].range
                next += 1
            }
            parsed.callouts.append(Callout(kind: kind, range: NSRange(location: line.range.location, length: NSMaxRange(last) - line.range.location),
                                           header: line.range))
            lineIndex = next
        }
        // Markers at the start of a line are not emphasis: "* Punkt" is a bullet.
        let lineMarkers = parsed.lines.map(\.marker)
        for (style, pattern) in inlineStyles {
            for match in pattern.matches(in: text, range: all) where isFree(match.range) {
                guard !lineMarkers.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
                parsed.spans.append(Span(style: style, range: match.range, content: match.range(at: 1)))
                // Its markers are taken; the text between them can carry other styles, such as *_both_*.
                taken.append(NSRange(location: match.range.location, length: match.range(at: 1).location - match.range.location))
                taken.append(NSRange(location: NSMaxRange(match.range(at: 1)), length: NSMaxRange(match.range) - NSMaxRange(match.range(at: 1))))
            }
        }
        parsed.spans.sort { $0.range.location < $1.range.location }
        return parsed
    }

    static func linkURL(_ address: String) -> URL? {
        let full = address.lowercased().hasPrefix("www.") ? "https://" + address : address
        guard let url = URL(string: full), url.host != nil else { return nil }
        return url
    }

    /// The formula around `location`, if the caret is inside its dollar signs.
    public static func formula(containing location: Int, in parsed: Parsed) -> Formula? {
        parsed.formulas.first { $0.range.location < location && location < NSMaxRange($0.range) }
    }

    // MARK: Styling

    public struct Appearance {
        public var size: CGFloat
        public var color: NSColor
        public var secondaryColor: NSColor
        public var codeBackground: NSColor
        public var lineSpacing: CGFloat
        /// Links and the boxes of tasks.
        public var accent: NSColor

        public init(size: CGFloat, color: NSColor, secondaryColor: NSColor, codeBackground: NSColor, lineSpacing: CGFloat,
                    accent: NSColor = NotesMarkup.printAccent) {
            self.size = size; self.color = color; self.secondaryColor = secondaryColor
            self.codeBackground = codeBackground; self.lineSpacing = lineSpacing; self.accent = accent
        }

        public static func print(size: CGFloat) -> Appearance {
            Appearance(size: size, color: .black, secondaryColor: .darkGray,
                       codeBackground: NSColor(white: 0.93, alpha: 1), lineSpacing: 4)
        }
    }

    /// UniPDF's green.
    public static let printAccent = NSColor(red: 0.161, green: 0.4, blue: 0.341, alpha: 1)

    /// On every character of a code block or a box: what is painted behind its lines.
    public static let blockKey = NSAttributedString.Key("UniPDFBlock")
    /// On a link's text: where it leads.
    public static let linkKey = NSAttributedString.Key("UniPDFLink")
    /// On a rule's line: a line is drawn across.
    public static let ruleKey = NSAttributedString.Key("UniPDFRule")

    /// The fill behind a code block or a box. One object per block, so that two blocks one under the other stay apart.
    public final class Block: NSObject, @unchecked Sendable {
        public let fill: NSColor
        /// Room inside the fill, above the first line and beneath the last.
        public let padding: CGFloat
        public let callout: CalloutKind?
        public init(fill: NSColor, padding: CGFloat, callout: CalloutKind?) {
            self.fill = fill; self.padding = padding; self.callout = callout
        }
    }

    /// Room inside a block and between a block and the text around it.
    public static func blockPadding(for size: CGFloat) -> CGFloat { (size * 0.6).rounded() }
    public static func blockGap(for size: CGFloat) -> CGFloat { (size * 0.35).rounded() }

    static func paragraph(_ text: NSAttributedString, at location: Int, base: NSParagraphStyle) -> NSMutableParagraphStyle {
        guard location < text.length else { return base.mutableCopy() as! NSMutableParagraphStyle }
        return (text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle ?? base).mutableCopy() as! NSMutableParagraphStyle
    }

    static func font(size: CGFloat, bold: Bool = false, italic: Bool = false, monospaced: Bool = false) -> NSFont {
        var font = monospaced ? NSFont.monospacedSystemFont(ofSize: size * 0.92, weight: bold ? .semibold : .regular)
                              : NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    /// The paragraph indent of a list item: the text of every line starts at the same place.
    public static func listIndent(for size: CGFloat) -> CGFloat { size * 1.4 }

    /// Styles `text` in place. Markers keep their characters; the caller dims or removes them.
    public static func style(_ text: NSMutableAttributedString, parsed: Parsed, appearance: Appearance) {
        let all = NSRange(location: 0, length: text.length)
        let base = NSMutableParagraphStyle()
        base.lineSpacing = appearance.lineSpacing
        base.lineBreakMode = .byWordWrapping
        text.setAttributes([.font: font(size: appearance.size), .foregroundColor: appearance.color, .paragraphStyle: base], range: all)

        var headingSize: [Int: CGFloat] = [:]
        for line in parsed.lines {
            let paragraph = base.mutableCopy() as! NSMutableParagraphStyle
            switch line.kind {
            case .heading(let level):
                let size = appearance.size * [1.45, 1.25, 1.1][min(level, 3) - 1]
                headingSize[line.range.location] = size
                paragraph.paragraphSpacingBefore = appearance.size * 0.5
                text.addAttribute(.font, value: font(size: size, bold: true), range: line.range)
            case .bullet, .numbered:
                let step = listIndent(for: appearance.size)
                paragraph.firstLineHeadIndent = CGFloat(line.indentationLevel) * step
                paragraph.headIndent = CGFloat(line.indentationLevel + 1) * step
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
                paragraph.defaultTabInterval = step
            case .quote:
                // In a box the text stays upright; the box itself sets it apart.
                guard !parsed.callouts.contains(where: { NSLocationInRange(line.range.location, $0.range) }) else { break }
                paragraph.headIndent = appearance.size
                paragraph.firstLineHeadIndent = 0
                text.addAttribute(.foregroundColor, value: appearance.secondaryColor, range: line.range)
                text.addAttribute(.font, value: font(size: appearance.size, italic: true), range: line.range)
            }
            text.addAttribute(.paragraphStyle, value: paragraph, range: line.range)
        }

        // Fonts combine: bold inside a heading or italic inside bold.
        for span in parsed.spans {
            let size = parsed.lines.first { NSLocationInRange(span.range.location, $0.range) }
                .flatMap { headingSize[$0.range.location] } ?? appearance.size
            switch span.style {
            case .bold, .italic:
                text.enumerateAttribute(.font, in: span.content) { value, range, _ in
                    let current = value as? NSFont ?? font(size: size)
                    let trait: NSFontTraitMask = span.style == .bold ? .boldFontMask : .italicFontMask
                    text.addAttribute(.font, value: NSFontManager.shared.convert(current, toHaveTrait: trait), range: range)
                }
            case .strike:
                text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.content)
            case .code:
                text.addAttribute(.font, value: font(size: size, monospaced: true), range: span.range)
                text.addAttribute(.backgroundColor, value: appearance.codeBackground, range: span.content)
            }
        }

        for line in parsed.lines {
            guard let box = line.checkbox else { continue }
            text.addAttribute(.foregroundColor, value: appearance.accent, range: box)
            let rest = NSRange(location: NSMaxRange(line.marker), length: NSMaxRange(line.range) - NSMaxRange(line.marker))
            // Done is grey, not struck through: it stays readable.
            if line.isChecked, rest.length > 0 { text.addAttribute(.foregroundColor, value: appearance.secondaryColor, range: rest) }
        }
        for link in parsed.links {
            text.addAttributes([.foregroundColor: appearance.accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                linkKey: link.url], range: link.text)
        }
        for rule in parsed.rules where rule.length > 0 {
            text.addAttributes([.foregroundColor: appearance.secondaryColor, ruleKey: true], range: rule)
        }

        let padding = blockPadding(for: appearance.size), gap = blockGap(for: appearance.size)
        for block in parsed.codeBlocks where block.range.length > 0 {
            text.addAttributes([.font: font(size: appearance.size, monospaced: true), .foregroundColor: appearance.color,
                                blockKey: Block(fill: appearance.codeBackground, padding: padding, callout: nil)], range: block.range)
            for fence in [block.opening] + (block.closing.map { [$0] } ?? []) where fence.length > 0 {
                text.addAttribute(.foregroundColor, value: appearance.secondaryColor, range: fence)
            }
            blockParagraphs(text, block.range, base: base, padding: padding, first: gap, last: gap)
        }
        for callout in parsed.callouts {
            let kind = callout.kind
            text.addAttribute(blockKey, value: Block(fill: kind.color.nsColor.withAlphaComponent(kind.tintAlpha), padding: padding, callout: kind),
                              range: callout.range)
            text.addAttributes([.font: font(size: appearance.size * 0.85, bold: true), .foregroundColor: kind.color.nsColor], range: callout.header)
            blockParagraphs(text, callout.range, base: base, padding: padding, first: gap + padding, last: gap + padding)
        }
    }

    /// Indents a block's paragraphs into its fill and keeps room above and beneath it.
    static func blockParagraphs(_ text: NSMutableAttributedString, _ range: NSRange, base: NSParagraphStyle,
                                padding: CGFloat, first: CGFloat, last: CGFloat) {
        let string = text.string as NSString
        var location = range.location
        repeat {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            let style = paragraph(text, at: paragraphRange.location, base: base)
            style.headIndent += padding
            style.firstLineHeadIndent += padding
            style.tailIndent = -padding
            if paragraphRange.location <= range.location { style.paragraphSpacingBefore = first }
            if NSMaxRange(paragraphRange) >= NSMaxRange(range) { style.paragraphSpacing = last }
            if paragraphRange.length > 0 { text.addAttribute(.paragraphStyle, value: style, range: paragraphRange) }
            location = NSMaxRange(paragraphRange)
        } while location < NSMaxRange(range) && location < string.length
    }

    /// The marker characters that a finished text hides: `**`, `# `, `> ` and the like.
    public static func markers(in parsed: Parsed) -> [NSRange] {
        var ranges: [NSRange] = []
        for span in parsed.spans {
            ranges.append(NSRange(location: span.range.location, length: span.content.location - span.range.location))
            ranges.append(NSRange(location: NSMaxRange(span.content), length: NSMaxRange(span.range) - NSMaxRange(span.content)))
        }
        for line in parsed.lines where line.kind != .numbered { ranges.append(line.marker) }
        for link in parsed.links where link.text != link.range {
            ranges.append(NSRange(location: link.range.location, length: link.text.location - link.range.location))
            ranges.append(NSRange(location: NSMaxRange(link.text), length: NSMaxRange(link.range) - NSMaxRange(link.text)))
        }
        return ranges.filter { $0.length > 0 }
    }

    // MARK: Rendering

    /// The finished notes for the exported PDF: styled, without markers, with formulas set.
    /// How a comment's tag looks in the study PDF: its number and the beginning of the passage, as in the app.
    public struct CommentMark: Sendable {
        public var number: Int
        public var label: String
        public var color: CommentColor
        public init(number: Int, label: String, color: CommentColor) {
            self.number = number; self.label = label; self.color = color
        }
    }

    /// On the text of a tag in the study PDF: the pastel the exporter paints beneath it, with rounded corners.
    public static let chipKey = NSAttributedString.Key("UniPDFCommentChip")

    /// A comment's tag as text: number and passage in the darker shade, marked for its pastel background.
    /// Narrow spaces at both ends give the background room around the text; no space in it breaks,
    /// so that a tag stays on one line.
    public static func chip(_ mark: CommentMark, size: CGFloat) -> NSAttributedString {
        let text = "\(mark.number) · \(mark.label)".replacingOccurrences(of: " ", with: "\u{00A0}")
        return NSAttributedString(string: "\u{202F}\(text)\u{202F}", attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: mark.color.strong.nsColor,
            chipKey: mark.color.pastel.nsColor
        ])
    }

    /// Comment tags become tags as in the app; tags without a comment disappear.
    public static func rendered(_ text: String, appearance: Appearance,
                                comments: [UUID: CommentMark] = [:]) -> NSAttributedString {
        let parsed = parse(text)
        let result = NSMutableAttributedString(string: text)
        style(result, parsed: parsed, appearance: appearance)
        let string = text as NSString

        enum Edit { case delete(NSRange), replace(NSRange, NSAttributedString) }
        var edits: [Edit] = []
        let headers = parsed.callouts.map(\.header)
        for range in markers(in: parsed) where !headers.contains(where: { NSIntersectionRange($0, range).length > 0 }) {
            if let line = parsed.lines.first(where: { $0.marker == range }), line.kind == .bullet {
                // The indent before the dash stays out; the bullet hangs in front of the text.
                var attributes = result.attributes(at: range.location, effectiveRange: nil)
                var bullet = "•"
                if line.checkbox != nil {
                    bullet = line.isChecked ? "☑" : "☐"
                    attributes[.foregroundColor] = appearance.accent
                }
                edits.append(.replace(range, NSAttributedString(string: bullet + "\t", attributes: attributes)))
            } else {
                edits.append(.delete(range))
            }
        }
        for line in parsed.lines where line.kind == .numbered {
            // "1. " becomes "1.\t", so that the text lines up as in a bullet list.
            let marker = string.substring(with: line.marker).trimmingCharacters(in: .whitespaces)
            let attributes = result.attributes(at: line.marker.location, effectiveRange: nil)
            edits.append(.replace(line.marker, NSAttributedString(string: marker + "\t", attributes: attributes)))
        }
        for tag in parsed.comments {
            if let comment = comments[tag.id] {
                let chip = NSMutableAttributedString(attributedString: chip(comment, size: appearance.size * 0.85))
                // Keeps the paragraph's indent and spacing.
                if let paragraph = result.attribute(.paragraphStyle, at: tag.range.location, effectiveRange: nil) {
                    chip.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: chip.length))
                }
                edits.append(.replace(tag.range, chip))
            } else {
                edits.append(.delete(tag.range))
            }
        }
        for callout in parsed.callouts {
            let attributes = result.attributes(at: callout.header.location, effectiveRange: nil)
            edits.append(.replace(callout.header, NSAttributedString(string: callout.kind.label, attributes: attributes)))
        }
        let padding = blockPadding(for: appearance.size), gap = blockGap(for: appearance.size)
        for block in parsed.codeBlocks {
            // The fences go; the code keeps its fill, with room inside it above and beneath.
            let opening = string.lineRange(for: block.opening)
            let closing = block.closing.map { closing in
                closing.location > 0 ? NSRange(location: closing.location - 1, length: closing.length + 1) : closing
            }
            let contentStart = NSMaxRange(opening)
            let contentEnd = closing?.location ?? NSMaxRange(block.range)
            if contentEnd > contentStart {
                let content = NSRange(location: contentStart, length: contentEnd - contentStart)
                let first = string.paragraphRange(for: NSRange(location: content.location, length: 0))
                let last = string.paragraphRange(for: NSRange(location: max(NSMaxRange(content) - 1, content.location), length: 0))
                let top = paragraph(result, at: first.location, base: NSParagraphStyle())
                top.paragraphSpacingBefore = gap + padding
                result.addAttribute(.paragraphStyle, value: top, range: first)
                let bottom = paragraph(result, at: last.location, base: NSParagraphStyle())
                bottom.paragraphSpacing = gap + padding
                if last == first { bottom.paragraphSpacingBefore = gap + padding }
                result.addAttribute(.paragraphStyle, value: bottom, range: last)
                edits.append(.delete(opening))
                if let closing { edits.append(.delete(closing)) }
            } else {
                edits.append(.delete(string.lineRange(for: block.range)))
            }
        }
        for rule in parsed.rules {
            var attributes = result.attributes(at: min(rule.location, max(result.length - 1, 0)), effectiveRange: nil)
            attributes[ruleKey] = true
            let style = paragraph(result, at: rule.location, base: NSParagraphStyle())
            style.paragraphSpacingBefore = gap
            style.paragraphSpacing = gap
            attributes[.paragraphStyle] = style
            edits.append(.replace(rule, NSAttributedString(string: "\u{200B}", attributes: attributes)))
        }
        for formula in parsed.formulas {
            let source = string.substring(with: formula.source)
            let size = appearance.size * (formula.isBlock ? 1.25 : 1.1)
            let math = NSMutableAttributedString(attributedString: MathNotation.formatted(oneLine(source), size: size, color: appearance.color))
            if formula.isBlock {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.paragraphSpacing = appearance.size * 0.4
                paragraph.paragraphSpacingBefore = appearance.size * 0.4
                math.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: math.length))
            }
            edits.append(.replace(formula.range, math))
        }
        func location(_ edit: Edit) -> Int {
            switch edit { case .delete(let range), .replace(let range, _): range.location }
        }
        for edit in edits.sorted(by: { location($0) > location($1) }) {
            switch edit {
            case .delete(let range): result.deleteCharacters(in: range)
            case .replace(let range, let value): result.replaceCharacters(in: range, with: value)
            }
        }
        return result
    }

    /// Formulas are set on one line; line breaks in their source only help while writing.
    public static func oneLine(_ source: String) -> String {
        source.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}
