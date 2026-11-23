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
    @State private var autoSaving = false
    /// This lecture as Claude's tools reach it, while it is open.
    @State private var claude: ClaudeWorkspace?
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
    @State private var search = DocumentSearch()
    /// Whether the notes column is folded away, so the slide takes the whole width. Kept across launches.
    @AppStorage("notesCollapsed") private var notesCollapsed = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openDocument) private var openDocument
    @Environment(\.openWindow) private var openWindow

    private var accent: Color { Color.studyAccent(for: colorScheme) }

    private var notes: Binding<PageNotes> { notes(for: session.selection) }

    /// The notes of one slide. While scrolling, annotations change on slides beside the current one too.
    private func notes(for index: Int) -> Binding<PageNotes> {
        Binding(
            get: { document.project.pages[index] ?? PageNotes() },
            set: { new in
                // A deleted tag takes its comment off the slide, a deleted comment its tag out of the notes.
                let value = CommentLinks.reconcile(new, previous: document.project.pages[index] ?? PageNotes())
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
        .alert("That didn’t work", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
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
        .focusedSceneValue(\.documentSearch, session.document == nil ? nil : search)
        .focusedSceneValue(\.slideSession, session.document == nil ? nil : session)
        .onAppear {
            search.showSidebar = { sidebarVisibility = .all }
            search.reveal = { hit in reveal(hit) }
            session.createComment = { comment in addComment(comment) }
            session.pageAnnotations = { index in document.project.pages[index]?.annotations ?? [] }
            session.setPageAnnotations = { index, annotations in notes(for: index).wrappedValue.annotations = annotations }
            session.openComment = { id in
                notesCollapsed = false
                notesEditor.expand(id)
            }
            connectClaude()
        }
        .onDisappear {
            if let claude { ClaudeBridge.shared.unregister(claude) }
            claude = nil
        }
        .onChange(of: fileURL) { connectClaude() }
        .onChange(of: search.query) { updateSearch() }
        .onChange(of: document.project.pages) { if search.isSearching { updateSearch() } }
        .onChange(of: session.selection) {
            // A card stays open only on its own slide, such as one a search hit opened.
            if let id = notesEditor.expandedComment, !notes.wrappedValue.annotations.contains(where: { $0.id == id }) {
                notesEditor.expand(nil)
            }
            showDrawing = !notes.wrappedValue.drawing.isEmpty
        }
    }

    private var welcome: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Label {
                    Text("UniPDF").foregroundStyle(accent)
                } icon: {
                    BrandSymbol().fill(Brand.gradient).frame(width: 26, height: 26)
                }
                .font(.title3.weight(.semibold))
                Spacer()
                Text("Your lecture.\nYour thoughts.")
                    .font(.system(size: 43, weight: .semibold, design: .serif)).tracking(-1)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Read slides, understand how things connect and keep everything in one place.")
                    .font(.title3).foregroundStyle(.secondary).lineSpacing(5).frame(maxWidth: 380, alignment: .leading)
                HStack(spacing: 12) {
                    Button { importSourceWindow = NSApp.keyWindow; importing = true } label: {
                        Label("Open Lecture PDF", systemImage: "plus").padding(.horizontal, 12).padding(.vertical, 7)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("i", modifiers: .command)
                    Button { openWindow(id: LibraryCommands.windowID) } label: {
                        Label("Library", systemImage: "folder").padding(.horizontal, 8).padding(.vertical, 7)
                    }
                    .help("Manage the folder with your lectures (⇧⌘L)")
                }
                .controlSize(.large)
                Text("You can also open PDFs and existing projects with ⌘O.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Label("Local on your Mac", systemImage: "internaldrive").font(.callout).foregroundStyle(.secondary)
            }
            .padding(56).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 34) {
                welcomeStep("doc.text", "Lecture slides", "Import your lecture’s PDF. Every slide has room for your thoughts.")
                welcomeStep("pencil.and.outline", "More than taking notes", "Add notes, formulas and sketches. Everything stays linked to its slide.")
                welcomeStep("square.and.arrow.down", "Save and keep studying", "⌘S updates your open PDF with all your notes. It stays editable in UniPDF.")
            }
            .padding(48).frame(width: 390, alignment: .leading).frame(maxHeight: .infinity)
            .background(accent.opacity(0.06))
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func welcomeStep(_ symbol: String, _ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
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
                if search.isSearching {
                    searchResults
                } else {
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
                        Text("Slides")
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search.query, isPresented: $search.isPresented, placement: .sidebar, prompt: "Search Document")
            .onSubmit(of: .search) { search.step(1) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Text(search.isSearching ? searchSummary
                     : String(localized: "\(document.project.pages.values.filter { !$0.isEmpty }.count) of \(pdf.pageCount) slides with notes"))
                    .font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    // The list scrolls beneath the caption, which would otherwise sit on top of the previews.
                    .background(.bar)
            }
            .onChange(of: session.selection) { if !search.isSearching { proxy.scrollTo(session.selection) } }
            .onChange(of: search.current) { if let current = search.current { proxy.scrollTo(search.hits[current].id) } }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 340)
        .onAppear { fileTree.reveal(fileURL, in: fileStore); fileTree.reload(fileStore) }
        .onChange(of: fileStore.revision) { fileTree.reload(fileStore) }
        .onChange(of: fileURL) { fileTree.reveal(fileURL, in: fileStore); fileTree.reload(fileStore) }
        // The library window may be closed, so the sidebar notices outside changes by itself.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in fileTree.reload(fileStore) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in fileTree.reload(fileStore) }
        .alert("That didn’t work", isPresented: Binding(get: { fileTree.openError != nil }, set: { if !$0 { fileTree.openError = nil } })) {
            Button("OK") { fileTree.openError = nil }
        } message: { Text(fileTree.openError ?? "") }
    }

    // MARK: Search

    /// Hits by slide, as in Preview's search.
    @ViewBuilder private var searchResults: some View {
        if search.hits.isEmpty {
            Text("No results for “\(search.query.trimmingCharacters(in: .whitespaces))”")
                .font(.callout).foregroundStyle(.secondary)
        }
        let pages = Array(Set(search.hits.map(\.page))).sorted()
        ForEach(pages, id: \.self) { page in
            Section {
                ForEach(Array(search.hits.enumerated()).filter { $0.element.page == page }, id: \.element.id) { index, hit in
                    SearchResultRow(hit: hit, isCurrent: search.current == index) { search.show(index) }
                        .padding(.leading, -9)
                        .id(hit.id)
                }
            } header: {
                Text("Slide \(page + 1)")
            }
        }
    }

    private var searchSummary: String {
        let count = search.hits.count
        let slides = Set(search.hits.map(\.page)).count
        if count == 0 { return String(localized: "No results") }
        let hits = count >= TextSearch.limit ? String(localized: "Over \(TextSearch.limit) results")
            : count == 1 ? String(localized: "1 result") : String(localized: "\(count) results")
        let found = slides == 1 ? String(localized: "\(hits) on 1 slide") : String(localized: "\(hits) on \(slides) slides")
        return found + " · " + String(localized: "↩ next")
    }

    private func updateSearch() {
        guard let pdf = session.document else { return }
        search.update(document: pdf, pages: document.project.pages)
        // Every hit on the slides is marked; the current one is selected on top.
        let selections: [PDFSelection] = search.hits.compactMap { hit in
            guard hit.source == .slide, let page = pdf.page(at: hit.page),
                  let selection = page.selection(for: hit.range) else { return nil }
            selection.color = NSColor.systemYellow.withAlphaComponent(0.45)
            return selection
        }
        session.view?.highlightedSelections = selections.isEmpty ? nil : selections
        if !search.isSearching { session.view?.clearSelection() }
    }

    private func reveal(_ hit: TextSearch.Hit) {
        session.selection = hit.page
        switch hit.source {
        case .notes, .comment: notesCollapsed = false
        case .slide, .textBox: break
        }
        if case .comment(let id) = hit.source { notesEditor.expand(id) }
        session.pendingReveal = SearchReveal(page: hit.page, source: hit.source, range: hit.range)
    }

    // MARK: Claude

    /// Lets Claude's tools read and change this lecture; every change goes through the document, like one by hand.
    private func connectClaude() {
        if let claude { ClaudeBridge.shared.unregister(claude) }
        let session = session, editor = notesEditor, url = fileURL
        let workspace = ClaudeWorkspace(
            title: { document.project.title },
            fileURL: { url },
            pdf: { session.document },
            currentSlide: { session.selection },
            showSlide: { index in session.selection = index },
            notes: { index in document.project.pages[index] ?? PageNotes() },
            setNotes: { index, value in notes(for: index).wrappedValue = value },
            slideSelection: { session.view?.currentSelection?.string },
            notesSelection: {
                guard let view = editor.notesView, view.selectedRange().length > 0 else { return nil }
                return (view.string as NSString).substring(with: view.selectedRange())
            },
            window: { session.view?.window },
            showComment: { _, id in
                notesCollapsed = false
                editor.expand(id)
            })
        ClaudeBridge.shared.register(workspace)
        claude = workspace
    }

    // MARK: Comments

    /// The comment goes on the slide and its tag into the notes in one change, which one undo takes back.
    /// The tag lands where the caret was put in the notes, otherwise on a new line at the end.
    private func addComment(_ comment: SlideAnnotation) {
        // The new comment's card is where its text goes, so the notes come back.
        notesCollapsed = false
        var value = notes.wrappedValue
        value.annotations.append(comment)
        let token = CommentLinks.token(for: comment.id)
        let text = value.text as NSString
        if let caret = notesEditor.notesCaret, caret <= text.length {
            let before = caret > 0 ? text.substring(with: NSRange(location: caret - 1, length: 1)) : "\n"
            let after = caret < text.length ? text.substring(with: NSRange(location: caret, length: 1)) : "\n"
            let insertion = (before.rangeOfCharacter(from: .whitespacesAndNewlines) == nil ? " " : "") + token
                + (after.rangeOfCharacter(from: .whitespacesAndNewlines) == nil ? " " : "")
            value.text = text.replacingCharacters(in: NSRange(location: caret, length: 0), with: insertion)
            notesEditor.notesCaret = caret + (insertion as NSString).length
        } else {
            let trimmed = value.text.trimmingCharacters(in: .newlines)
            value.text = trimmed.isEmpty ? token : trimmed + "\n" + token
        }
        notes.wrappedValue = value
        notesEditor.expand(comment.id, focus: true)
    }

    private var commentContext: CommentContext {
        let notes = notes
        let page = session.selection
        let session = session
        let editor = notesEditor
        return CommentContext(
            comments: Dictionary(uniqueKeysWithValues: CommentLinks.comments(in: notes.wrappedValue).map { ($0.id, $0.comment) }),
            expanded: notesEditor.expandedComment,
            update: { id, comment in
                var value = notes.wrappedValue
                guard let index = value.annotations.firstIndex(where: { $0.id == id }) else { return }
                value.annotations[index].content = .comment(comment)
                notes.wrappedValue = value
            },
            delete: { id in
                var value = notes.wrappedValue
                value.annotations.removeAll { $0.id == id }
                editor.expand(nil)
                if session.selectedAnnotation == id { session.selectedAnnotation = nil; session.selectedKind = nil }
                notes.wrappedValue = value
            },
            jump: { id in session.pendingReveal = SearchReveal(page: page, source: .comment(id), range: NSRange()) },
            toggle: { id in editor.expand(editor.expandedComment == id ? nil : id) }
        )
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
                            .disabled(session.selection == 0).help("Previous slide: ← or ↑ in the PDF area; also ⌘↑")
                            .accessibilityLabel("Previous Slide").keyboardShortcut(.upArrow, modifiers: .command)
                        Text("Slide \(session.selection + 1) of \(pdf.pageCount)").font(.callout.monospacedDigit())
                        Button { session.move(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(session.selection >= pdf.pageCount - 1).help("Next slide: → or ↓ in the PDF area; also ⌘↓")
                            .accessibilityLabel("Next Slide").keyboardShortcut(.downArrow, modifiers: .command)
                    }.buttonStyle(.borderless).frame(maxWidth: .infinity).frame(height: 43)
                }
                .frame(minWidth: EditorWidthMemory.minimumPDFWidth, maxWidth: .infinity, maxHeight: .infinity)

                if !notesCollapsed {
                    editor.frame(minWidth: EditorWidthMemory.minimumEditorWidth, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                        .background(EditorWidthMemory())
                }
            }
            // On the detail column, as in the Finder.
            .toolbar { toolbar }
            .modifier(WithoutToolbarTitle())
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Notes", systemImage: "square.and.pencil").font(.subheadline.weight(.semibold))
                Spacer()
                Text("Slide \(session.selection + 1)").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 22).frame(height: 47)
            Divider()
            HStack(spacing: 14) {
                Button { showFormula.toggle() } label: { Label("Formula", systemImage: "function") }
                    .foregroundStyle(showFormula ? accent : .secondary)
                    .help("Formula bar: formula blocks, symbols by topic, superscript and subscript")
                Button { showDrawing.toggle() } label: { Label("Sketch", systemImage: "pencil.tip.crop.circle") }
                    .foregroundStyle(showDrawing ? accent : .secondary)
                Button { createAIPrompt() } label: { Label("AI Prompt", systemImage: "text.bubble") }
                    .help("Copy an AI prompt with the file path and the current slide (⌥⌘K)")
                    .accessibilityLabel("Copy AI Prompt with File Path")
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
                .menuStyle(.borderlessButton).fixedSize().help("Font size of the notes")
            }
            .buttonStyle(.borderless).font(.callout).padding(.horizontal, 22).padding(.vertical, 13)
            if showFormula {
                FormulaPalette(insert: notesEditor.insert, isInFormula: notesEditor.isInFormula)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("What do you want to remember?")
                        .font(.system(size: 24, weight: .medium, design: .serif)).padding(.top, 4)
                    ZStack(alignment: .topLeading) {
                        if notes.wrappedValue.text.isEmpty {
                            Text("Your own explanations, key ideas, open questions …")
                                .font(.system(size: fontSize)).foregroundStyle(.secondary)
                                .padding(.horizontal, 5).padding(.top, 1).allowsHitTesting(false)
                        }
                        NotesEditor(text: notes.text, fontSize: fontSize,
                                    accessibilityLabel: String(localized: "Notes for slide \(session.selection + 1)"), controller: notesEditor,
                                    page: session.selection, searchQuery: search.isSearching ? search.query : "",
                                    reveal: session.pendingReveal, revealed: { session.pendingReveal = nil },
                                    comments: commentContext)
                            .id(session.selection)
                    }
                    // Formulas used to have a field of their own. They now belong in the text.
                    if !notes.wrappedValue.formula.isEmpty {
                        sectionHeader("Formula", symbol: "function")
                        FormulaEditor(formula: notes.formula) { moveFormulaIntoNotes() }
                    }
                    if showDrawing {
                        sectionHeader("Sketch", symbol: "pencil.tip")
                        DrawingEditor(elements: notes.drawing).id(session.selection)
                    }
                    if !showFormula && !showDrawing && notes.wrappedValue.drawing.isEmpty {
                        Text(verbatim: String(localized: "Format like in a chat: **bold**, _italic_, ~strikethrough~, - bullets. Formulas go between $ … $ or come from “Formula”, sketches from “Sketch”."))
                            .font(.callout).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }.padding(24)
            }
            Divider()
            HStack {
                Text("\(notes.wrappedValue.text.split(whereSeparator: \.isWhitespace).count) words")
                Spacer()
                Text(fileURL?.pathExtension.lowercased() == "pdf" ? String(localized: "Save PDF: ⌘S") : String(localized: "Save file: ⌘S"))
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).frame(height: 43)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var formatMenu: some View {
        Menu {
            Button("Bold") { notesEditor.toggle(.bold) }.keyboardShortcut("b")
            Button("Italic") { notesEditor.toggle(.italic) }.keyboardShortcut("i")
            Button("Strikethrough") { notesEditor.toggle(.strike) }
            Button("Code") { notesEditor.toggle(.code) }
            Divider()
            Button("Bulleted List") { notesEditor.toggleList(numbered: false) }
            Button("Numbered List") { notesEditor.toggleList(numbered: true) }
            Divider()
            Button("Formula Block") { notesEditor.insert(.block) }
            Divider()
            Text("**bold** · _italic_ · ~strike~ · `code`")
            Text("# Heading · - Bullet · 1. List · > Quote")
            Text("$x^{2}$ in a sentence · $$ … $$ as a block")
        } label: { Image(systemName: "bold.italic.underline") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Formatting of the notes")
        .accessibilityLabel("Formatting")
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

    private func sectionHeader(_ title: LocalizedStringKey, symbol: String) -> some View {
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
                Button { openWindow(id: LibraryCommands.windowID) } label: { Label("Library", systemImage: "folder") }
                    .help("Open the library (⇧⌘L)")
            }
        }
    }

    @ToolbarContentBuilder private var titleItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if session.document != nil {
                HStack(spacing: 6) {
                    // The brand mark, as beside the document title in the web app.
                    BrandSymbol(small: true).fill(Brand.gradient).frame(width: 16, height: 16).accessibilityHidden(true)
                    // As wide as the name: the hidden text gives the width, the field sits on top of it.
                    Text(document.project.title.isEmpty ? String(localized: "Lecture name") : document.project.title)
                        .font(.headline).lineLimit(1).hidden()
                        .overlay {
                            TextField("Lecture name", text: $document.project.title)
                                .textFieldStyle(.plain).font(.headline)
                                .accessibilityLabel("Lecture Name")
                        }
                        .frame(minWidth: 40, maxWidth: 360)
                    saveStatus
                }
                .padding(.leading, 10).padding(.trailing, 6)
                .background(HiddenWindowTitle())
                .background(DocumentEditedObserver { hasUnsavedChanges = $0 })
                .background(AutoSaver { autoSaving = $0 })
            } else { Text("UniPDF").font(.headline) }
        }
    }

    /// A quiet mark beside the lecture's name: a grey dot while changes are unsaved, a green check once all is saved,
    /// and while it saves by itself a short bar in the brand gradient.
    private var saveStatus: some View {
        Group {
            if autoSaving {
                AutoSaveBar()
            } else if hasUnsavedChanges {
                Circle().fill(.secondary.opacity(0.6)).frame(width: 7, height: 7)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white, accent)
            }
        }
        // The dot and the check keep their place; only the bar while saving takes a little more room.
        .frame(width: autoSaving ? 30 : 14, height: 14)
        .help(autoSaving ? String(localized: "Saving automatically") : hasUnsavedChanges ? String(localized: "Unsaved changes – save with ⌘S") : String(localized: "Everything saved"))
        .accessibilityElement()
        .accessibilityLabel(autoSaving ? String(localized: "Saving Automatically") : hasUnsavedChanges ? String(localized: "Unsaved Changes") : String(localized: "Everything Saved"))
    }

    @ToolbarContentBuilder private var saveItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if session.document != nil {
                HStack(spacing: 12) {
                    Button { search.open() } label: { Label("Search", systemImage: "magnifyingglass") }
                        .help("Search slides, notes and text boxes (⌘F)")
                    Button {
                        NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                    } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .help("Update the open file in the same place (⌘S)")
                    if let exportedURL {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([exportedURL]) } label: {
                            Label("Show in Finder", systemImage: "checkmark.circle")
                        }.help("Show the exported study PDF in the Finder")
                    }
                    Button { exportPDF() } label: { Label("Export Study PDF", systemImage: "square.and.arrow.up") }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    Button { notesCollapsed.toggle() } label: {
                        Label(notesCollapsed ? String(localized: "Show Notes") : String(localized: "Hide Notes"), systemImage: "sidebar.right")
                    }
                    .keyboardShortcut("0", modifiers: [.command, .option])
                    .help(notesCollapsed ? String(localized: "Show the notes (⌥⌘0)") : String(localized: "Hide the notes so the slide uses the full width (⌥⌘0)"))
                }
            }
        }
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let name = document.project.title.isEmpty ? String(localized: "Lecture") : document.project.title
        panel.nameFieldStringValue = String(localized: "\(name) – Study PDF.pdf")
        panel.title = String(localized: "Export Study PDF")
        panel.prompt = String(localized: "Export")
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
        panel.title = String(localized: "Insert Image")
        panel.prompt = String(localized: "Insert")
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
            errorMessage = String(localized: "The prompt could not be copied to the clipboard. Try again.")
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
            .accessibilityLabel(hasNotes ? String(localized: "Slide \(index + 1), with notes") : String(localized: "Slide \(index + 1)"))
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
            // The open slide: a narrow frame in the brand gradient with a little air around the preview.
            .padding(3)
            .overlay { if isSelected { RoundedRectangle(cornerRadius: 7).strokeBorder(Brand.gradient, lineWidth: 2.5) } }
            // A portrait page at full width would fill the list, so its height is capped.
            .frame(maxWidth: .infinity, maxHeight: 150)
            HStack(spacing: 4) {
                Text("Slide \(index + 1)").font(.caption.monospacedDigit())
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
