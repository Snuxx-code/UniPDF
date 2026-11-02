import SwiftUI
import PDFKit
import UniPDFCore

@Observable
final class PDFSession {
    var document: PDFDocument?
    weak var view: PDFView?
    var selection = 0
    var showsSidebar = true
    var tool = AnnotationTool.select { didSet { overlay?.toolDidChange() } }
    var lastShape = SlideShape.rectangle
    /// Defaults for new annotations, and what the bar shows for the selected one.
    var style = AnnotationStyle()
    var selectedAnnotation: UUID?
    /// What the selected annotation is, so the bar offers the fitting settings.
    var selectedKind: AnnotationKind?
    var annotationError: String?
    weak var overlay: AnnotationOverlayView?

    /// A slide with the longest side of 960 points is the base for default stroke widths and font sizes.
    var slideUnit: Double {
        guard let page = document?.page(at: selection) else { return 1 }
        let size = page.displayedSlideSize
        return max(max(size.width, size.height) / 960, 0.1)
    }

    /// Sizes the defaults to the lecture's slides, which come in any size.
    func adaptStyleToSlides() {
        style.lineWidth = 2 * slideUnit
        style.text.size = (24 * slideUnit).rounded()
    }

    func move(_ offset: Int) {
        guard let document else { return }
        selection = min(max(selection + offset, 0), document.pageCount - 1)
    }
}

struct PDFPane: NSViewRepresentable {
    let session: PDFSession
    @Binding var annotations: [SlideAnnotation]

    func makeNSView(context: Context) -> SlideCanvasView {
        let canvas = SlideCanvasView(session: session)
        let view = canvas.pdfView
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.minScaleFactor = 0.15
        view.maxScaleFactor = 6
        view.backgroundColor = .windowBackgroundColor
        view.document = session.document
        // Last: the settings above turn it off again, and the slide would no longer fit its pane.
        view.autoScales = true
        session.view = view
        session.overlay = canvas.overlay
        context.coordinator.session = session
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)),
                                               name: .PDFViewPageChanged, object: view)
        return canvas
    }

    func updateNSView(_ canvas: SlideCanvasView, context: Context) {
        let view = canvas.pdfView
        if view.document !== session.document { view.document = session.document }
        if let page = session.document?.page(at: session.selection), view.currentPage !== page { view.go(to: page) }
        let binding = $annotations
        canvas.overlay.show(annotations, pageIndex: session.selection) { binding.wrappedValue = $0 }
    }

    static func dismantleNSView(_ canvas: SlideCanvasView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var session: PDFSession?
        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView, let page = view.currentPage,
                  let session, let document = view.document else { return }
            let index = document.index(for: page)
            // PDFKit can notify during a SwiftUI update. Deliver the binding update afterwards.
            Task { @MainActor [weak session] in
                guard session?.document === document else { return }
                if session?.selection != index { session?.selection = index }
            }
        }
    }
}
