import Foundation
import PDFKit

/// What Claude may do to a lecture through UniPDF's tools: read a slide, comment on a passage, mark it,
/// add to the notes. Each step works on one slide's notes and returns them changed, so that the app applies
/// it as one change, which one undo takes back. Nothing here overwrites what is already written.
public enum ClaudeEditing {
    public enum Failure: LocalizedError, Equatable {
        case quoteNotFound(String)
        case anchorNotFound(String)
        case noSuchComment(String)
        case empty(String)

        public var errorDescription: String? {
            switch self {
            case .quoteNotFound(let quote):
                "The passage “\(quote)” is not on this slide. Read the slide with read_slide and quote its text exactly."
            case .anchorNotFound(let anchor):
                "“\(anchor)” does not occur in the notes of this slide. Read them with read_slide, or leave out “after”."
            case .noSuchComment(let id): "There is no comment \(id) on this slide."
            case .empty(let field): "“\(field)” must not be empty."
            }
        }
    }

    public static let highlightColors: [(name: String, color: AnnotationColor)] = [
        ("yellow", PDFTextHighlight.yellow),
        ("green", AnnotationColor(red: 0.25, green: 0.85, blue: 0.4)),
        ("pink", AnnotationColor(red: 1, green: 0.4, blue: 0.65)),
        ("blue", AnnotationColor(red: 0.25, green: 0.65, blue: 1)),
    ]

    // MARK: Finding text on the slide

    /// The slide's text as PDFKit reads it.
    public static func text(of page: PDFPage) -> String { page.string ?? "" }

    /// A passage on a page, found however its lines break and its spaces fall, and regardless of case.
    /// `occurrence` counts from 1 where the passage appears more than once.
    public static func find(_ quote: String, on page: PDFPage, occurrence: Int = 1) -> PDFSelection? {
        let source = text(of: page) as NSString
        let (haystack, map) = normalized(source as String)
        let needle = normalized(quote).text
        guard !needle.isEmpty else { return nil }
        var start = haystack.startIndex
        var found = 0
        while let range = haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: start..<haystack.endIndex) {
            found += 1
            if found == max(occurrence, 1) {
                let lower = haystack.distance(from: haystack.startIndex, to: range.lowerBound)
                let upper = haystack.distance(from: haystack.startIndex, to: range.upperBound)
                let from = map[lower].location, to = NSMaxRange(map[upper - 1])
                return page.selection(for: NSRange(location: from, length: to - from))
            }
            start = range.upperBound
        }
        return nil
    }

    /// The text with every run of white space as one space, and for each of its characters the UTF-16 range
    /// it came from in the original.
    static func normalized(_ string: String) -> (text: String, map: [NSRange]) {
        var text = "", map: [NSRange] = []
        var offset = 0, pendingSpace = false
        for character in string {
            let length = String(character).utf16.count
            if character.isWhitespace || character.isNewline {
                pendingSpace = !text.isEmpty
            } else {
                if pendingSpace { text.append(" "); map.append(NSRange(location: offset, length: 0)); pendingSpace = false }
                text.append(character)
                map.append(NSRange(location: offset, length: length))
            }
            offset += length
        }
        return (text, map)
    }

    /// The passage's lines in displayed slide points, as the highlighter marks them.
    static func lineRects(_ selection: PDFSelection, on page: PDFPage) -> [CGRect] {
        selection.selectionsByLine().compactMap { line -> CGRect? in
            guard let string = line.string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return PDFTextHighlight.slideRect(line.bounds(for: page), on: page)
        }
    }

    // MARK: Changes

    /// A comment on a passage of the slide, with its tag in the notes: after `anchor` if given,
    /// otherwise on a new line at the end.
    public static func addComment(to notes: PageNotes, page: PDFPage, quote: String, text: String, color: CommentColor? = nil,
                                  occurrence: Int = 1, after anchor: String? = nil) throws -> (notes: PageNotes, id: UUID) {
        guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty("quote") }
        guard let selection = find(quote, on: page, occurrence: occurrence) else { throw Failure.quoteNotFound(quote) }
        let rects = lineRects(selection, on: page)
        guard !rects.isEmpty else { throw Failure.quoteNotFound(quote) }
        // New comments take the colours in turn, as when made by hand.
        let used = CommentLinks.comments(in: notes).count
        let comment = SlideComment(rects: rects, quote: selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? quote,
                                   text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                   color: color ?? CommentColor.allCases[used % CommentColor.allCases.count])
        let annotation = SlideAnnotation(content: .comment(comment))
        var result = notes
        result.annotations.append(annotation)
        result.text = try insertInline(CommentLinks.token(for: annotation.id), into: result.text, after: anchor)
        return (result, annotation.id)
    }

    /// Text for the notes, in their markup, as its own paragraph: after the line holding `anchor`, or at the end.
    public static func addNotes(to notes: PageNotes, text: String, after anchor: String? = nil) throws -> PageNotes {
        let addition = text.trimmingCharacters(in: .newlines)
        guard !addition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty("text") }
        var result = notes
        let current = notes.text as NSString
        if let anchor, !anchor.isEmpty {
            let found = current.range(of: anchor, options: [.caseInsensitive])
            guard found.location != NSNotFound else { throw Failure.anchorNotFound(anchor) }
            let lineEnd = current.lineRange(for: found)
            let end = NSMaxRange(lineEnd)
            // After the line's break, or after a new one where the line is the last.
            let endsWithBreak = end > 0 && current.character(at: end - 1) == 10
            let insertion = endsWithBreak ? addition + "\n" : "\n" + addition
            result.text = current.replacingCharacters(in: NSRange(location: end, length: 0), with: insertion)
        } else {
            let trimmed = notes.text.trimmingCharacters(in: .newlines)
            result.text = trimmed.isEmpty ? addition : trimmed + "\n" + addition
        }
        return result
    }

    /// The highlighter over a passage of the slide.
    public static func highlight(in notes: PageNotes, page: PDFPage, quote: String, color: AnnotationColor = PDFTextHighlight.yellow,
                                 occurrence: Int = 1) throws -> (notes: PageNotes, id: UUID) {
        guard !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.empty("quote") }
        guard let selection = find(quote, on: page, occurrence: occurrence),
              let annotation = PDFTextHighlight.annotation(for: selection, on: page, color: color) else { throw Failure.quoteNotFound(quote) }
        var result = notes
        result.annotations.append(annotation)
        return (result, annotation.id)
    }

    public static func editComment(in notes: PageNotes, id: String, text: String?, color: CommentColor?) throws -> PageNotes {
        guard let uuid = UUID(uuidString: id),
              let index = notes.annotations.firstIndex(where: { $0.id == uuid }),
              case .comment(var comment) = notes.annotations[index].content else { throw Failure.noSuchComment(id) }
        if let text { comment.text = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let color { comment.color = color }
        var result = notes
        result.annotations[index].content = .comment(comment)
        return result
    }

    /// The comment off the slide and its tag out of the notes.
    public static func deleteComment(in notes: PageNotes, id: String) throws -> PageNotes {
        guard let uuid = UUID(uuidString: id),
              notes.annotations.contains(where: { $0.id == uuid && { if case .comment = $0.content { true } else { false } }($0) })
        else { throw Failure.noSuchComment(id) }
        var result = notes
        result.annotations.removeAll { $0.id == uuid }
        return CommentLinks.reconcile(result, previous: notes)
    }

    /// Puts `token` after `anchor` within its line, or on a new line at the end, with a space on either side where needed.
    static func insertInline(_ token: String, into text: String, after anchor: String?) throws -> String {
        guard let anchor, !anchor.isEmpty else {
            let trimmed = text.trimmingCharacters(in: .newlines)
            return trimmed.isEmpty ? token : trimmed + "\n" + token
        }
        let current = text as NSString
        let found = current.range(of: anchor, options: [.caseInsensitive])
        guard found.location != NSNotFound else { throw Failure.anchorNotFound(anchor) }
        let at = NSMaxRange(found)
        let after = at < current.length ? current.substring(with: NSRange(location: at, length: 1)) : "\n"
        let insertion = " " + token + (after.rangeOfCharacter(from: .whitespacesAndNewlines) == nil ? " " : "")
        return current.replacingCharacters(in: NSRange(location: at, length: 0), with: insertion)
    }

    // MARK: Reading

    /// One slide as Claude reads it: its text, the notes as written, the comments with their ids, and what else is on it.
    public static func describe(slide index: Int, of count: Int, page: PDFPage, notes: PageNotes) -> [String: Any] {
        let comments = CommentLinks.ordered(notes).map { item -> [String: Any] in
            ["id": item.id.uuidString, "quote": item.comment.quote, "comment": item.comment.text,
             "color": item.comment.color.rawValue, "area": item.comment.isArea]
        }
        var textBoxes: [String] = []
        var highlights = 0, drawings = 0
        for annotation in notes.annotations {
            switch annotation.content {
            case .text(let string, _, _, _, _): textBoxes.append(string)
            case .highlight: highlights += 1
            case .ink, .shape, .image: drawings += 1
            case .comment: break
            }
        }
        return [
            "slide": index + 1, "slides": count,
            "slideText": text(of: page).trimmingCharacters(in: .whitespacesAndNewlines),
            "notes": notes.text, "comments": comments, "textBoxes": textBoxes,
            "highlights": highlights, "drawings": drawings,
        ]
    }

    /// A value as pretty JSON, for a tool's answer.
    public static func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return String(describing: value) }
        return String(decoding: data, as: UTF8.self)
    }
}
