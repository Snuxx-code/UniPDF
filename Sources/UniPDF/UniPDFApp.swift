import SwiftUI

struct UniPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        DocumentGroup(newDocument: StudyDocument()) { file in
            WorkspaceView(document: file.$document, fileURL: file.fileURL)
                .frame(minWidth: 1000, minHeight: 680)
                .background(WindowTabbing(group: WindowTabbing.documents))
                .background(WindowFrameMemory(key: "documentWindowFrame"))
                .task(id: file.fileURL) { AppDelegate.remember(file.fileURL) }
        }
        .defaultSize(width: 1320, height: 850)
        .commands {
            LibraryCommands()
            DocumentSearchCommands()
            CommandGroup(replacing: .help) {
                Button("UniPDF Help") {
                    let alert = NSAlert()
                    alert.messageText = String(localized: "Your lecture. Your thoughts.")
                    alert.informativeText = String(localized: "1. Open your lecture PDF with ⌘O or “Open Lecture PDF”.\n2. Choose a slide on the left and write your notes on the right. “Formula” and “Sketch” add more.\n3. ⌘S updates the open file in the same place. For a PDF, the original file is replaced by the slides with your notes.\n4. The PDF also holds the editable content. Open it in UniPDF again to keep writing. “Export Study PDF” creates an additional copy.\n\nStarted without a file, UniPDF opens the file you opened last or, if it no longer exists, the library.\n\nLibrary (⇧⌘L): give access to a folder and organize its subfolders and files. Double-click to go into a folder. Drag items onto a folder or onto the path at the top to move them. In the viewer, the same files are in the sidebar under “Files”.\n\nOn the slide: the tools above the slide offer a pen, text boxes, shapes and images. The arrow selects, moves and resizes them, ⌫ deletes. They stay editable when you save and appear in the study PDF.\n\nSeveral files share one window as tabs. Right-click a tab to move it to a new window.\n\nExisting .unipdf projects are still supported and are also updated in their current place.\n\nFormulas: x^{2}, a_{n}, \\frac{a}{b}, \\sqrt{x}, \\alpha, \\sum and \\int. Simple notation, not full LaTeX.\n\nEverything stays local on your Mac.")
                    alert.informativeText += "\n\n" + String(localized: "Changing slides: in the PDF area, → or ↓ for the next slide, ← or ↑ for the previous one. In text fields the arrows still move the cursor, and they move selected annotations. Press Esc to deselect. ⌘↑ and ⌘↓ stay available.")
                    alert.informativeText += "\n\n" + String(localized: "Highlighter: turn on the highlighter above the slide and drag over PDF text. You can also select text first and then click the highlighter. Its color is chosen separately. Press Esc to return to the selection tool; click a highlight and press ⌫ to delete it. Highlights stay editable in the saved PDF.")
                    alert.informativeText += "\n\n" + String(localized: "Eraser: drag over pen strokes and highlights. “Precise” removes only what it touches, whole characters for highlights; “Stroke” deletes every stroke and highlight it touches entirely. Choose the mode and size in the row below the tools; ⌘Z takes back a whole stroke of the eraser. Click shapes, text boxes and images and press ⌫ to delete them.")
                    alert.runModal()
                }
            }
        }

        Window("Library", id: LibraryCommands.windowID) {
            LibraryView().frame(minWidth: 480, minHeight: 420)
                .background(WindowTabbing(group: nil))
                .background(WindowFrameMemory(key: "libraryWindowFrame"))
        }
        .defaultSize(width: 720, height: 560)
    }
}

struct LibraryCommands: Commands {
    static let windowID = "library"
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openDocument) private var openDocument

    var body: some Commands {
        // The app delegate has no environment, but needs these when starting without a file.
        let _ = AppDelegate.openLibrary = { [openWindow] in openWindow(id: Self.windowID) }
        let _ = AppDelegate.openFile = { [openDocument] url in try await openDocument(at: url) }
        CommandGroup(after: .newItem) {
            Button("Library") { openWindow(id: Self.windowID) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var openLibrary: (() -> Void)?
    static var openFile: ((URL) async throws -> Void)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Without this, a start without a file shows the system's open panel.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

    // Clicking the Dock icon with all windows closed behaves like a start without a file.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { Self.openLastFileOrLibrary() }
        return false
    }

    /// SwiftUI has opened an empty document by now when no file was asked for, and no API on
    /// macOS 14 turns that off. A start with a file or with restored windows has nothing to replace.
    private static func arrangeWindowsAfterLaunch(startedWithoutFile: Bool) {
        let documents = NSDocumentController.shared.documents
        let automatic = documents.filter { $0.fileURL == nil && !$0.isDocumentEdited }
        automatic.forEach { $0.close() }
        if startedWithoutFile, automatic.count == documents.count { openLastFileOrLibrary() }
    }

    private static let lastFileKey = "lastOpenedFileBookmark"

    // A bookmark, not the system's recent documents: it follows a moved file and survives a rebuild.
    static func remember(_ url: URL?) {
        guard let url, let bookmark = try? url.bookmarkData() else { return }
        UserDefaults.standard.set(bookmark, forKey: lastFileKey)
    }

    private static var lastFile: URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: lastFileKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path), !url.path.contains("/.Trash/") else { return nil }
        return url
    }

    private static func openLastFileOrLibrary() {
        guard let lastFile else {
            openLibrary?()
            return
        }
        Task {
            do { try await openFile?(lastFile) }
            catch { openLibrary?() }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // False when the app was started by opening a file, which only arrives after this point.
        let startedWithoutFile = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        DispatchQueue.main.async { Self.arrangeWindowsAfterLaunch(startedWithoutFile: startedWithoutFile) }
    }
}
