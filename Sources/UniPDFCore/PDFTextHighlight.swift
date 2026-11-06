import PDFKit

/// Converts PDFKit text selections into the same displayed slide coordinates as other annotations.
public enum PDFTextHighlight {
    public static let yellow = AnnotationColor(red: 1, green: 0.84, blue: 0.12)

    public static func annotation(for selection: PDFSelection, on page: PDFPage,
                                  color: AnnotationColor = yellow) -> SlideAnnotation? {
        guard selection.pages.contains(where: { $0 === page }) else { return nil }
        let rects = selection.selectionsByLine().compactMap { line -> CGRect? in
            guard line.pages.contains(where: { $0 === page }),
                  let text = line.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return slideRect(line.bounds(for: page), on: page)
        }
        let result = SlideAnnotation(content: .highlight(rects: rects, color: color))
        return result.isValid ? result : nil
    }

    /// Every visible character of the page in slide points, so that the eraser can remove whole characters.
    public static func characterRects(on page: PDFPage) -> [CGRect] {
        (0..<page.numberOfCharacters).compactMap { slideRect(page.characterBounds(at: $0), on: page) }
    }

    /// PDFKit uses unrotated, bottom-left page space. Annotations use the visible crop,
    /// after rotation, with a top-left origin.
    static func slideRect(_ pageRect: CGRect, on page: PDFPage) -> CGRect? {
        let crop = page.bounds(for: .cropBox)
        let rect = pageRect.intersection(crop)
        guard !rect.isNull, !rect.isEmpty else { return nil }
        switch (page.rotation % 360 + 360) % 360 {
        case 90:
            return CGRect(x: rect.minY - crop.minY, y: rect.minX - crop.minX, width: rect.height, height: rect.width)
        case 180:
            return CGRect(x: crop.maxX - rect.maxX, y: rect.minY - crop.minY, width: rect.width, height: rect.height)
        case 270:
            return CGRect(x: crop.maxY - rect.maxY, y: crop.maxX - rect.maxX, width: rect.height, height: rect.width)
        default:
            return CGRect(x: rect.minX - crop.minX, y: crop.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
    }
}
