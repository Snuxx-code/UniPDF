import AppKit
import CoreText
import PDFKit
import Testing
@testable import UniPDFCore

private let red = AnnotationColor(red: 1, green: 0, blue: 0)

private func solidImage(_ color: NSColor, size: Int = 8) throws -> Data {
    let context = try #require(CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let image = try #require(context.makeImage())
    return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
}

private func lecturePDF(size: CGSize = CGSize(width: 640, height: 360), rotation: Int = 0, cropBox: CGRect? = nil) throws -> Data {
    let data = NSMutableData()
    var box = CGRect(origin: .zero, size: size)
    let consumer = try #require(CGDataConsumer(data: data))
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    context.setFillColor(NSColor.white.cgColor); context.fill(box)
    context.endPDFPage(); context.closePDF()
    let document = try #require(PDFDocument(data: data as Data))
    let page = try #require(document.page(at: 0))
    page.rotation = rotation
    if let cropBox { page.setBounds(cropBox, for: .cropBox) }
    return try #require(document.dataRepresentation())
}

/// A bitmap of the first exported page at 2 pixels per point, addressed in PDF points from the bottom left.
private struct RenderedPage {
    let context: CGContext

    init(_ pdf: Data) throws {
        let provider = try #require(CGDataProvider(data: pdf as CFData))
        let page = try #require(CGPDFDocument(provider)?.page(at: 1))
        let box = page.getBoxRect(.mediaBox)
        context = try #require(CGContext(data: nil, width: Int(box.width * 2), height: Int(box.height * 2), bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 2, y: 2)
        context.drawPDFPage(page)
    }

    func isRed(_ x: CGFloat, _ y: CGFloat) -> Bool {
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let row = context.height - 1 - Int(y * 2)
        let offset = row * context.bytesPerRow + Int(x * 2) * 4
        return bytes[offset] > 200 && bytes[offset + 1] < 60 && bytes[offset + 2] < 60
    }
}

@Suite struct SlideAnnotationModelTests {
    @Test func projectWithoutAnnotationsFromVersionOneStillOpens() throws {
        let json = #"{"version":1,"title":"Alt","pages":{"0":{"text":"Notiz","formula":"","drawing":[]}}}"#
        let project = try StudyProject.decode(Data(json.utf8))
        #expect(project.pages[0]?.text == "Notiz")
        #expect(project.pages[0]?.annotations == [])
        #expect(project.version == StudyProject.currentVersion)
    }

    @Test func everyKindSurvivesRoundTrip() throws {
        var notes = PageNotes()
        notes.annotations = [
            SlideAnnotation(content: .ink(points: [CGPoint(x: 1, y: 2), CGPoint(x: 30.5, y: 40)], color: red, width: 3)),
            SlideAnnotation(content: .shape(.circle, start: CGPoint(x: 5, y: 5), end: CGPoint(x: 50, y: 50), color: red, width: 2)),
            SlideAnnotation(content: .text("Größe 中文", frame: CGRect(x: 1, y: 2, width: 100, height: 30),
                                           style: SlideTextStyle(fontFamily: "Helvetica", size: 18, bold: true, italic: true, underline: true), color: red)),
            SlideAnnotation(content: .image(Data([1, 2, 3]), frame: CGRect(x: 0, y: 0, width: 10, height: 20)))
        ]
        let restored = try StudyProject.decode(StudyProject(pdfData: Data([1]), pages: [0: notes]).encoded())
        #expect(restored.pages[0] == notes)
    }

    @Test func annotationsAloneCountAsContent() {
        var notes = PageNotes()
        #expect(notes.isEmpty)
        notes.annotations = [SlideAnnotation(content: .ink(points: [.zero], color: red, width: 1))]
        #expect(!notes.isEmpty)
    }

    @Test func rejectsInvalidAnnotations() throws {
        var notes = PageNotes()
        notes.annotations = [SlideAnnotation(content: .image(Data(), frame: CGRect(x: 0, y: 0, width: 10, height: 10)))]
        #expect(throws: ProjectError.self) { try StudyProject.decode(StudyProject(pages: [0: notes]).encoded()) }
        notes.annotations = [SlideAnnotation(content: .ink(points: [], color: red, width: 1))]
        #expect(throws: ProjectError.self) { try StudyProject.decode(StudyProject(pages: [0: notes]).encoded()) }
    }

    @Test func movingAndResizingMapTheGeometry() {
        let line = SlideAnnotation(content: .shape(.line, start: CGPoint(x: 10, y: 50), end: CGPoint(x: 30, y: 10), color: red, width: 2))
        #expect(line.moved(by: CGVector(dx: 5, dy: -5)).bounds == CGRect(x: 15, y: 5, width: 20, height: 40))
        // A line keeps its direction, which its bounds alone do not record.
        guard case .shape(_, let start, let end, _, _) = line.resized(to: CGRect(x: 0, y: 0, width: 40, height: 80)).content else {
            Issue.record("Not a shape")
            return
        }
        #expect(start == CGPoint(x: 0, y: 80))
        #expect(end == CGPoint(x: 40, y: 0))
        let ink = SlideAnnotation(content: .ink(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 20)], color: red, width: 2))
        #expect(ink.resized(to: CGRect(x: 100, y: 100, width: 20, height: 20)).bounds == CGRect(x: 100, y: 100, width: 20, height: 20))
    }

    @Test func shapesAreHitAtTheirLineAndBoxesInside() {
        let box = SlideAnnotation(content: .shape(.rectangle, start: CGPoint(x: 10, y: 10), end: CGPoint(x: 110, y: 110), color: red, width: 2))
        #expect(box.contains(CGPoint(x: 10, y: 60), tolerance: 3))
        #expect(!box.contains(CGPoint(x: 60, y: 60), tolerance: 3))
        #expect(!box.contains(CGPoint(x: 200, y: 60), tolerance: 3))
        let circle = SlideAnnotation(content: .shape(.circle, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), color: red, width: 2))
        #expect(circle.contains(CGPoint(x: 100, y: 50), tolerance: 3))
        // The box's corner is not on the circle.
        #expect(!circle.contains(CGPoint(x: 1, y: 1), tolerance: 3))
        let dot = SlideAnnotation(content: .ink(points: [CGPoint(x: 50, y: 50)], color: red, width: 2))
        #expect(dot.contains(CGPoint(x: 52, y: 50), tolerance: 3))
        #expect(!dot.contains(CGPoint(x: 60, y: 50), tolerance: 3))
        let text = SlideAnnotation(content: .text("Hallo", frame: CGRect(x: 0, y: 0, width: 100, height: 30), style: SlideTextStyle(), color: red))
        #expect(text.contains(CGPoint(x: 50, y: 15), tolerance: 0))
    }

    @Test func fontsFollowTheStyleAndFallBack() {
        let bold = AnnotationRenderer.font(for: SlideTextStyle(fontFamily: "Helvetica", size: 20, bold: true))
        #expect(bold.familyName == "Helvetica")
        #expect(bold.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(bold.pointSize == 20)
        let missing = AnnotationRenderer.font(for: SlideTextStyle(fontFamily: "Gibt es nicht", size: 20))
        #expect(missing.familyName == NSFont.systemFont(ofSize: 20).familyName)
    }

    @Test func textHeightGrowsWithWrappedLines() {
        let style = SlideTextStyle(size: 20)
        let one = AnnotationRenderer.textHeight("Wort", style: style, width: 300)
        #expect(one > 0)
        #expect(AnnotationRenderer.textHeight("", style: style, width: 300) == one)
        #expect(AnnotationRenderer.textHeight("Wort\n", style: style, width: 300) > one)
        #expect(AnnotationRenderer.textHeight(String(repeating: "Wort ", count: 50), style: style, width: 100) > one * 3)
    }

    @Test func importedImagesAreUprightBoundedAndReadable() throws {
        let large = try solidImage(.red, size: 3000)
        let prepared = try SlideImageImport.prepare(large)
        #expect(prepared.pixelSize == CGSize(width: 2400, height: 2400))
        #expect(NSImage(data: prepared.data) != nil)
        #expect(throws: ProjectError.self) { try SlideImageImport.prepare(Data("kein Bild".utf8)) }
    }
}

@Suite @MainActor struct SlideAnnotationExportTests {
    /// The study page's slide area, which a slide fills centered and without being enlarged.
    private func displayedRect(of size: CGSize) -> CGRect {
        let area = CGRect(x: 32, y: 72, width: 460, height: 428)
        let scale = min(area.width / size.width, area.height / size.height, 1)
        return CGRect(x: area.midX - size.width * scale / 2, y: area.midY - size.height * scale / 2,
                      width: size.width * scale, height: size.height * scale)
    }

    /// A red square in the slide's displayed top-left corner must land there, and nowhere else.
    private func expectTopLeftSquare(pdf: Data, displayed size: CGSize) throws {
        let square = size.width / 4
        var notes = PageNotes()
        notes.annotations = [SlideAnnotation(content: .image(try solidImage(.red), frame: CGRect(x: 0, y: 0, width: square, height: square)))]
        let rendered = try RenderedPage(PDFExporter.export(StudyProject(pdfData: pdf, pages: [0: notes])))
        let rect = displayedRect(of: size)
        let scale = rect.width / size.width
        let part = square * scale
        #expect(rendered.isRed(rect.minX + part / 2, rect.maxY - part / 2))
        #expect(rendered.isRed(rect.minX + 2, rect.maxY - 2))
        #expect(!rendered.isRed(rect.minX + part + 3, rect.maxY - part / 2))
        #expect(!rendered.isRed(rect.minX + part / 2, rect.maxY - part - 3))
        #expect(!rendered.isRed(rect.maxX - part / 2, rect.minY + part / 2))
    }

    @Test(arguments: [0, 180]) func uprightPagesPlaceAnnotationsCorrectly(rotation: Int) throws {
        try expectTopLeftSquare(pdf: lecturePDF(rotation: rotation), displayed: CGSize(width: 640, height: 360))
    }

    @Test(arguments: [90, 270]) func turnedPagesPlaceAnnotationsCorrectly(rotation: Int) throws {
        try expectTopLeftSquare(pdf: lecturePDF(rotation: rotation), displayed: CGSize(width: 360, height: 640))
    }

    @Test func croppedPagesCountFromTheVisibleCorner() throws {
        let crop = CGRect(x: 100, y: 50, width: 320, height: 180)
        try expectTopLeftSquare(pdf: lecturePDF(cropBox: crop), displayed: crop.size)
    }

    @Test func smallPagesAreNotEnlarged() throws {
        try expectTopLeftSquare(pdf: lecturePDF(size: CGSize(width: 200, height: 100)), displayed: CGSize(width: 200, height: 100))
    }

    @Test func allKindsAppearOnTheStudyPage() throws {
        let pdf = try lecturePDF()
        let rect = displayedRect(of: CGSize(width: 640, height: 360))
        let scale = rect.width / 640
        func x(_ value: CGFloat) -> CGFloat { rect.minX + value * scale }
        func y(_ value: CGFloat) -> CGFloat { rect.maxY - value * scale }
        var notes = PageNotes()
        notes.annotations = [
            SlideAnnotation(content: .ink(points: [CGPoint(x: 50, y: 40), CGPoint(x: 150, y: 40)], color: red, width: 8)),
            SlideAnnotation(content: .shape(.rectangle, start: CGPoint(x: 200, y: 20), end: CGPoint(x: 300, y: 80), color: red, width: 8)),
            SlideAnnotation(content: .shape(.line, start: CGPoint(x: 350, y: 40), end: CGPoint(x: 450, y: 40), color: red, width: 8)),
            SlideAnnotation(content: .shape(.circle, start: CGPoint(x: 500, y: 20), end: CGPoint(x: 600, y: 120), color: red, width: 8)),
            SlideAnnotation(content: .text("SICHTBARER FOLIENTEXT", frame: CGRect(x: 50, y: 200, width: 400, height: 40),
                                           style: SlideTextStyle(size: 24, bold: true), color: red))
        ]
        let exported = try PDFExporter.export(StudyProject(pdfData: pdf, pages: [0: notes]))
        let rendered = try RenderedPage(exported)
        #expect(rendered.isRed(x(100), y(40)))
        #expect(rendered.isRed(x(200), y(50)))
        #expect(!rendered.isRed(x(250), y(50)))
        #expect(rendered.isRed(x(400), y(40)))
        #expect(rendered.isRed(x(600), y(70)))
        #expect(!rendered.isRed(x(550), y(70)))
        // Real text, in the right place.
        let document = try #require(PDFDocument(data: exported))
        let page = try #require(document.page(at: 0))
        let selection = try #require(document.findString("SICHTBARER FOLIENTEXT", withOptions: []).first)
        let bounds = selection.bounds(for: page)
        #expect(abs(bounds.minX - x(50)) < 3)
        #expect(bounds.maxY <= y(200) + 2)
        #expect(bounds.minY >= y(240) - 2)
    }

    @Test func underlineIsDrawn() throws {
        var plain = SlideTextStyle(size: 30)
        func image(_ style: SlideTextStyle) throws -> Int {
            let context = try #require(CGContext(data: nil, width: 300, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let annotation = SlideAnnotation(content: .text("xxx", frame: CGRect(x: 0, y: 0, width: 300, height: 60), style: style, color: red))
            AnnotationRenderer.draw([annotation], in: context, slideSize: CGSize(width: 300, height: 60), target: CGRect(x: 0, y: 0, width: 300, height: 60))
            let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
            return (0..<context.height * context.bytesPerRow).filter { bytes[$0] > 128 }.count
        }
        let without = try image(plain)
        plain.underline = true
        #expect(try image(plain) > without)
    }

    @Test func savedPDFRestoresAnnotationsWithoutAlteringTheOriginal() throws {
        let original = try lecturePDF()
        var notes = PageNotes()
        notes.annotations = [
            SlideAnnotation(content: .image(try solidImage(.red), frame: CGRect(x: 10, y: 10, width: 50, height: 50))),
            SlideAnnotation(content: .text("Text", frame: CGRect(x: 10, y: 80, width: 100, height: 30), style: SlideTextStyle(), color: red))
        ]
        let saved = try PDFExporter.export(StudyProject(title: "Test", pdfData: original, pages: [0: notes]))
        let reopened = try StudyPDF.open(saved)
        #expect(reopened.pages[0] == notes)
        #expect(reopened.pdfData == original)
        #expect(reopened.version == StudyProject.currentVersion)
    }

    @Test func thumbnailShowsAnnotationsInTheRightCorner() throws {
        let document = try #require(PDFDocument(data: lecturePDF(rotation: 90)))
        let page = try #require(document.page(at: 0))
        let square = SlideAnnotation(content: .image(try solidImage(.red), frame: CGRect(x: 0, y: 0, width: 180, height: 320)))
        let image = AnnotationRenderer.thumbnail(of: page, annotations: [square], size: CGSize(width: 90, height: 160))
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let (width, height) = (bitmap.pixelsWide, bitmap.pixelsHigh)
        let topLeft = try #require(bitmap.colorAt(x: width / 4, y: height / 4)?.usingColorSpace(.sRGB))
        let bottomRight = try #require(bitmap.colorAt(x: width * 3 / 4, y: height * 3 / 4)?.usingColorSpace(.sRGB))
        #expect(topLeft.redComponent > 0.8 && topLeft.greenComponent < 0.3)
        #expect(bottomRight.greenComponent > 0.8)
    }
}
