import Foundation

public struct AIQuestionPrompt: Sendable {
    public let title: String
    public let sourceURL: URL?
    public let studyPDFURL: URL
    public let slidePDFURL: URL
    public let slideNumber: Int
    public let slideCount: Int

    public init(title: String, sourceURL: URL?, studyPDFURL: URL, slidePDFURL: URL,
                slideNumber: Int, slideCount: Int) {
        self.title = title
        self.sourceURL = sourceURL
        self.studyPDFURL = studyPDFURL
        self.slidePDFURL = slidePDFURL
        self.slideNumber = slideNumber
        self.slideCount = slideCount
    }

    public func text(question: String = "") -> String {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = if let sourceURL {
            "Geöffnete Datei (letzter gespeicherter Stand):\n\(sourceURL.path)"
        } else {
            "Die Vorlesung ist noch nicht als eigene Datei gespeichert. Verwende die folgenden PDF-Kopien."
        }
        return """
        Hilf mir bei der Vorlesung „\(title.isEmpty ? "Vorlesung" : title)“.
        Ich beziehe mich auf Originalfolie \(slideNumber) von \(slideCount).

        \(source)

        Aktuelle Lern-PDF mit allen Mitschriften, Formeln und Skizzen, einschließlich noch ungespeicherter Änderungen:
        \(studyPDFURL.path)

        Die ausgewählte Originalfolie als einzelne PDF (Seite 1):
        \(slidePDFURL.path)

        Nutze die aktuelle Lern-PDF für meine Mitschriften und die einzelne Originalfolie für die genaue Zuordnung. Wegen möglicher Fortsetzungsseiten entspricht die Originalfoliennummer nicht unbedingt der Seitenzahl in der Lern-PDF.

        Meine Frage:
        \(question.isEmpty ? "[Hier meine Frage zur Folie eintragen.]" : question)

        Antworte auf Deutsch. Erkläre den Zusammenhang anhand der Vorlesung und kennzeichne, wenn eine Information aus den Unterlagen nicht hervorgeht.
        Falls du lokale Dateien nicht öffnen kannst, bitte mich, die genannten PDF-Kopien anzuhängen.
        """
    }
}
