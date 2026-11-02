import Foundation
import Testing
@testable import UniPDFCore

@Suite struct AIQuestionPromptTests {
    private func context(sourceURL: URL? = URL(fileURLWithPath: "/Users/student/Uni/Übung 3 – Analysis.pdf")) -> AIQuestionPrompt {
        AIQuestionPrompt(title: "Analysis", sourceURL: sourceURL,
                         studyPDFURL: URL(fileURLWithPath: "/tmp/UniPDF-KI/test/Aktuelle-Mitschrift.pdf"),
                         slidePDFURL: URL(fileURLWithPath: "/tmp/UniPDF-KI/test/Originalfolie-3.pdf"),
                         slideNumber: 3, slideCount: 24)
    }

    @Test func preservesRealPathsAndOriginalSlideNumber() {
        let prompt = context().text(question: "  Warum ist die Ableitung hier null?  ")
        #expect(prompt.contains("/Users/student/Uni/Übung 3 – Analysis.pdf"))
        #expect(!prompt.contains("%20"))
        #expect(prompt.contains("Originalfolie 3 von 24"))
        #expect(prompt.contains("/tmp/UniPDF-KI/test/Originalfolie-3.pdf"))
        #expect(prompt.contains("/tmp/UniPDF-KI/test/Aktuelle-Mitschrift.pdf"))
        #expect(prompt.contains("Meine Frage:\nWarum ist die Ableitung hier null?"))
        #expect(!prompt.contains("[Hier meine Frage"))
    }

    @Test func unsavedDocumentUsesExistingSnapshotPathsWithoutInventingASource() {
        let prompt = context(sourceURL: nil).text()
        #expect(prompt.contains("noch nicht als eigene Datei gespeichert"))
        #expect(prompt.contains("[Hier meine Frage zur Folie eintragen.]"))
        #expect(prompt.contains("/tmp/UniPDF-KI/test/Aktuelle-Mitschrift.pdf"))
        #expect(!prompt.contains("/Users/student"))
    }
}
