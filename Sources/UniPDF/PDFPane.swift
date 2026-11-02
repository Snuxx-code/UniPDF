import SwiftUI
import PDFKit

@Observable
final class PDFSession {
    var document: PDFDocument?
    weak var view: PDFView?
    var selection = 0
    var showsSidebar = true

    func move(_ offset: Int) {
        guard let document else { return }
        selection = min(max(selection + offset, 0), document.pageCount - 1)
    }
}

struct PDFPane: NSViewRepresentable {
    let session: PDFSession

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.displayDirection = .horizontal
        view.autoScales = true
        view.minScaleFactor = 0.15
        view.maxScaleFactor = 6
        view.backgroundColor = .windowBackgroundColor
        view.document = session.document
        session.view = view
        context.coordinator.session = session
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)),
                                               name: .PDFViewPageChanged, object: view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== session.document { view.document = session.document }
        if let page = session.document?.page(at: session.selection), view.currentPage !== page { view.go(to: page) }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
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
