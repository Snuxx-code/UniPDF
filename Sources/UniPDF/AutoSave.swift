import AppKit
import SwiftUI
import UniPDFCore

/// Saving by itself, as in the web app: every 15 seconds while there are changes, and when UniPDF goes to
/// the background. Only a document that already has its file; a new one waits for ⌘S, so that no save panel
/// opens by itself. Switched in File → Save Automatically; on by default.
enum AutoSave {
    static let key = "autoSave"
    static let interval: TimeInterval = 15
    static var isOn: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
    /// Posted when Claude changed a lecture: it is saved a moment later, also while UniPDF is in the background.
    static let changedByClaude = Notification.Name("UniPDFChangedByClaude")

    /// When a key was last pressed in UniPDF. Saving waits for a pause in typing: a save takes a moment,
    /// and what is typed meanwhile must not be counted as saved.
    @MainActor static var lastKey = Date.distantPast
    @MainActor private static var monitor: Any?
    @MainActor static func watchTyping() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            lastKey = Date()
            return event
        }
    }
}

/// The menu item in the File menu, after Save.
struct AutoSaveCommands: Commands {
    @AppStorage(AutoSave.key) private var autoSave = true

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Toggle("Save Automatically", isOn: $autoSave)
        }
    }
}

/// Saves the document of its window by itself and reports while it does.
struct AutoSaver: NSViewRepresentable {
    /// Counts every change to the document, so that one made while a save runs keeps it unsaved.
    let revision: () -> Int
    let onSaving: (Bool) -> Void

    func makeNSView(context: Context) -> NSView { SaverView(revision: revision, onSaving: onSaving) }
    func updateNSView(_ view: NSView, context: Context) {
        (view as? SaverView)?.onSaving = onSaving
        (view as? SaverView)?.revision = revision
    }

    private final class SaverView: NSView {
        var revision: () -> Int
        var onSaving: (Bool) -> Void
        private var timer: Timer?
        private var saving = false

        init(revision: @escaping () -> Int, onSaving: @escaping (Bool) -> Void) {
            self.revision = revision
            self.onSaving = onSaving
            super.init(frame: .zero)
            AutoSave.watchTyping()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            timer?.invalidate()
            timer = nil
            guard window != nil else { return }
            let timer = Timer(timeInterval: AutoSave.interval, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.saveIfNeeded() } }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            NotificationCenter.default.addObserver(self, selector: #selector(saveOnLeaving),
                                                   name: NSApplication.willResignActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(saveSoon),
                                                   name: AutoSave.changedByClaude, object: nil)
        }

        private var soon: Timer?

        /// After a change by Claude: one save shortly after the last of a run of changes.
        @objc private func saveSoon() {
            soon?.invalidate()
            let timer = Timer(timeInterval: 2, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.saveIfNeeded() } }
            RunLoop.main.add(timer, forMode: .common)
            soon = timer
        }

        /// Leaving UniPDF ends the typing, so it saves at once.
        @objc private func saveOnLeaving() { saveIfNeeded(waitForPause: false) }

        @objc private func saveIfNeeded() { saveIfNeeded(waitForPause: true) }

        private func saveIfNeeded(waitForPause: Bool) {
            guard AutoSave.isOn, !saving, let window,
                  let document = NSDocumentController.shared.document(for: window),
                  document.isDocumentEdited, let url = document.fileURL, let type = document.fileType else { return }
            // In the middle of a sentence it waits until the typing pauses.
            if waitForPause, Date().timeIntervalSince(AutoSave.lastKey) < 2 {
                saveSoon()
                return
            }
            saving = true
            report(true)
            let started = Date()
            let before = revision()
            document.save(to: url, ofType: type, for: .saveOperation) { [weak self] _ in
                // What changed while the file was written is not in it: the document stays unsaved, so that
                // it is saved next time and macOS does not load the older file over it, as it would where a
                // synced folder such as OneDrive touches the file after the save.
                if let self, self.revision() != before { document.updateChangeCount(.changeDone) }
                // Shown at least a moment, so that a quick save does not merely flicker.
                let rest = max(0, 0.8 - Date().timeIntervalSince(started))
                DispatchQueue.main.asyncAfter(deadline: .now() + rest) {
                    self?.saving = false
                    self?.report(false)
                }
            }
        }

        private func report(_ value: Bool) {
            DispatchQueue.main.async { [weak self] in self?.onSaving(value) }
        }
    }
}

/// Shown beside the lecture's name while it saves by itself: a short bar filled with the brand gradient,
/// which runs through it. Still where motion is reduced.
struct AutoSaveBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var running = false
    private let width: CGFloat = 30

    var body: some View {
        let stops = BrandMark.gradient.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        // Two periods of green, teal, blue and back, side by side: moving by one period loops without a seam.
        let period = [stops[0], stops[1], stops[2], stops[1]]
        LinearGradient(colors: period + period + [stops[0]], startPoint: .leading, endPoint: .trailing)
            .frame(width: width * 2, height: 4)
            .offset(x: running ? -width : 0)
            .frame(width: width, height: 4, alignment: .leading)
            .clipShape(Capsule())
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { running = true }
            }
    }
}
