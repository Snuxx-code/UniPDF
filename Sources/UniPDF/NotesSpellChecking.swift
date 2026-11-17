import AppKit
import NaturalLanguage
import UniPDFCore

/// Per-editor language hints; does not change the user's system-wide spelling preferences.
enum NotesSpellChecking {
    private static let openings = try! NSRegularExpression(pattern: #"(?<![\\\w$])\${1,2}(?![\d$])|`"#)

    static func orthography(for text: String) -> NSOrthography {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.german, .english]
        recognizer.processString(text)
        let languages = recognizer.dominantLanguage == .english ? ["en", "de"] : ["de", "en"]
        return NSOrthography(dominantScript: "Latn", languageMap: ["Latn": languages])
    }

    /// Syntax, formulas, code and comment links must not be rewritten by spelling services.
    static func proseResults(_ results: [NSTextCheckingResult], in text: String) -> [NSTextCheckingResult] {
        guard !results.isEmpty else { return [] }
        let parsed = NotesMarkup.parse(text)
        var protected = parsed.formulas.map(\.range) + parsed.comments.map(\.range)
            + parsed.spans.filter { $0.style == .code }.map(\.range) + NotesMarkup.markers(in: parsed)
        let source = text as NSString
        // Protect notation while its closing delimiter has not been typed yet as well.
        for match in openings.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            guard !protected.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { continue }
            let end = source.substring(with: match.range) == "$$" ? source.length
                : NSMaxRange(source.lineRange(for: match.range))
            protected.append(NSRange(location: match.range.location, length: end - match.range.location))
        }
        return results.filter { result in
            result.range.location != NSNotFound && NSMaxRange(result.range) <= source.length
                && !protected.contains { NSIntersectionRange($0, result.range).length > 0 }
        }
    }
}
