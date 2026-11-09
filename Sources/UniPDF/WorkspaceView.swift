import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import UniPDFCore

struct WorkspaceView: View {
    @Binding var document: StudyDocument
    var fileURL: URL? = nil
    var fileStore: LibraryStore = .shared
    @State private var session = PDFSession()
    @State private var sidebarVisibility = NavigationSplitViewVisibility.all
    @State private var fileTree = FileTreeModel()
    @State private var showsToolSettings = false
    @State private var hasUnsavedChanges = false
    @State private var importing = false
    @State private var importSourceWindow: NSWindow?
    @State private var errorMessage: String?
    @State private var exportedURL: URL?
    @State private var aiPrompt: AIQuestionPrompt?
    @State private var showsAIPrompt = false
    @State private var showFormula = false
    @State private var showDrawing = false
    @State private var fontSize = 15.0
    @State private var notesEditor = NotesEditorController()
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
            else { welcome.toolbar { toolbar } }
        }
        .tint(accent)
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
            showDrawing = !notes.wrappedValue.drawing.isEmpty
        }
        .onChange(of: session.annotationError) {
            if let message = session.annotationError {
                errorMessage = message
                session.annotationError = nil
            }
        }
        .onChange(of: session.selection) {
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

    /// Native sidebar, as in the Finder: the granted folder above the slides of this lecture.
    private func sidebar(_ pdf: PDFDocument) -> some View {
        ScrollViewReader { proxy in
            // No list selection: its filled highlight would cover the preview. The open slide gets a green frame instead.
            List {
                FileTreeSection(store: fileStore, currentFile: fileURL, model: fileTree)
                Section {
                    ForEach(0..<pdf.pageCount, id: \.self) { index in
                        SlideRow(page: pdf.page(at: index), index: index, isSelected: session.selection == index,
                                 hasNotes: !(document.project.pages[index]?.isEmpty ?? true),
                                 annotations: document.project.pages[index]?.annotations ?? []) {
                            session.selection = index
                        }
                            // The sidebar indents rows 9 points more on the leading side, for disclosure
                            // triangles, and ignores listRowInsets. Slides have none and sit centered,
                            // their frames in line with the section header.
                            .padding(.leading, -15).padding(.trailing, -6)
                            .id(index)
                    }
                } header: {
                    Text("Folien")
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Text("\(document.project.pages.values.filter { !$0.isEmpty }.count) von \(pdf.pageCount) Folien mit Mitschrift")
                    .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 10)
            }
            .onChange(of: session.selection) { proxy.scrollTo(session.selection) }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 340)
        .onAppear { fileTree.reveal(fileURL, in: fileStore); fileTree.reload(fileStore) }
        .onChange(of: fileStore.revision) { fileTree.reload(fileStore) }
        .onChange(of: fileURL) { fileTree.reveal(fileURL, in: fileStore); fileTree.reload(fileStore) }
        // The library window may be closed, so the sidebar notices outside changes by itself.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in fileTree.reload(fileStore) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in fileTree.reload(fileStore) }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { fileTree.openError != nil }, set: { if !$0 { fileTree.openError = nil } })) {
            Button("OK") { fileTree.openError = nil }
        } message: { Text(fileTree.openError ?? "") }
    }

    /// Whether the active tool or the selection has settings. The arrow without a selection has none.
    private var hasToolSettings: Bool { session.tool != .select || session.selectedAnnotation != nil }

    /// The tools in the slide pane's header; beneath them, only when there are any, their settings.
    private var slideHeader: some View {
        VStack(spacing: 0) {
            // 8 points: in line with the library button and the tab bar above.
            SlideToolBar(session: session, chooseImage: chooseImage)
                .padding(.horizontal, 8).frame(height: 47)
            if showsToolSettings {
                Divider()
                ViewThatFits(in: .horizontal) {
                    AnnotationSettingsBar(session: session)
                    AnnotationSettingsBar(session: session, swatches: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
        .onAppear { showsToolSettings = hasToolSettings }
        // Not mid-gesture: the slide would shift under the pointer while it moves something.
        .onChange(of: hasToolSettings) { if !session.isGestureActive { showsToolSettings = hasToolSettings } }
        .onChange(of: session.isGestureActive) { if !session.isGestureActive { showsToolSettings = hasToolSettings } }
    }

    private func workspace(_ pdf: PDFDocument) -> some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar(pdf)
        } detail: {
            HSplitView {
                VStack(spacing: 0) {
                    slideHeader
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
            // On the detail column, as in the Finder.
            .toolbar { toolbar }
            .modifier(WithoutToolbarTitle())
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
                    .help("Formelleiste: Formelblöcke, Zeichen nach Themengebiet, hoch- und tiefgestellt")
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
                formatMenu
                Menu {
                    ForEach([13.0, 15.0, 18.0, 21.0], id: \.self) { size in
                        Button("\(Int(size)) pt") { fontSize = size }
                    }
                } label: { Image(systemName: "textformat.size") }
                .menuStyle(.borderlessButton).fixedSize().help("Schriftgröße der Mitschrift")
            }
            .buttonStyle(.borderless).font(.callout).padding(.horizontal, 22).padding(.vertical, 13)
            if showFormula {
                FormulaPalette(insert: notesEditor.insert, isInFormula: notesEditor.isInFormula)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
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
                        NotesEditor(text: notes.text, fontSize: fontSize,
                                    accessibilityLabel: "Mitschrift zu Folie \(session.selection + 1)", controller: notesEditor)
                            .id(session.selection)
                    }
                    // Formulas used to have a field of their own. They now belong in the text.
                    if !notes.wrappedValue.formula.isEmpty {
                        sectionHeader("Formel", symbol: "function")
                        FormulaEditor(formula: notes.formula) { moveFormulaIntoNotes() }
                    }
                    if showDrawing {
                        sectionHeader("Skizze", symbol: "pencil.tip")
                        DrawingEditor(elements: notes.drawing).id(session.selection)
                    }
                    if !showFormula && !showDrawing && notes.wrappedValue.drawing.isEmpty {
                        Text(verbatim: "Formatiere wie im Chat: **fett**, _kursiv_, ~durchgestrichen~, - Stichpunkte. Formeln stehen zwischen $ … $ oder kommen über „Formel“ dazu, Skizzen über „Skizze“.")
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

    private var formatMenu: some View {
        Menu {
            Button("Fett") { notesEditor.toggle(.bold) }.keyboardShortcut("b")
            Button("Kursiv") { notesEditor.toggle(.italic) }.keyboardShortcut("i")
            Button("Durchgestrichen") { notesEditor.toggle(.strike) }
            Button("Code") { notesEditor.toggle(.code) }
            Divider()
            Button("Stichpunkte") { notesEditor.toggleList(numbered: false) }
            Button("Nummerierte Liste") { notesEditor.toggleList(numbered: true) }
            Divider()
            Button("Formelblock") { notesEditor.insert(.block) }
            Divider()
            Text("**fett** · _kursiv_ · ~durch~ · `Code`")
            Text("# Überschrift · - Punkt · 1. Liste · > Zitat")
            Text("$x^{2}$ im Satz · $$ … $$ als Block")
        } label: { Image(systemName: "bold.italic.underline") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Formatierung der Mitschrift")
        .accessibilityLabel("Formatierung")
    }

    /// Moves a formula from the old formula field into the notes, as a block.
    private func moveFormulaIntoNotes() {
        var value = notes.wrappedValue
        let formula = value.formula.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !formula.isEmpty else { return }
        let text = value.text.trimmingCharacters(in: .newlines)
        value.text = (text.isEmpty ? "" : text + "\n\n") + "$$ " + formula + " $$"
        value.formula = ""
        notes.wrappedValue = value
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Divider()
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
        }
    }

    /// The name stands in the pill in the middle, so the title beside the library button would repeat it.
    /// Before macOS 15 the window's title visibility does the same.
    private struct WithoutToolbarTitle: ViewModifier {
        func body(content: Content) -> some View {
            if #available(macOS 15, *) { content.toolbar(removing: .title) } else { content }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        libraryItem
        titleItem
        saveItems
    }

    @ToolbarContentBuilder private var libraryItem: some ToolbarContent {
        // The sidebar button comes with NavigationSplitView.
        ToolbarItem(placement: .navigation) {
            if session.document != nil {
                Button { openWindow(id: LibraryCommands.windowID) } label: { Label("Bibliothek", systemImage: "folder") }
                    .help("Bibliothek öffnen (⇧⌘L)")
            }
        }
    }

    @ToolbarContentBuilder private var titleItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if session.document != nil {
                HStack(spacing: 6) {
                    // As wide as the name: the hidden text gives the width, the field sits on top of it.
                    Text(document.project.title.isEmpty ? "Name der Vorlesung" : document.project.title)
                        .font(.headline).lineLimit(1).hidden()
                        .overlay {
                            TextField("Name der Vorlesung", text: $document.project.title)
                                .textFieldStyle(.plain).font(.headline)
                                .accessibilityLabel("Name der Vorlesung")
                        }
                        .frame(minWidth: 40, maxWidth: 360)
                    saveStatus
                }
                .padding(.leading, 10).padding(.trailing, 6)
                .background(HiddenWindowTitle())
                .background(DocumentEditedObserver { hasUnsavedChanges = $0 })
            } else { Text("UniPDF").font(.headline) }
        }
    }

    /// A quiet mark beside the lecture's name: a grey dot while changes are unsaved, a green check once all is saved.
    private var saveStatus: some View {
        Group {
            if hasUnsavedChanges {
                Circle().fill(.secondary.opacity(0.6)).frame(width: 7, height: 7)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white, accent)
            }
        }
        .frame(width: 14, height: 14)
        .help(hasUnsavedChanges ? "Ungesicherte Änderungen – mit ⌘S sichern" : "Alles gesichert")
        .accessibilityElement()
        .accessibilityLabel(hasUnsavedChanges ? "Ungesicherte Änderungen" : "Alles gesichert")
    }

    @ToolbarContentBuilder private var saveItems: some ToolbarContent {
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
    let isSelected: Bool
    let hasNotes: Bool
    let annotations: [SlideAnnotation]
    let select: () -> Void
    @State private var thumbnail: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    /// The page as displayed, so that portrait and turned pages keep their shape.
    private var aspectRatio: CGFloat {
        guard let size = page?.displayedSlideSize, size.width > 0, size.height > 0 else { return 16 / 9 }
        return size.width / size.height
    }

    var body: some View {
        Button(action: select) { content }
            .buttonStyle(.plain)
            .accessibilityLabel("Folie \(index + 1)\(hasNotes ? ", mit Mitschrift" : "")")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .task(id: annotations) {
                guard let page else { return }
                let size = CGSize(width: 320, height: 320 / aspectRatio)
                thumbnail = AnnotationRenderer.thumbnail(of: page, annotations: annotations, size: size)
            }
    }

    private var content: some View {
        let accent = Color.studyAccent(for: colorScheme)
        return VStack(spacing: 6) {
            Group {
                if let thumbnail { Image(nsImage: thumbnail).resizable() }
                else { Rectangle().fill(.white) }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            // The open slide: a narrow green frame with a little air around the preview.
            .padding(3)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isSelected ? accent : .clear, lineWidth: 2.5))
            // A portrait page at full width would fill the list, so its height is capped.
            .frame(maxWidth: .infinity, maxHeight: 150)
            HStack(spacing: 4) {
                Text("Folie \(index + 1)").font(.caption.monospacedDigit())
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? accent : .primary)
                Spacer(minLength: 0)
                if hasNotes { Image(systemName: "pencil.line").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        // Little air at the sides: the sidebar's own row margins already separate it from the edge.
        .padding(.horizontal, 2).padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
