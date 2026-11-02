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
            // Only a dragged divider names its index. Every other change is the window around it.
            if notification.userInfo?["NSSplitViewDividerIndex"] != nil, let width = splitView?.arrangedSubviews.last?.frame.width {
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
            guard width > 0, let splitView, let editor = splitView.arrangedSubviews.last else { return }
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
