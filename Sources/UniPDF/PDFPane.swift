import SwiftUI
import PDFKit
import UniPDFCore

@Observable
final class PDFSession {
    var document: PDFDocument?
    weak var view: PDFView?
    var selection = 0
    var tool = AnnotationTool.select { didSet { overlay?.toolDidChange() } }
    var lastShape = SlideShape.rectangle
    /// Whether the text tool stays active after a text box, so that the next click starts another one.
    var keepsTextTool = UserDefaults.standard.bool(forKey: "keepsTextTool") {
        didSet { UserDefaults.standard.set(keepsTextTool, forKey: "keepsTextTool") }
    }
    /// Defaults for new annotations, and what the bar shows for the selected one.
    var style = AnnotationStyle()
    var selectedAnnotation: UUID?
    /// What the selected annotation is, so the bar offers the fitting settings.
    var selectedKind: AnnotationKind?
    var annotationError: String?
    /// While the mouse is down on the slide. Layout changes wait for its end, so the slide does not move under the pointer.
    var isGestureActive = false
    /// A search hit to show once its slide is on screen.
    var pendingReveal: SearchReveal?
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
        style.eraserRadius = 10 * slideUnit
        style.text.size = (24 * slideUnit).rounded()
    }

    func move(_ offset: Int) {
        guard let document, document.pageCount > 0 else { return }
        selection = min(max(selection + offset, 0), document.pageCount - 1)
    }

    func toggleTextToolLock() {
        keepsTextTool.toggle()
        // Locking while writing in a box: the next click already starts a new one.
        if keepsTextTool, tool == .select, selectedKind == .text { tool = .text }
    }

    func activateHighlighter() {
        tool = .highlight
        overlay?.highlightCurrentSelection()
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
        let keyboardNavigation = PDFArrowKeyNavigation(canvas: canvas, session: session)
        context.coordinator.keyboardNavigation = keyboardNavigation
        keyboardNavigation.start()
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
        // After the slide is shown: its annotations and text are the ones of the hit.
        if let reveal = session.pendingReveal, reveal.page == session.selection, reveal.source != .notes {
            let session = session
            DispatchQueue.main.async { [weak canvas] in
                guard session.pendingReveal == reveal else { return }
                session.pendingReveal = nil
                canvas?.reveal(reveal)
            }
        }
    }

    static func dismantleNSView(_ canvas: SlideCanvasView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.keyboardNavigation?.stop()
        coordinator.keyboardNavigation = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject {
        var session: PDFSession?
        var keyboardNavigation: PDFArrowKeyNavigation?
        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView, view.currentPage != nil,
                  session != nil, let document = view.document else { return }
            // PDFKit can notify during a SwiftUI update. Deliver the binding update afterwards.
            Task { @MainActor [weak self, weak view] in
                guard let view else { return }
                self?.synchronizeCurrentPage(in: view, document: document)
            }
        }

        func synchronizeCurrentPage(in view: PDFView, document: PDFDocument) {
            guard session?.document === document, view.document === document,
                  let currentPage = view.currentPage else { return }
            // Key repeats may have advanced again before a queued callback runs.
            let index = document.index(for: currentPage)
            if session?.selection != index { session?.selection = index }
        }
    }
}
