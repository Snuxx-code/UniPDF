import AppKit
import PDFKit
import QuickLookThumbnailing

/// Previews for library tiles. Quick Look covers PDFs and common file types and falls back to
/// the file's icon; legacy projects keep their PDF inside and are rendered from it.
public enum LibraryThumbnail {
    public static func image(for url: URL, size: CGSize, scale: CGFloat) async -> CGImage? {
        if url.pathExtension.lowercased() == "unipdf" {
            return await Task.detached(priority: .utility) { projectCover(url, size: size) }.value
        }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: scale, representationTypes: .all)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }

    private static func projectCover(_ url: URL, size: CGSize) -> CGImage? {
        guard let data = try? Data(contentsOf: url), let project = try? StudyProject.decode(data),
              let pdf = project.pdfData, let page = PDFDocument(data: pdf)?.page(at: 0) else { return nil }
        return page.thumbnail(of: CGSize(width: size.width * 2, height: size.height * 2), for: .cropBox)
            .cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
