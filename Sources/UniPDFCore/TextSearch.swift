import Foundation

/// Search across a lecture: the slides' own text, the notes and the text boxes placed on slides.
public enum TextSearch {
    public enum Source: Hashable, Sendable {
        case slide
        case notes
        case textBox(UUID)
        case comment(UUID)
    }

    public struct Hit: Hashable, Sendable, Identifiable {
        public var page: Int
        public var source: Source
        /// In the searched text: the PDF page's string, the notes, or the text box's string.
        public var range: NSRange
        public var before: String
        public var match: String
        public var after: String

        public var id: String { "\(page)-\(source)-\(range.location)" }
    }

    static let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
    /// Enough for any lecture; a one-letter query should not build thousands of rows.
    public static let limit = 500

    /// Hits in reading order: by slide, then the slide's text, its text boxes, its notes.
    public static func hits(for query: String, pageTexts: [String], pages: [Int: PageNotes], limit: Int = limit) -> [Hit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var hits: [Hit] = []
        for page in 0..<pageTexts.count {
            hits += find(needle, in: pageTexts[page], page: page, source: .slide, limit: limit - hits.count)
            let notes = pages[page] ?? PageNotes()
            for annotation in notes.annotations {
                guard case .text(let string, _, _, _, _) = annotation.content else { continue }
                hits += find(needle, in: string, page: page, source: .textBox(annotation.id), limit: limit - hits.count)
            }
            for (id, comment) in CommentLinks.ordered(notes) {
                hits += find(needle, in: comment.text, page: page, source: .comment(id), limit: limit - hits.count)
            }
            hits += find(needle, in: notes.text, page: page, source: .notes, limit: limit - hits.count)
            if hits.count >= limit { break }
        }
        return hits
    }

    static func find(_ needle: String, in text: String, page: Int, source: Source, limit: Int) -> [Hit] {
        guard limit > 0, !text.isEmpty else { return [] }
        let string = text as NSString
        var hits: [Hit] = []
        var searchRange = NSRange(location: 0, length: string.length)
        while hits.count < limit {
            let found = string.range(of: needle, options: options, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            hits.append(hit(found, in: string, page: page, source: source))
            let next = NSMaxRange(found)
            searchRange = NSRange(location: next, length: string.length - next)
        }
        return hits
    }

    /// The match with a little text around it, on one line, cut at word boundaries.
    static func hit(_ range: NSRange, in string: NSString, page: Int, source: Source, context: Int = 32) -> Hit {
        func clean(_ text: String) -> String {
            text.components(separatedBy: .newlines).joined(separator: " ")
                .replacingOccurrences(of: "\t", with: " ")
        }
        let start = max(range.location - context, 0)
        var before = clean(string.substring(with: NSRange(location: start, length: range.location - start)))
        if start > 0 {
            if let space = before.firstIndex(of: " ") { before = String(before[before.index(after: space)...]) }
            before = "…" + before
        }
        let end = min(NSMaxRange(range) + context * 2, string.length)
        var after = clean(string.substring(with: NSRange(location: NSMaxRange(range), length: end - NSMaxRange(range))))
        if end < string.length {
            if let space = after.lastIndex(of: " ") { after = String(after[..<space]) }
            after += "…"
        }
        return Hit(page: page, source: source, range: range, before: before,
                   match: clean(string.substring(with: range)), after: after)
    }
}
