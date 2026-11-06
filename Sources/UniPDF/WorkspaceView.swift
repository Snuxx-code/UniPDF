import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import UniPDFCore

struct WorkspaceView: View {
    @Binding var document: StudyDocument
    var fileURL: URL? = nil
    var fileStore: LibraryStore = .shared
    @State private var session = PDFSession()
    @State private var importing = false
    @State private var importSourceWindow: NSWindow?
    @State private var errorMessage: String?
    @State private var exportedURL: URL?
    @State private var aiPrompt: AIQuestionPrompt?
    @State private var showsAIPrompt = false
    @State private var showFormula = false
    @State private var showDrawing = false
    @State private var fontSize = 15.0
    @FocusState private var notesFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openDocument) private var openDocument
    @Environment(\.openWindow) private var openWindow

    private var accent: Color { Color.studyAccent(for: colorScheme) }

    private var notes: Binding<PageNotes> {
        let index = session.selection
        return Binding(
            get: { document.project.pages[index] ?? PageNotes() },
            set: { value in
                if value.isEmpty { document.project.pages.removeValue(forKey: index) }
                else { document.project.pages[index] = value }
                exportedURL = nil
            }
        )
    }

    var body: some View {
        Group {
            if let pdf = session.document { workspace(pdf) }
            else { welcome }
        }
        .tint(accent)
        .toolbar { toolbar }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            Task {
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    // Open as a native document so ⌘S targets this exact PDF URL.
                    try await openDocument(at: url)
                    if let window = importSourceWindow,
                       let emptyDocument = NSDocumentController.shared.document(for: window),
                       emptyDocument.fileURL == nil, !emptyDocument.isDocumentEdited {
                        emptyDocument.close()
                    }
                } catch { errorMessage = error.localizedDescription }
                importSourceWindow = nil
            }
        }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .onAppear {
            if session.document == nil, let data = document.project.pdfData {
                do {
                    session.document = try PDFExporter.validatedDocument(data: data)
                    session.adaptStyleToSlides()
                } catch { errorMessage = error.localizedDescription }
            }
            showFormula = !notes.wrappedValue.formula.isEmpty
            showDrawing = !notes.wrappedValue.drawing.isEmpty
        }
        .onChange(of: session.annotationError) {
            if let message = session.annotationError {
                errorMessage = message
                session.annotationError = nil
            }
        }
        .onChange(of: session.selection) {
            showFormula = !notes.wrappedValue.formula.isEmpty
            showDrawing = !notes.wrappedValue.drawing.isEmpty
        }
    }

    private var welcome: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Label("UniPDF", systemImage: "book.closed").font(.title3.weight(.semibold)).foregroundStyle(accent)
                Spacer()
                Text("Deine Vorlesung.\nDeine Gedanken.")
                    .font(.system(size: 43, weight: .semibold, design: .serif)).tracking(-1)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Folien lesen, Zusammenhänge verstehen und alles an einem Ort festhalten.")
                    .font(.title3).foregroundStyle(.secondary).lineSpacing(5).frame(maxWidth: 380, alignment: .leading)
                HStack(spacing: 12) {
                    Button { importSourceWindow = NSApp.keyWindow; importing = true } label: {
                        Label("Vorlesungs-PDF öffnen", systemImage: "plus").padding(.horizontal, 12).padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("i", modifiers: .command)
                    Button { openWindow(id: LibraryCommands.windowID) } label: {
                        Label("Bibliothek", systemImage: "folder").padding(.horizontal, 8).padding(.vertical, 7)
                    }
                    .help("Ordner mit deinen Vorlesungen verwalten (⇧⌘L)")
                }
                .controlSize(.large)
                Text("PDFs und vorhandene Projekte öffnest du auch mit ⌘O.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Label("Lokal auf deinem Mac", systemImage: "internaldrive").font(.callout).foregroundStyle(.secondary)
            }
            .padding(56).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 34) {
                welcomeStep("doc.text", "Vorlesungsfolien", "Importiere das PDF deiner Vorlesung. Jede Folie hat Platz für deine Gedanken.")
                welcomeStep("pencil.and.outline", "Mehr als Mitschreiben", "Ergänze Notizen, Formeln und Skizzen. Alles bleibt mit der passenden Folie verbunden.")
                welcomeStep("square.and.arrow.down", "Speichern und weiterlernen", "⌘S aktualisiert deine geöffnete PDF mit allen Mitschriften. In UniPDF bleibt sie weiter bearbeitbar.")
            }
            .padding(48).frame(width: 390, alignment: .leading).frame(maxHeight: .infinity)
            .background(accent.opacity(0.06))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func welcomeStep(_ symbol: String, _ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light)).foregroundStyle(accent).padding(.bottom, 4)
            Text(title).font(.headline)
            Text(body).font(.body).foregroundStyle(.secondary).lineSpacing(4)
        }
    }

    private func workspace(_ pdf: PDFDocument) -> some View {
        HStack(spacing: 0) {
            if session.showsSidebar {
                VStack(alignment: .leading, spacing: 0) {
                    FileTreeSection(store: fileStore, currentFile: fileURL)
                    Divider()
                    HStack {
                        Text("Folien").font(.headline)
                        Spacer()
                        Text("\(pdf.pageCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.padding(16)
                    Divider()
                    ScrollViewReader { proxy in
                        List(0..<pdf.pageCount, id: \.self, selection: Binding<Int?>(
                            get: { session.selection }, set: { if let value = $0 { session.selection = value } }
                        )) { index in
                            SlideRow(page: pdf.page(at: index), index: index,
                                     hasNotes: !(document.project.pages[index]?.isEmpty ?? true),
                                     annotations: document.project.pages[index]?.annotations ?? [])
                                .tag(index).id(index)
                        }
                        .listStyle(.sidebar)
                        .onChange(of: session.selection) { proxy.scrollTo(session.selection) }
                    }
                    Divider()
                    Text("\(document.project.pages.values.filter { !$0.isEmpty }.count) von \(pdf.pageCount) mit Mitschrift")
                        .font(.caption).foregroundStyle(.secondary).padding(14)
                }
                .frame(width: 178).background(.regularMaterial)
                Divider()
            }
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Label("Vorlesungsfolie", systemImage: "doc.richtext").font(.subheadline.weight(.medium))
                        Spacer()
                        Button { session.view?.zoomOut(nil) } label: { Image(systemName: "minus.magnifyingglass") }
                            .help("Verkleinern").accessibilityLabel("PDF verkleinern")
                        Button { session.view?.autoScales = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                            .help("An Fenster anpassen").accessibilityLabel("PDF an Fenster anpassen")
                        Button { session.view?.zoomIn(nil) } label: { Image(systemName: "plus.magnifyingglass") }
                            .help("Vergrößern").accessibilityLabel("PDF vergrößern")
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 47)
                    Divider()
                    AnnotationToolbar(session: session, chooseImage: chooseImage)
                    Divider()
                    PDFPane(session: session, annotations: notes.annotations)
                    Divider()
                    HStack(spacing: 18) {
                        Button { session.move(-1) } label: { Image(systemName: "chevron.left") }
                            .disabled(session.selection == 0).help("Vorherige Folie: ← oder ↑ im PDF-Bereich; auch ⌘↑")
                            .accessibilityLabel("Vorherige Folie").keyboardShortcut(.upArrow, modifiers: .command)
                        Text("Folie \(session.selection + 1) von \(pdf.pageCount)").font(.callout.monospacedDigit())
                        Button { session.move(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(session.selection >= pdf.pageCount - 1).help("Nächste Folie: → oder ↓ im PDF-Bereich; auch ⌘↓")
                            .accessibilityLabel("Nächste Folie").keyboardShortcut(.downArrow, modifiers: .command)
                    }.buttonStyle(.borderless).frame(maxWidth: .infinity).frame(height: 43)
                }
                .frame(minWidth: EditorWidthMemory.minimumPDFWidth, maxWidth: .infinity, maxHeight: .infinity)

                editor.frame(minWidth: EditorWidthMemory.minimumEditorWidth, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                    .background(EditorWidthMemory())
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Mitschrift", systemImage: "square.and.pencil").font(.subheadline.weight(.semibold))
                Spacer()
                Text("Folie \(session.selection + 1)").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).frame(height: 47)
            Divider()
            HStack(spacing: 14) {
                Button { showFormula.toggle() } label: { Label("Formel", systemImage: "function") }
                    .foregroundStyle(showFormula ? accent : .secondary)
                Button { showDrawing.toggle() } label: { Label("Skizze", systemImage: "pencil.tip.crop.circle") }
                    .foregroundStyle(showDrawing ? accent : .secondary)
                Button { createAIPrompt() } label: { Label("KI-Prompt", systemImage: "text.bubble") }
                    .help("KI-Prompt mit Dateipfad und aktueller Folie kopieren (⌥⌘K)")
                    .accessibilityLabel("KI-Prompt mit Dateipfad kopieren")
                    .keyboardShortcut("k", modifiers: [.command, .option])
                    .popover(isPresented: $showsAIPrompt) {
                        if let aiPrompt {
                            AIPromptPopover(context: aiPrompt, copy: copyPrompt)
                                .id(aiPrompt.studyPDFURL)
                        }
                    }
                Spacer()
                Menu {
                    ForEach([13.0, 15.0, 18.0, 21.0], id: \.self) { size in
                        Button("\(Int(size)) pt") { fontSize = size }
                    }
                } label: { Image(systemName: "textformat.size") }
                .menuStyle(.borderlessButton).fixedSize().help("Schriftgröße der Mitschrift")
            }
            .buttonStyle(.borderless).font(.callout).padding(.horizontal, 22).padding(.vertical, 13)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Was möchtest du festhalten?")
                        .font(.system(size: 24, weight: .medium, design: .serif)).padding(.top, 4)
                    ZStack(alignment: .topLeading) {
                        if notes.wrappedValue.text.isEmpty {
                            Text("Eigene Erklärungen, wichtige Gedanken, offene Fragen …")
                                .font(.system(size: fontSize)).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.top, 1).allowsHitTesting(false)
                        }
                        TextEditor(text: notes.text)
                            .font(.system(size: fontSize)).lineSpacing(5)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 260)
                            .focused($notesFocused)
                            .accessibilityLabel("Mitschrift zu Folie \(session.selection + 1)")
                            .id(session.selection)
                    }
                    if showFormula {
                        sectionHeader("Formel", symbol: "function")
                        FormulaEditor(formula: notes.formula)
                    }
                    if showDrawing {
                        sectionHeader("Skizze", symbol: "pencil.tip")
                        DrawingEditor(elements: notes.drawing).id(session.selection)
                    }
                    if !showFormula && !showDrawing && notes.wrappedValue.formula.isEmpty && notes.wrappedValue.drawing.isEmpty {
                        Text("Manches wird als Formel oder Skizze klarer. Ergänze sie über die Leiste oben.")
                            .font(.callout).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                Text("\(notes.wrappedValue.text.split(whereSeparator: \.isWhitespace).count) Wörter")
                Spacer()
                Text(fileURL?.pathExtension.lowercased() == "pdf" ? "PDF speichern: ⌘S" : "Datei speichern: ⌘S")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).frame(height: 43)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Divider()
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if session.document != nil {
                Button { session.showsSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                    .help("Seitenleiste ein-/ausblenden").accessibilityLabel("Seitenleiste ein- oder ausblenden")
                Button { openWindow(id: LibraryCommands.windowID) } label: { Image(systemName: "folder") }
                    .help("Bibliothek öffnen (⇧⌘L)").accessibilityLabel("Bibliothek öffnen")
            }
        }
        ToolbarItem(placement: .principal) {
            if session.document != nil {
                TextField("Name der Vorlesung", text: $document.project.title)
                    .textFieldStyle(.plain).font(.headline).multilineTextAlignment(.center)
                    .frame(minWidth: 160, idealWidth: 300, maxWidth: 420)
                    .accessibilityLabel("Name der Vorlesung")
            } else { Text("UniPDF").font(.headline) }
        }
        ToolbarItem(placement: .primaryAction) {
            if session.document != nil {
                HStack(spacing: 12) {
                    Button {
                        NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                    } label: { Label("Speichern", systemImage: "square.and.arrow.down") }
                    .help("Geöffnete Datei am selben Speicherort aktualisieren (⌘S)")
                    if let exportedURL {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([exportedURL]) } label: {
                            Label("Im Finder zeigen", systemImage: "checkmark.circle")
                        }.help("Exportiertes Lern-PDF im Finder zeigen")
                    }
                    Button { exportPDF() } label: { Label("Lern-PDF exportieren", systemImage: "square.and.arrow.up") }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                }
            }
        }
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (document.project.title.isEmpty ? "Vorlesung" : document.project.title) + " – Lernskript.pdf"
        panel.title = "Lern-PDF exportieren"
        panel.prompt = "Exportieren"
        let save: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try PDFExporter.export(document.project)
                try data.write(to: url, options: .atomic)
                exportedURL = url
            } catch { errorMessage = error.localizedDescription }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: save) }
        else { save(panel.runModal()) }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.title = "Bild einfügen"
        panel.prompt = "Einfügen"
        let insert: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do { session.overlay?.insertImage(try Data(contentsOf: url)) }
            catch { errorMessage = error.localizedDescription }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: insert) }
        else { insert(panel.runModal()) }
    }

    private func createAIPrompt() {
        do {
            let context = try AIQuestionContext.create(project: document.project,
                                                        sourceURL: fileURL, slideIndex: session.selection)
            aiPrompt = context
            if copyPrompt(context.text()) { showsAIPrompt = true }
        } catch { errorMessage = error.localizedDescription }
    }

    private func copyPrompt(_ text: String) -> Bool {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            errorMessage = "Der Prompt konnte nicht in die Zwischenablage kopiert werden. Versuche es erneut."
            return false
        }
        return true
    }
}

private struct SlideRow: View {
    let page: PDFPage?
    let index: Int
    let hasNotes: Bool
    let annotations: [SlideAnnotation]
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
                else { Rectangle().fill(.quaternary) }
            }
            .frame(maxWidth: .infinity).frame(height: 78)
            .background(.white).clipShape(RoundedRectangle(cornerRadius: 4))
            HStack {
                Text("Folie \(index + 1)").font(.caption)
                Spacer()
                if hasNotes { Image(systemName: "pencil.line").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Folie \(index + 1)\(hasNotes ? ", mit Mitschrift" : "")")
        .task(id: annotations) {
            guard let page else { return }
            thumbnail = AnnotationRenderer.thumbnail(of: page, annotations: annotations, size: CGSize(width: 240, height: 156))
        }
    }
}
