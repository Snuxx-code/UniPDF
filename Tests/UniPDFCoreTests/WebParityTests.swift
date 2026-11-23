import AppKit
import Foundation
import Testing
@testable import UniPDFCore

/// What the Mac app took over from the web app: growing text boxes and the study PDF's portrait layout.
struct WebParityTests {
    private let red = AnnotationColor(red: 1, green: 0, blue: 0)

    @Test func growingTextBoxesReadAndWriteAsInTheWebApp() throws {
        let box = SlideAnnotation(content: .text("Hallo", frame: CGRect(x: 10, y: 20, width: 80, height: 24),
                                                 style: SlideTextStyle(), color: red, autoWidth: true))
        let json = String(decoding: try JSONEncoder().encode(box), as: UTF8.self)
        #expect(json.contains("\"autoWidth\":true"))
        #expect(try JSONDecoder().decode(SlideAnnotation.self, from: Data(json.utf8)) == box)

        // A box from before, or one made on the Mac with a fixed width, carries no flag at all.
        let fixed = SlideAnnotation(content: .text("Fest", frame: CGRect(x: 0, y: 0, width: 80, height: 24), style: SlideTextStyle(), color: red))
        #expect(!String(decoding: try JSONEncoder().encode(fixed), as: UTF8.self).contains("autoWidth"))
    }

    @Test func aWidthSetByHandStopsTheGrowing() {
        let box = SlideAnnotation(content: .text("Hallo", frame: CGRect(x: 10, y: 20, width: 80, height: 24),
                                                 style: SlideTextStyle(), color: red, autoWidth: true))
        guard case .text(_, _, _, _, let moved) = box.moved(by: CGVector(dx: 5, dy: 5)).content,
              case .text(_, _, _, _, let taller) = box.resized(to: CGRect(x: 10, y: 20, width: 80, height: 60)).content,
              case .text(_, _, _, _, let narrower) = box.resized(to: CGRect(x: 10, y: 20, width: 50, height: 60)).content
        else { Issue.record("Not a text box"); return }
        #expect(moved == true)
        #expect(taller == true)
        #expect(narrower == nil)
    }

    @Test func portraitSlidesFillThePageHeightAndLandscapeOnesStay() {
        let portrait = PDFExporter.Layout.for(CGSize(width: 595.28, height: 841.89), page: PDFExporter.pageSize)
        #expect(portrait.fills && !portrait.labelsOverSlide)
        #expect(abs(portrait.slide.height - PDFExporter.pageSize.height) < 0.01)
        #expect(portrait.slide.minX == 0)
        #expect(portrait.column.minX > portrait.slide.maxX)
        #expect(portrait.column.maxX <= PDFExporter.pageSize.width - 32 + 0.01)

        let landscape = PDFExporter.Layout.for(CGSize(width: 960, height: 540), page: PDFExporter.pageSize)
        #expect(!landscape.fills && landscape.labelsOverSlide)
        #expect(landscape.slide == CGRect(x: 32, y: 72, width: 460, height: 428))
    }

    @Test func growingBoxesMeasureTheirLongestLine() {
        let style = SlideTextStyle(size: 20)
        let short = AnnotationRenderer.textWidth("Hi", style: style)
        let long = AnnotationRenderer.textWidth("Hi\nein deutlich längerer Satz", style: style)
        #expect(short > 0 && long > short * 4)
    }
}
