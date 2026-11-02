import AppKit
import SwiftUI

/// Puts document windows into one native tabbed window, whatever the system's tab preference says.
/// The tab bar's own menu then offers moving a tab to a new window. Without a group the window never tabs.
struct WindowTabbing: NSViewRepresentable {
    static let documents = "de.unipdf.documents"
    let group: String?

    func makeNSView(context: Context) -> NSView { TabbingView(group: group) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class TabbingView: NSView {
        private let group: String?
        // Only once: a tab the user moved to its own window must stay there.
        private var isConfigured = false

        init(group: String?) {
            self.group = group
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !isConfigured else { return }
            isConfigured = true
            guard let group else {
                window.tabbingMode = .disallowed
                return
            }
            window.tabbingIdentifier = group
            window.tabbingMode = .preferred
            // SwiftUI can attach this view after the window is on screen, too late for the mode alone.
            DispatchQueue.main.async { [weak window] in
                guard let window, window.tabbedWindows == nil || window.tabbedWindows?.count == 1 else { return }
                let others = NSApp.windows.filter { $0 !== window && $0.isVisible && $0.tabbingIdentifier == group }
                guard let target = others.first(where: \.isMainWindow) ?? others.first else { return }
                target.addTabbedWindow(window, ordered: .above)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
