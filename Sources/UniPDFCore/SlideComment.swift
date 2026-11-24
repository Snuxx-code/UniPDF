import Foundation

/// Soft colours for comments: a pastel fill and a darker shade of the same hue for lines and text.
public enum CommentColor: String, Codable, CaseIterable, Sendable {
    case rose, peach, lemon, mint, sky, lavender

    public var label: String {
        switch self {
        case .rose: String(localized: "Rose")
        case .peach: String(localized: "Peach")
        case .lemon: String(localized: "Lemon")
        case .mint: String(localized: "Mint")
        case .sky: String(localized: "Sky")
        case .lavender: String(localized: "Lavender")
        }
    }

    public var pastel: AnnotationColor {
        switch self {
        case .rose: AnnotationColor(red: 0.99, green: 0.86, blue: 0.89)
        case .peach: AnnotationColor(red: 1.00, green: 0.89, blue: 0.80)
        case .lemon: AnnotationColor(red: 1.00, green: 0.95, blue: 0.72)
        case .mint: AnnotationColor(red: 0.83, green: 0.95, blue: 0.87)
        case .sky: AnnotationColor(red: 0.83, green: 0.91, blue: 1.00)
        case .lavender: AnnotationColor(red: 0.90, green: 0.87, blue: 1.00)
        }
    }

    /// For the outline on the slide and the text of the tag.
    public var strong: AnnotationColor {
        switch self {
        case .rose: AnnotationColor(red: 0.78, green: 0.29, blue: 0.42)
        case .peach: AnnotationColor(red: 0.80, green: 0.44, blue: 0.16)
        case .lemon: AnnotationColor(red: 0.62, green: 0.50, blue: 0.04)
        case .mint: AnnotationColor(red: 0.18, green: 0.55, blue: 0.36)
        case .sky: AnnotationColor(red: 0.20, green: 0.45, blue: 0.78)
        case .lavender: AnnotationColor(red: 0.46, green: 0.36, blue: 0.78)
        }
    }

    /// The colour after this one, so that comments side by side differ.
    public var next: CommentColor {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// A comment on a passage of a slide, or on an area where a slide has no text.
public struct SlideComment: Codable, Sendable, Equatable {
    /// In displayed slide points, one per line of the passage, or the one area.
    public var rects: [CGRect]
    public var isArea: Bool
    /// The commented text as it stood on the slide; empty for an area.
    public var quote: String
    /// The comment itself, written like the notes: plain text with markers and formulas.
    public var text: String
    public var color: CommentColor
    public var created: Date

    public init(rects: [CGRect], isArea: Bool = false, quote: String = "", text: String = "",
                color: CommentColor = .rose, created: Date = Date()) {
        self.rects = rects; self.isArea = isArea; self.quote = quote; self.text = text
        self.color = color; self.created = created
    }

    /// What the tag in the notes shows: the beginning of the passage.
    public var label: String {
        guard !isArea else { return String(localized: "Area") }
        let words = quote.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard words.count > 28 else { return words.isEmpty ? String(localized: "Passage") : words }
        let cut = words.prefix(28)
        return (cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)) + " …"
    }
}

/// The tags in the notes that stand for comments, and keeping both sides in step.
public enum CommentLinks {
    /// How a tag is written in the notes. Plain text, so the notes stay plain text.
    public static func token(for id: UUID) -> String { "[[kommentar:\(id.uuidString)]]" }

    static let pattern = try! NSRegularExpression(pattern: #"\[\[kommentar:([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\]\]"#)

    public static func tokens(in text: String) -> [(range: NSRange, id: UUID)] {
        pattern.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).compactMap { match in
            UUID(uuidString: (text as NSString).substring(with: match.range(at: 1))).map { (match.range, $0) }
        }
    }

    public static func comments(in notes: PageNotes) -> [(id: UUID, comment: SlideComment)] {
        notes.annotations.compactMap { annotation in
            guard case .comment(let comment) = annotation.content else { return nil }
            return (annotation.id, comment)
        }
    }

    /// Comments taken out with their tag, for as long as the app runs. Their ids are unique, so one store serves every document.
    public final class Removed: @unchecked Sendable {
        private var kept: [UUID: SlideAnnotation] = [:]
        private let lock = NSLock()
        public init() {}
        func keep(_ annotation: SlideAnnotation) { lock.withLock { kept[annotation.id] = annotation } }
        func annotation(_ id: UUID) -> SlideAnnotation? { lock.withLock { kept[id] } }
    }

    public static let removed = Removed()

    /// Removing a comment's tag from the notes removes the comment from the slide, and the other way round.
    /// Removed comments go into `kept`, so that their tag brings them back when it returns:
    /// pasted after ⌘X, or restored by undo in the notes.
    public static func reconcile(_ new: PageNotes, previous: PageNotes, kept: Removed = removed) -> PageNotes {
        var result = new
        let oldTags = Set(tokens(in: previous.text).map(\.id)), newTags = Set(tokens(in: new.text).map(\.id))
        let oldComments = Set(comments(in: previous).map(\.id)), newComments = Set(comments(in: new).map(\.id))
        let tagsRemoved = oldTags.subtracting(newTags)
        let commentsRemoved = oldComments.subtracting(newComments)
        for annotation in previous.annotations {
            guard case .comment = annotation.content, tagsRemoved.contains(annotation.id) || commentsRemoved.contains(annotation.id) else { continue }
            kept.keep(annotation)
        }
        // A tag that comes back without its comment brings the comment back, where it is still known.
        for id in tokens(in: new.text).map(\.id) where !oldTags.contains(id) && !newComments.contains(id) {
            if let annotation = kept.annotation(id), !result.annotations.contains(where: { $0.id == id }) {
                result.annotations.append(annotation)
            }
        }
        if !tagsRemoved.isEmpty {
            result.annotations.removeAll { annotation in
                guard case .comment = annotation.content else { return false }
                return tagsRemoved.contains(annotation.id)
            }
        }
        if !commentsRemoved.isEmpty {
            let text = NSMutableString(string: result.text)
            for (range, id) in tokens(in: result.text).reversed() where commentsRemoved.contains(id) {
                // A tag alone on its line takes the line with it.
                var removal = range
                let lineBefore = removal.location == 0 || text.character(at: removal.location - 1) == 10
                let lineAfter = NSMaxRange(removal) == text.length || text.character(at: NSMaxRange(removal)) == 10
                if lineBefore, lineAfter {
                    if NSMaxRange(removal) < text.length { removal.length += 1 }
                    else if removal.location > 0 { removal = NSRange(location: removal.location - 1, length: removal.length + 1) }
                }
                text.deleteCharacters(in: removal)
            }
            result.text = text as String
        }
        return result
    }

    /// The comments of a page in the order of their tags, then any without one. They are numbered so in the study PDF.
    public static func ordered(_ notes: PageNotes) -> [(id: UUID, comment: SlideComment)] {
        let all = comments(in: notes)
        let order = tokens(in: notes.text).map(\.id)
        return all.sorted { a, b in
            (order.firstIndex(of: a.id) ?? Int.max, all.firstIndex { $0.id == a.id } ?? 0)
                < (order.firstIndex(of: b.id) ?? Int.max, all.firstIndex { $0.id == b.id } ?? 0)
        }
    }
}
