import Foundation
import PDFKit
import UniPDFCore

enum AIQuestionContext {
    static func create(project: StudyProject, sourceURL: URL?, slideIndex: Int) throws -> AIQuestionPrompt {
        guard let data = project.pdfData else { throw ProjectError.invalidPDF }
        let source = try PDFExporter.validatedDocument(data: data)
        guard slideIndex >= 0, slideIndex < source.pageCount,
              let page = source.page(at: slideIndex)?.copy() as? PDFPage else { throw ProjectError.invalidData }
        let singleSlide = PDFDocument()
        singleSlide.insert(page, at: 0)
        guard let slideData = singleSlide.dataRepresentation() else { throw ProjectError.exportFailed }
        // A snapshot needs readable PDF pages; the editable project stays in the source document.
        let studyData = try PDFExporter.export(project, includingProject: false)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UniPDF-AI", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let studyURL = directory.appendingPathComponent(String(localized: "Current-Notes.pdf"))
            let slideURL = directory.appendingPathComponent(String(localized: "Original-Slide-\(slideIndex + 1).pdf"))
            try studyData.write(to: studyURL, options: .atomic)
            try slideData.write(to: slideURL, options: .atomic)
            return AIQuestionPrompt(title: project.title, sourceURL: sourceURL,
                                    studyPDFURL: studyURL, slidePDFURL: slideURL,
                                    slideNumber: slideIndex + 1, slideCount: source.pageCount)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
