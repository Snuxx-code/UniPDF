import SwiftUI

struct UniPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        DocumentGroup(newDocument: StudyDocument()) { file in
            WorkspaceView(document: file.$document, fileURL: file.fileURL)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .defaultSize(width: 1320, height: 850)
        .commands {
            CommandGroup(replacing: .help) {
                Button("UniPDF-Hilfe") {
                    let alert = NSAlert()
                    alert.messageText = "Deine Vorlesung. Deine Gedanken."
                    alert.informativeText = "1. Öffne dein Vorlesungs-PDF mit ⌘O oder „Vorlesungs-PDF öffnen“.\n2. Wähle links eine Folie und schreibe rechts deine Notizen. Unter „Formel“ und „Skizze“ kannst du weitere Inhalte ergänzen.\n3. ⌘S aktualisiert die geöffnete Datei am selben Speicherort. Bei einer PDF wird die ursprüngliche Datei durch Folien mit Mitschriften ersetzt.\n4. Die PDF enthält auch die bearbeitbaren Inhalte. Öffne sie wieder in UniPDF, um weiterzuschreiben. „Lern-PDF exportieren“ erstellt eine zusätzliche Kopie.\n\nBestehende .unipdf-Projekte bleiben unterstützt und werden ebenfalls an ihrem bisherigen Ort aktualisiert.\n\nFormeln: x^{2}, a_{n}, \\frac{a}{b}, \\sqrt{x}, \\alpha, \\sum und \\int. Einfache Notation, kein vollständiges LaTeX.\n\nAlles bleibt lokal auf deinem Mac."
                    alert.runModal()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
