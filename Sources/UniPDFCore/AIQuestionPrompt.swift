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
            String(localized: "Open file (last saved version):\n\(sourceURL.path)")
        } else {
            String(localized: "The lecture is not saved as a file of its own yet. Use the PDF copies below.")
        }
        let lecture = title.isEmpty ? String(localized: "Lecture") : title
        let asked = question.isEmpty ? String(localized: "[Enter my question about the slide here.]") : question
        // The prompt asks for an answer in the language the student uses the app in.
        return String(localized: """
        Help me with the lecture “\(lecture)”.
        I am referring to original slide \(slideNumber) of \(slideCount).

        \(source)

        Current study PDF with all notes, formulas and sketches, including unsaved changes:
        \(studyPDFURL.path)

        The selected original slide as a single PDF (page 1):
        \(slidePDFURL.path)

        Use the current study PDF for my notes and the single original slide to tell exactly which slide I mean. Because of continuation pages, the original slide number is not necessarily the page number in the study PDF.

        My question:
        \(asked)

        Answer in English. Explain the context using the lecture, and say so when the material does not contain a piece of information.
        If you cannot open local files, ask me to attach the PDF copies named above.
        """)
    }
}
