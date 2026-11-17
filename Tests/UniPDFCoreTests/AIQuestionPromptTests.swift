import Foundation
import Testing
@testable import UniPDFCore

@Suite struct AIQuestionPromptTests {
    private func context(sourceURL: URL? = URL(fileURLWithPath: "/Users/student/Uni/Übung 3 – Analysis.pdf")) -> AIQuestionPrompt {
        AIQuestionPrompt(title: "Analysis", sourceURL: sourceURL,
                         studyPDFURL: URL(fileURLWithPath: "/tmp/UniPDF-AI/test/Current-Notes.pdf"),
                         slidePDFURL: URL(fileURLWithPath: "/tmp/UniPDF-AI/test/Original-Slide-3.pdf"),
                         slideNumber: 3, slideCount: 24)
    }

    @Test func preservesRealPathsAndOriginalSlideNumber() {
        let prompt = context().text(question: "  Warum ist die Ableitung hier null?  ")
        #expect(prompt.contains("/Users/student/Uni/Übung 3 – Analysis.pdf"))
        #expect(!prompt.contains("%20"))
        #expect(prompt.contains("original slide 3 of 24"))
        #expect(prompt.contains("/tmp/UniPDF-AI/test/Original-Slide-3.pdf"))
        #expect(prompt.contains("/tmp/UniPDF-AI/test/Current-Notes.pdf"))
        #expect(prompt.contains("My question:\nWarum ist die Ableitung hier null?"))
        #expect(!prompt.contains("[Enter my question"))
    }

    @Test func unsavedDocumentUsesExistingSnapshotPathsWithoutInventingASource() {
        let prompt = context(sourceURL: nil).text()
        #expect(prompt.contains("not saved as a file of its own yet"))
        #expect(prompt.contains("[Enter my question about the slide here.]"))
        #expect(prompt.contains("/tmp/UniPDF-AI/test/Current-Notes.pdf"))
        #expect(!prompt.contains("/Users/student"))
    }
}
