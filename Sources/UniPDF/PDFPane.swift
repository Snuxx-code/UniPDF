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
    /// Whether the slides scroll by as one long document instead of one slide at a time. Kept across launches.
    var scrollsContinuously = UserDefaults.standard.bool(forKey: "scrollsContinuously") {
        didSet { UserDefaults.standard.set(scrollsContinuously, forKey: "scrollsContinuously") }
    }
    /// Set when the view itself made another slide current, by scrolling or by a click on it,
    /// so that the view does not jump to the slide's top.
    @ObservationIgnored var selectionFollowsView = false
    /// Set by the workspace: the annotations of any slide, for the slides around the current one while scrolling.
    @ObservationIgnored var pageAnnotations: ((Int) -> [SlideAnnotation])?
    @ObservationIgnored var setPageAnnotations: ((Int, [SlideAnnotation]) -> Void)?
    /// Set by the workspace: puts a new comment on the slide and its tag into the notes.
    var createComment: ((SlideAnnotation) -> Void)?
    /// Set by the workspace: opens a comment's card in the notes.
    var openComment: ((UUID) -> Void)?
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

    /// Comments selected text at once; without a selection, the comment tool waits for a passage or an area.
    func activateComment() {
        if overlay?.commentCurrentSelection() != true { tool = .comment }
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
        let continuous = session.scrollsContinuously
        let mode: PDFDisplayMode = continuous ? .singlePageContinuous : .singlePage
        if view.displayMode != mode {
            let page = session.document?.page(at: session.selection)
            view.displayMode = mode
            view.displayDirection = continuous ? .vertical : .horizontal
            view.autoScales = true
            if let page { view.go(to: page) }
            canvas.overlay.pageGeometryDidChange()
        }
        let followsView = session.selectionFollowsView
        session.selectionFollowsView = false
        if let page = session.document?.page(at: session.selection), view.currentPage !== page {
            if !continuous {
                view.go(to: page)
            } else if context.coordinator.shownSelection != session.selection {
                // While scrolling, only a slide chosen elsewhere, such as in the sidebar, is scrolled to.
                // One the view made current itself, by scrolling or a click on it, stays where it is.
                if !(followsView && view.visiblePages.contains(where: { $0 === page })) { view.go(to: page) }
            }
        }
        context.coordinator.shownSelection = session.selection
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
        /// The slide the view was last brought to, so that later updates do not move it again.
        var shownSelection: Int?
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
            if session?.selection != index {
                session?.selectionFollowsView = true
                session?.selection = index
            }
        }
    }
}
