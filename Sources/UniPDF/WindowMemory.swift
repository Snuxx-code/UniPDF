import AppKit
import SwiftUI

/// Restores a window's last frame and keeps it up to date. New windows of the same kind start there.
struct WindowFrameMemory: NSViewRepresentable {
    let key: String

    func makeNSView(context: Context) -> NSView { MemoryView(key: key) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class MemoryView: NSView {
        private let key: String
        private var isConfigured = false

        init(key: String) {
            self.key = key
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !isConfigured else { return }
            isConfigured = true
            // Afterwards, because SwiftUI applies its default size when the window first appears.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                if let saved = UserDefaults.standard.string(forKey: self.key) { window.setFrame(from: saved) }
                for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(self.frameChanged), name: name, object: window)
                }
            }
        }

        @objc private func frameChanged() {
            // The full screen frame is not the size to come back to.
            guard let window, !window.styleMask.contains(.fullScreen) else { return }
            UserDefaults.standard.set(window.frameDescriptor, forKey: key)
        }
    }
}

/// Keeps the notes pane at the width the student dragged it to: across launches, across all open
/// tabs, and when the window or sidebar changes size. Place inside the split view's trailing pane.
struct EditorWidthMemory: NSViewRepresentable {
    static let key = "editorPaneWidth"
    static let minimumEditorWidth: CGFloat = 350
    static let minimumPDFWidth: CGFloat = 360

    /// Where the divider belongs for a width. The width gives way while the window is too small for it.
    static func dividerPosition(totalWidth: CGFloat, editorWidth: CGFloat, dividerThickness: CGFloat) -> CGFloat {
        let width = max(editorWidth, minimumEditorWidth)
        return max(totalWidth - width - dividerThickness, minimumPDFWidth)
    }

    func makeNSView(context: Context) -> NSView { MemoryView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class MemoryView: NSView {
        private static let widthChanged = Notification.Name("de.unipdf.editorWidthChanged")
        private weak var splitView: NSSplitView?
        private var isApplying = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, splitView == nil else { return }
            DispatchQueue.main.async { [weak self] in self?.connect() }
        }

        private func connect() {
            let ancestors = sequence(first: self as NSView, next: \.superview)
            guard splitView == nil, let found = ancestors.lazy.compactMap({ $0 as? NSSplitView }).first else { return }
            splitView = found
            NotificationCenter.default.addObserver(self, selector: #selector(splitChanged(_:)),
                                                   name: NSSplitView.didResizeSubviewsNotification, object: found)
            NotificationCenter.default.addObserver(self, selector: #selector(otherPaneChanged),
                                                   name: Self.widthChanged, object: nil)
            apply()
        }

        @objc private func splitChanged(_ notification: Notification) {
            guard !isApplying else { return }
            // Only a divider dragged by hand changes the remembered width. Every other change, such as the window
            // resizing or the notes being hidden and shown again, gets the remembered width back.
            let dragged = [.leftMouseDragged, .leftMouseUp].contains(NSApp.currentEvent?.type)
            if notification.userInfo?["NSSplitViewDividerIndex"] != nil, dragged, let splitView, splitView.arrangedSubviews.count >= 2,
               let width = splitView.arrangedSubviews.last?.frame.width {
                UserDefaults.standard.set(Double(width), forKey: EditorWidthMemory.key)
                NotificationCenter.default.post(name: Self.widthChanged, object: self)
            } else {
                apply()
            }
        }

        @objc private func otherPaneChanged(_ notification: Notification) {
            if notification.object as AnyObject? !== self { apply() }
        }

        private func apply() {
            let width = UserDefaults.standard.double(forKey: EditorWidthMemory.key)
            guard width > 0, let splitView, splitView.arrangedSubviews.count >= 2, let editor = splitView.arrangedSubviews.last else { return }
            let position = EditorWidthMemory.dividerPosition(totalWidth: splitView.bounds.width, editorWidth: width,
                                                             dividerThickness: splitView.dividerThickness)
            let current = editor.frame.minX - splitView.dividerThickness
            guard abs(position - current) > 0.5 else { return }
            isApplying = true
            splitView.setPosition(position, ofDividerAt: 0)
            isApplying = false
        }
    }
}

/// Hides the window's own title beside the toolbar's leading buttons. Tabs keep showing the file name.
struct HiddenWindowTitle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitleView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class TitleView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.titleVisibility = .hidden
        }
    }
}

/// Reports whether the document in this window has unsaved changes, as the window's close button shows it.
struct DocumentEditedObserver: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView { ObserverView(onChange: onChange) }
    func updateNSView(_ view: NSView, context: Context) { (view as? ObserverView)?.onChange = onChange }

    private final class ObserverView: NSView {
        var onChange: (Bool) -> Void
        private var reported: Bool?
        private var timer: Timer?

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            timer?.invalidate()
            timer = nil
            guard let window else { return }
            // The edited flag is not observable. A window update catches changes at once while the app is
            // active; the timer also catches saves and changes while it is in the background.
            NotificationCenter.default.addObserver(self, selector: #selector(check), name: NSWindow.didUpdateNotification, object: window)
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.check() } }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            check()
        }

        @objc private func check() {
            guard let window else { return }
            let edited = NSDocumentController.shared.document(for: window)?.isDocumentEdited ?? window.isDocumentEdited
            guard edited != reported else { return }
            reported = edited
            // The update runs inside AppKit's own cycle; SwiftUI state changes wait for it to end.
            DispatchQueue.main.async { [weak self] in self?.onChange(edited) }
        }
    }
}
