import AppKit
import PDFKit

/// Intercepts arrows before PDFKit's inner document view scrolls them.
/// The monitor belongs to one canvas and leaves text editing and annotation nudging alone.
final class PDFArrowKeyNavigation {
    private weak var canvas: NSView?
    private weak var session: PDFSession?
    private var monitor: Any?

    init(canvas: NSView, session: PDFSession) {
        self.canvas = canvas
        self.session = session
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) == true }
            return handled ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    static func offset(for event: NSEvent) -> Int? {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return nil }
        switch event.keyCode {
        case 123, 126: return -1 // left, up
        case 124, 125: return 1  // right, down
        default: return nil
        }
    }

    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        handle(event, in: event.window)
    }

    /// The source window is explicit so routing can also be tested without a WindowServer.
    @discardableResult
    func handle(_ event: NSEvent, in eventWindow: NSWindow?) -> Bool {
        guard let offset = Self.offset(for: event), let canvas, let session,
              let window = canvas.window, eventWindow === window, window.attachedSheet == nil,
              !canvas.isHiddenOrHasHiddenAncestor,
              NSEvent.pressedMouseButtons == 0, session.selectedAnnotation == nil,
              let document = session.document, document.pageCount > 0,
              let view = session.view, view.document === document else { return false }

        let responder = window.firstResponder
        if responder is NSTextView || responder is NSTextField { return false }
        if let view = responder as? NSView {
            // PDF/annotation focus, or an otherwise unfocused document hosting view.
            // Sidebar lists, controls and the right-hand editor are separate branches.
            guard view === canvas || view.isDescendant(of: canvas) || canvas.isDescendant(of: view) else { return false }
        } else if let responder, responder !== window {
            return false
        }

        session.move(offset)
        if let page = document.page(at: session.selection), view.currentPage !== page {
            view.go(to: page)
        }
        // Consume arrows at the first/last slide too, avoiding an unexpected scroll there.
        return true
    }
}
