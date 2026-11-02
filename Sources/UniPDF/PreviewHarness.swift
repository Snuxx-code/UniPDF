import AppKit
import CoreText
import SwiftUI
import UniPDFCore

@main
struct UniPDFLauncher {
    static func main() {
        if CommandLine.arguments.contains("--preview") {
            do { try PreviewHarness.run() }
            catch { fputs("Preview failed: \(error.localizedDescription)\n", stderr); exit(1) }
        } else { UniPDFApp.main() }
    }
}

/// An explicit development command; never changes a user's projects or preferences.
enum PreviewHarness {
    static func run() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/Preview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let project = try demoProject()
        try project.encoded().write(to: directory.appendingPathComponent("Beispiel.unipdf"))
        try PDFExporter.export(project).write(to: directory.appendingPathComponent("Beispiel-Lernskript.pdf"))
        let store = try demoLibrary(in: directory, pdf: PDFExporter.export(project, includingProject: false))
        for (name, document, size, appearance) in [
            ("welcome", StudyDocument(), NSSize(width: 1200, height: 780), NSAppearance.Name.aqua),
            ("workspace", StudyDocument(project: project), NSSize(width: 1320, height: 850), NSAppearance.Name.aqua),
            ("workspace-dark", StudyDocument(project: project), NSSize(width: 1000, height: 740), NSAppearance.Name.darkAqua)
        ] {
            let sourceURL = document.project.pdfData == nil ? nil : directory.appendingPathComponent("Beispiel.unipdf")
            try capture(WorkspaceView(document: .constant(document), fileURL: sourceURL, fileStore: store), name: name,
                        size: size, appearance: appearance, directory: directory)
        }
        let context = try AIQuestionContext.create(project: project,
            sourceURL: directory.appendingPathComponent("Beispiel.unipdf"), slideIndex: 0)
        try capture(AIPromptPopover(context: context, copy: { _ in true }), name: "ai-prompt",
                    size: NSSize(width: 520, height: 580), appearance: .aqua, directory: directory)
        try capture(LibraryView(store: store), name: "library", size: NSSize(width: 720, height: 560),
                    appearance: .aqua, directory: directory, settle: 3)
        try capture(LibraryView(store: store), name: "library-dark", size: NSSize(width: 720, height: 560),
                    appearance: .darkAqua, directory: directory, settle: 3)
        // A separate suite, so the list capture leaves the user's chosen view untouched.
        let suiteName = "de.unipdf.preview"
        if let suite = UserDefaults(suiteName: suiteName) {
            suite.set(LibraryViewMode.list.rawValue, forKey: "libraryViewMode")
            try capture(LibraryView(store: store).defaultAppStorage(suite), name: "library-list",
                        size: NSSize(width: 720, height: 560), appearance: .aqua, directory: directory, settle: 3)
            suite.removePersistentDomain(forName: suiteName)
        }
        print("Preview artifacts: \(directory.path)")
    }

    private static func capture(_ view: some View, name: String, size: NSSize,
                                appearance: NSAppearance.Name, directory: URL, settle: TimeInterval = 0.6) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.setContentSize(size)
        host.frame = NSRect(origin: .zero, size: size)
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        host.layoutSubtreeIfNeeded()
        window.display()
        host.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { throw ProjectError.exportFailed }
        bitmap.size = size
        guard host.bounds.width >= size.width, host.bounds.height >= size.height else {
            throw NSError(domain: "UniPDF.Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "Offscreen layout failed: \(host.bounds)"])
        }
        host.cacheDisplay(in: NSRect(origin: .zero, size: size), to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ProjectError.exportFailed }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        window.orderOut(nil)
    }

    private static func demoLibrary(in directory: URL, pdf: Data) throws -> LibraryStore {
        let root = directory.appendingPathComponent("Beispiel-Bibliothek", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        let semester = root.appendingPathComponent("Semester 1", isDirectory: true)
        try FileManager.default.createDirectory(at: semester, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Semester 2", isDirectory: true), withIntermediateDirectories: true)
        try pdf.write(to: semester.appendingPathComponent("Beispiel Vorlesung.pdf"))
        try pdf.write(to: root.appendingPathComponent("Beispiel Vorlesung 1.pdf"))
        try pdf.write(to: root.appendingPathComponent("Beispiel Vorlesung 2.pdf"))
        try Data("Beispielnotiz".utf8).write(to: root.appendingPathComponent("Beispiel Notizen.txt"))
        return LibraryStore(root: root)
    }

    private static func demoProject() throws -> StudyProject {
        let output = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 960, height: 540)
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw ProjectError.exportFailed
        }
        let slides = [
            ("Lineare Algebra", "Vektorräume & lineare Abbildungen", "Beispielvorlesung · Keine echten Kursunterlagen"),
            ("Was ist ein Vektorraum?", "Eine Menge mit zwei Operationen.", "Vektoraddition  u + v     ·     Skalarmultiplikation  λ · v"),
            ("Lineare Abbildungen", "Struktur bleibt erhalten.", "f(u + v) = f(u) + f(v)     ·     f(λv) = λf(v)")
        ]
        for (title, subtitle, detail) in slides {
            context.beginPDFPage(nil)
            context.setFillColor(NSColor.white.cgColor); context.fill(box)
            func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = .black) {
                let value = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
                context.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(CTLineCreateWithAttributedString(value), context)
            }
            label(title, x: 65, y: 400, size: 47)
            label(subtitle, x: 65, y: 330, size: 25, color: .darkGray)
            label(detail, x: 65, y: 180, size: 20, color: .darkGray)
            context.setFillColor(NSColor(srgbRed: 0.16, green: 0.4, blue: 0.34, alpha: 1).cgColor)
            context.fill(CGRect(x: 65, y: 275, width: 72, height: 4))
            label("DEMOMATERIAL · UniPDF", x: 65, y: 45, size: 13, color: .darkGray)
            context.endPDFPage()
        }
        context.closePDF()
        var notes = PageNotes()
        notes.text = "Die Grundidee\nEin Vektor beschreibt mehr als eine Richtung. Auch Funktionen oder Polynome können Vektoren sein.\n\nMerken\nEntscheidend sind die Rechenregeln, nicht die Darstellung.\n\nOffene Frage\nWann bilden zwei Vektoren eine Basis?"
        notes.formula = "f(u + v) = f(u) + f(v)"
        notes.drawing = [
            InkElement(tool: .arrow, color: .graphite, points: [InkPoint(x: 100, y: 410), InkPoint(x: 100, y: 60)]),
            InkElement(tool: .arrow, color: .graphite, points: [InkPoint(x: 100, y: 410), InkPoint(x: 710, y: 410)]),
            InkElement(tool: .arrow, color: .blue, width: 5, points: [InkPoint(x: 100, y: 410), InkPoint(x: 510, y: 150)]),
            InkElement(tool: .arrow, color: .green, width: 5, points: [InkPoint(x: 100, y: 410), InkPoint(x: 300, y: 110)])
        ]
        return StudyProject(title: "Lineare Algebra · Beispiel", pdfData: output as Data, pages: [0: notes])
    }
}
