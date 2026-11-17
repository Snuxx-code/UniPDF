import CoreGraphics
import Foundation

/// The editable project lives in the PDF's standard XMP metadata stream.
/// Reopening restores the original slides, rather than reimporting the rendered study pages.
enum PDFProjectMetadata {
    static let namespace = "urn:unipdf:project:1.0"

    static func encode(_ project: StudyProject) throws -> Data {
        let payload = try project.encoded().base64EncodedString()
        return Data("""
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:unipdf="\(namespace)">
              <unipdf:project>\(payload)</unipdf:project>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """.utf8)
    }

    static func decode(from data: Data) throws -> StudyProject? {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider), let catalog = document.catalog else {
            throw ProjectError.invalidPDF
        }
        var metadata: CGPDFStreamRef?
        guard CGPDFDictionaryGetStream(catalog, "Metadata", &metadata), let metadata else { return nil }
        var format = CGPDFDataFormat.raw
        guard let xml = CGPDFStreamCopyData(metadata, &format) else { throw ProjectError.invalidData }
        let reader = MetadataReader()
        let parser = XMLParser(data: xml as Data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = reader
        let parsed = parser.parse()
        // Ordinary PDF metadata is unrelated to UniPDF and can be ignored.
        guard reader.projectCount > 0 else { return nil }
        guard parsed, reader.projectCount == 1,
              let payload = Data(base64Encoded: reader.payload.filter { !$0.isWhitespace }) else {
            throw ProjectError.invalidData
        }
        return try StudyProject.decode(payload)
    }

    private final class MetadataReader: NSObject, XMLParserDelegate {
        var projectCount = 0
        var payload = ""
        private var reading = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            if namespaceURI == PDFProjectMetadata.namespace && elementName == "project" {
                projectCount += 1
                reading = true
            } else if reading {
                // A project is base64 text, never nested markup.
                parser.abortParsing()
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if reading { payload += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if namespaceURI == PDFProjectMetadata.namespace && elementName == "project" { reading = false }
        }
    }
}

public enum StudyPDF {
    /// Opens an ordinary lecture, or restores a previously saved editable study PDF.
    public static func open(_ data: Data, title: String = String(localized: "Lecture")) throws -> StudyProject {
        _ = try PDFExporter.validatedDocument(data: data)
        if let project = try PDFProjectMetadata.decode(from: data) {
            guard let original = project.pdfData else { throw ProjectError.invalidData }
            let source = try PDFExporter.validatedDocument(data: original)
            guard project.pages.keys.allSatisfy({ $0 < source.pageCount }) else { throw ProjectError.invalidData }
            return project
        }
        return StudyProject(title: title, pdfData: data)
    }
}
