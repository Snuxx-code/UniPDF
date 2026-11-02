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
            CommandGroup(replacing: .help) {
                Button("UniPDF-Hilfe") {
                    let alert = NSAlert()
                    alert.messageText = "Deine Vorlesung. Deine Gedanken."
                    alert.informativeText = "1. Öffne dein Vorlesungs-PDF mit ⌘O oder „Vorlesungs-PDF öffnen“.\n2. Wähle links eine Folie und schreibe rechts deine Notizen. Unter „Formel“ und „Skizze“ kannst du weitere Inhalte ergänzen.\n3. ⌘S aktualisiert die geöffnete Datei am selben Speicherort. Bei einer PDF wird die ursprüngliche Datei durch Folien mit Mitschriften ersetzt.\n4. Die PDF enthält auch die bearbeitbaren Inhalte. Öffne sie wieder in UniPDF, um weiterzuschreiben. „Lern-PDF exportieren“ erstellt eine zusätzliche Kopie.\n\nOhne Datei gestartet öffnet UniPDF die zuletzt geöffnete Datei oder, falls es keine mehr gibt, die Bibliothek.\n\nBibliothek (⇧⌘L): Gib Zugriff auf einen Ordner und ordne darin Unterordner und Dateien. Doppelklick geht in einen Ordner. Ziehe Einträge auf einen Ordner oder auf den Pfad oben, um sie zu verschieben. Im Viewer findest du dieselben Dateien auch in der Seitenleiste unter „Dateien“.\n\nAuf der Folie: Die Leiste über der Folie bietet Stift, Textfeld, Formen und Bilder. Mit dem Pfeil wählst, verschiebst und vergrößerst du sie, ⌫ löscht. Sie bleiben beim Speichern bearbeitbar und erscheinen im Lern-PDF.\n\nMehrere Dateien liegen als Tabs in einem Fenster. Rechtsklick auf einen Tab bewegt ihn in ein neues Fenster.\n\nBestehende .unipdf-Projekte bleiben unterstützt und werden ebenfalls an ihrem bisherigen Ort aktualisiert.\n\nFormeln: x^{2}, a_{n}, \\frac{a}{b}, \\sqrt{x}, \\alpha, \\sum und \\int. Einfache Notation, kein vollständiges LaTeX.\n\nAlles bleibt lokal auf deinem Mac."
                    alert.runModal()
                }
            }
        }

        Window("Bibliothek", id: LibraryCommands.windowID) {
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
            Button("Bibliothek") { openWindow(id: Self.windowID) }
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
