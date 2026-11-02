import SwiftUI
import UniformTypeIdentifiers
import UniPDFCore

extension UTType {
    nonisolated static let uniPDF = UTType(exportedAs: "de.unipdf.study-project", conformingTo: .data)
}

struct StudyDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf, .uniPDF] }
    static var writableContentTypes: [UTType] { [.pdf, .uniPDF] }
    var project: StudyProject

    init(project: StudyProject = StudyProject()) { self.project = project }

    nonisolated init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ProjectError.invalidData }
        let filename = configuration.file.preferredFilename ?? configuration.file.filename ?? "Vorlesung.pdf"
        try self.init(data: data, contentType: configuration.contentType,
                      title: (filename as NSString).deletingPathExtension)
    }

    nonisolated init(data: Data, contentType: UTType, title: String = "Vorlesung") throws {
        if contentType.conforms(to: .pdf) {
            project = try StudyPDF.open(data, title: title)
        } else {
            guard contentType == .uniPDF else { throw ProjectError.invalidData }
            project = try StudyProject.decode(data)
        }
        if let pdf = project.pdfData {
            let document = try PDFExporter.validatedDocument(data: pdf)
            guard project.pages.keys.allSatisfy({ $0 < document.pageCount }) else { throw ProjectError.invalidData }
        } else if !project.pages.isEmpty { throw ProjectError.invalidData }
    }

    nonisolated func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try contents(for: configuration.contentType))
    }

    nonisolated func contents(for contentType: UTType) throws -> Data {
        if contentType.conforms(to: .pdf) { return try PDFExporter.export(project) }
        guard contentType == .uniPDF else { throw ProjectError.invalidData }
        return try project.encoded()
    }
}
