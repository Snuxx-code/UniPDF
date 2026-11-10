import AppKit

/// Light formatting for the notes, written as in chat apps and Markdown.
/// The notes stay plain text: `**fett**` or `*fett*`, `_kursiv_`, `~durchgestrichen~`, `` `Code` ``,
/// `# Überschrift`, `- Stichpunkt`, `1. Aufzählung`, `> Zitat`, and formulas as `$x^{2}$` or `$$ … $$` blocks.
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
        /// `## `, `- `, `1. ` or `> `, with the indent before it.
        public var marker: NSRange
    }

    public struct Parsed: Sendable, Equatable {
        public var formulas: [Formula] = []
        public var spans: [Span] = []
        public var lines: [Line] = []
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

        for match in blockFormula.matches(in: text, range: all) {
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

        string.enumerateSubstrings(in: all, options: [.byLines, .substringNotRequired]) { _, line, _, _ in
            guard isFree(NSRange(location: line.location, length: min(line.length, 1))) || line.length == 0 else { return }
            for (pattern, kind) in lineKinds {
                guard let match = pattern.firstMatch(in: text, range: line), match.range.location == line.location else { continue }
                parsed.lines.append(Line(kind: kind(match), range: line, marker: match.range))
                break
            }
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

        public init(size: CGFloat, color: NSColor, secondaryColor: NSColor, codeBackground: NSColor, lineSpacing: CGFloat) {
            self.size = size; self.color = color; self.secondaryColor = secondaryColor
            self.codeBackground = codeBackground; self.lineSpacing = lineSpacing
        }

        public static func print(size: CGFloat) -> Appearance {
            Appearance(size: size, color: .black, secondaryColor: .darkGray,
                       codeBackground: NSColor(white: 0.93, alpha: 1), lineSpacing: 4)
        }
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
                let indent = listIndent(for: appearance.size)
                paragraph.headIndent = indent
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
                paragraph.defaultTabInterval = indent
            case .quote:
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
    }

    /// The marker characters that a finished text hides: `**`, `# `, `> ` and the like.
    public static func markers(in parsed: Parsed) -> [NSRange] {
        var ranges: [NSRange] = []
        for span in parsed.spans {
            ranges.append(NSRange(location: span.range.location, length: span.content.location - span.range.location))
            ranges.append(NSRange(location: NSMaxRange(span.content), length: NSMaxRange(span.range) - NSMaxRange(span.content)))
        }
        for line in parsed.lines where line.kind != .numbered { ranges.append(line.marker) }
        return ranges.filter { $0.length > 0 }
    }

    // MARK: Rendering

    /// The finished notes for the exported PDF: styled, without markers, with formulas set.
    public static func rendered(_ text: String, appearance: Appearance) -> NSAttributedString {
        let parsed = parse(text)
        let result = NSMutableAttributedString(string: text)
        style(result, parsed: parsed, appearance: appearance)
        let string = text as NSString

        enum Edit { case delete(NSRange), replace(NSRange, NSAttributedString) }
        var edits: [Edit] = []
        for range in markers(in: parsed) {
            if let line = parsed.lines.first(where: { $0.marker == range }), line.kind == .bullet {
                // The indent before the dash stays out; the bullet hangs in front of the text.
                let attributes = result.attributes(at: range.location, effectiveRange: nil)
                edits.append(.replace(range, NSAttributedString(string: "•\t", attributes: attributes)))
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
