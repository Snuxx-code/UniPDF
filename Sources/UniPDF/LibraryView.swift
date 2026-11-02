import SwiftUI
import UniPDFCore

extension Color {
    static func studyAccent(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.53, green: 0.78, blue: 0.67) : Color(red: 0.16, green: 0.40, blue: 0.34)
    }
}

enum LibraryViewMode: String {
    case tiles, list
}

struct LibraryView: View {
    private enum NamePrompt {
        case newFolder, rename(LibraryEntry)
    }

    private static let tileWidth: CGFloat = 168
    private static let tileSpacing: CGFloat = 14
    private static let gridPadding: CGFloat = 20

    @State var store: LibraryStore
    @State private var namePrompt: NamePrompt?
    @State private var name = ""
    @State private var pendingTrash: LibraryEntry?
    @State private var dropTarget: URL?
    @State private var columns = 1
    @AppStorage("libraryViewMode") private var viewMode = LibraryViewMode.tiles
    @FocusState private var gridFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openDocument) private var openDocument

    init(store: LibraryStore = .shared) { _store = State(initialValue: store) }

    private var selectedEntry: LibraryEntry? { store.entries.first { $0.id == store.selection } }

    var body: some View {
        Group {
            if store.library == nil { emptyState } else { browser }
        }
        .tint(Color.studyAccent(for: colorScheme))
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar { toolbar }
        .alert(promptTitle, isPresented: Binding(get: { namePrompt != nil }, set: { if !$0 { namePrompt = nil } })) {
            TextField("Name", text: $name)
            Button("Abbrechen", role: .cancel) {}
            Button(promptAction) { submitName() }
        }
        .confirmationDialog("„\(pendingTrash?.name ?? "")“ in den Papierkorb legen?",
                            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } })) {
            Button("In den Papierkorb legen", role: .destructive) {
                if let entry = pendingTrash { Task { await store.trash(entry) } }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(pendingTrash?.isDirectory == true
                 ? "Der Ordner und sein gesamter Inhalt lassen sich aus dem Papierkorb wiederherstellen."
                 : "Die Datei lässt sich aus dem Papierkorb wiederherstellen.")
        }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        // Files change in the Finder and when a document window saves.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in store.refresh() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Noch kein Ordner", systemImage: "folder")
        } description: {
            Text("Gib UniPDF Zugriff auf einen Ordner, zum Beispiel dein Studium. Darin kannst du dann Unterordner und PDFs direkt hier ordnen.")
        } actions: {
            Button("Ordner auswählen …") { store.chooseRoot() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var browser: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()
            if store.entries.isEmpty {
                ContentUnavailableView {
                    Label("Dieser Ordner ist leer", systemImage: "folder")
                } description: {
                    Text("Lege hier einen Unterordner an oder ziehe in der Bibliothek Dateien auf diesen Ordner.")
                } actions: {
                    Button("Neuer Ordner …") { askForNewFolder() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewMode == .tiles {
                grid
            } else {
                list
            }
        }
    }

    private var pathBar: some View {
        HStack(spacing: 12) {
            path
            Picker("Darstellung", selection: $viewMode) {
                Label("Kacheln", systemImage: "square.grid.2x2").tag(LibraryViewMode.tiles)
                Label("Liste", systemImage: "list.bullet").tag(LibraryViewMode.list)
            }
            .pickerStyle(.segmented).labelStyle(.iconOnly).labelsHidden().fixedSize()
            .help("Zwischen Kacheln und Liste wechseln")
            .padding(.trailing, 16)
        }
        .frame(height: 47)
    }

    private var path: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                let trail = store.trail
                ForEach(Array(trail.enumerated()), id: \.element) { index, folder in
                    if index > 0 {
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    Button { store.enter(folder) } label: {
                        Text(folder.lastPathComponent)
                            .font(.subheadline.weight(index == trail.count - 1 ? .semibold : .regular))
                            .foregroundStyle(index == trail.count - 1 ? .primary : .secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(dropHighlight(for: folder), in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(index == trail.count - 1)
                    .dropDestination(for: URL.self) { urls, _ in
                        moveDropped(urls, into: folder)
                    } isTargeted: { setDropTarget(folder, $0) }
                }
            }
            .padding(.leading, 16)
        }
    }

    private var list: some View {
        List(store.entries, selection: $store.selection) { entry in
            HStack(spacing: 10) {
                LibraryPreview(entry: entry, cache: store.thumbnails, folderSize: 22, placeholderSize: 18,
                               onSelection: store.selection == entry.id)
                    .frame(width: 40, height: 30)
                Text(entry.name).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(entry.isDirectory || entry.opensInUniPDF ? .primary : .secondary)
                Spacer(minLength: 8)
                Text(entry.caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.vertical, 2)
            .background(dropHighlight(for: entry.url), in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .help(entry.name)
            .draggable(entry.url)
            .dropDestination(for: URL.self) { urls, _ in
                guard entry.isDirectory else { return false }
                return moveDropped(urls, into: entry.url)
            } isTargeted: { if entry.isDirectory { setDropTarget(entry.url, $0) } }
            .tag(entry.id)
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: URL.self) { urls in
            if let entry = urls.first.flatMap({ url in store.entries.first { $0.id == url } }) {
                entryMenu(entry)
            } else {
                backgroundMenu
            }
        } primaryAction: { urls in
            if let entry = urls.first.flatMap({ url in store.entries.first { $0.id == url } }) { open(entry) }
        }
    }

    @ViewBuilder private func entryMenu(_ entry: LibraryEntry) -> some View {
        Button("Öffnen") { open(entry) }
        Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        Divider()
        Button("Umbenennen …") { name = entry.name; namePrompt = .rename(entry) }
        Divider()
        Button("In den Papierkorb legen", role: .destructive) { pendingTrash = entry }
    }

    @ViewBuilder private var backgroundMenu: some View {
        Button("Neuer Ordner …") { askForNewFolder() }
        if let current = store.current {
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([current]) }
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tileWidth), spacing: Self.tileSpacing)],
                          spacing: Self.tileSpacing) {
                    ForEach(store.entries) { entry in
                        tile(entry).id(entry.id)
                    }
                }
                .padding(Self.gridPadding)
            }
            .contentShape(Rectangle())
            .onTapGesture { store.selection = nil; gridFocused = true }
            .contextMenu { backgroundMenu }
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            .onKeyPress(.leftArrow) { moveSelection(by: -1) }
            .onKeyPress(.rightArrow) { moveSelection(by: 1) }
            .onKeyPress(.upArrow) { moveSelection(by: -columns) }
            .onKeyPress(.downArrow) { moveSelection(by: columns) }
            .onKeyPress(.return) {
                guard let selectedEntry else { return .ignored }
                open(selectedEntry)
                return .handled
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                let available = width - 2 * Self.gridPadding + Self.tileSpacing
                columns = max(1, Int(available / (Self.tileWidth + Self.tileSpacing)))
            }
            .onChange(of: store.selection) {
                if let selection = store.selection { proxy.scrollTo(selection) }
            }
        }
    }

    private func tile(_ entry: LibraryEntry) -> some View {
        LibraryTile(entry: entry, cache: store.thumbnails, isSelected: store.selection == entry.id)
            .background(dropHighlight(for: entry.url), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .help(entry.name)
            .onTapGesture(count: 2) { open(entry) }
            .simultaneousGesture(TapGesture().onEnded { store.selection = entry.id; gridFocused = true })
            .accessibilityAction { open(entry) }
            .draggable(entry.url)
            .dropDestination(for: URL.self) { urls, _ in
                guard entry.isDirectory else { return false }
                return moveDropped(urls, into: entry.url)
            } isTargeted: { if entry.isDirectory { setDropTarget(entry.url, $0) } }
            .contextMenu { entryMenu(entry) }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { store.goUp() } label: { Label("Übergeordneter Ordner", systemImage: "chevron.left") }
                .disabled(!store.canGoUp)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Übergeordneter Ordner (⌘↑)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { askForNewFolder() } label: { Label("Neuer Ordner", systemImage: "folder.badge.plus") }
                .disabled(store.library == nil)
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Neuer Ordner (⇧⌘N)")
            Button {
                if let selectedEntry { pendingTrash = selectedEntry }
            } label: { Label("In den Papierkorb legen", systemImage: "trash") }
                .disabled(selectedEntry == nil)
                .keyboardShortcut(.delete, modifiers: .command)
                .help("In den Papierkorb legen (⌘⌫)")
            Button { store.refresh() } label: { Label("Aktualisieren", systemImage: "arrow.clockwise") }
                .disabled(store.library == nil)
                .keyboardShortcut("r", modifiers: .command)
                .help("Aktualisieren (⌘R)")
            Menu {
                Button(store.library == nil ? "Ordner auswählen …" : "Anderen Ordner auswählen …") { store.chooseRoot() }
                if store.library != nil {
                    Button("Ordner trennen") { store.disconnect() }
                }
            } label: {
                Label("Ordner", systemImage: "folder.badge.gearshape")
                    .accessibilityLabel("Freigegebenen Ordner ändern")
            }
            .help("Freigegebenen Ordner ändern. Beim Trennen bleiben die Dateien unverändert.")
        }
    }

    private var promptTitle: String {
        switch namePrompt {
        case .rename(let entry): "„\(entry.name)“ umbenennen"
        default: "Neuer Ordner"
        }
    }

    private var promptAction: String {
        if case .rename = namePrompt { "Umbenennen" } else { "Erstellen" }
    }

    private func askForNewFolder() {
        name = ""
        namePrompt = .newFolder
    }

    private func submitName() {
        guard let prompt = namePrompt else { return }
        let name = name
        Task {
            switch prompt {
            case .newFolder: await store.createFolder(named: name)
            case .rename(let entry): await store.rename(entry, to: name)
            }
        }
    }

    private func open(_ entry: LibraryEntry) {
        if entry.isDirectory {
            store.enter(entry.url)
        } else if entry.opensInUniPDF {
            Task {
                do { try await openDocument(at: entry.url) }
                catch { store.errorMessage = error.localizedDescription }
            }
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        guard !store.entries.isEmpty else { return .ignored }
        guard let index = store.entries.firstIndex(where: { $0.id == store.selection }) else {
            store.selection = store.entries[0].id
            return .handled
        }
        let target = index + offset
        if store.entries.indices.contains(target) { store.selection = store.entries[target].id }
        return .handled
    }

    private func moveDropped(_ urls: [URL], into folder: URL) -> Bool {
        let urls = urls.filter { $0.path != folder.path }
        guard !urls.isEmpty else { return false }
        Task { for url in urls { await store.move(url, into: folder) } }
        return true
    }

    private func setDropTarget(_ url: URL, _ targeted: Bool) {
        if targeted { dropTarget = url } else if dropTarget == url { dropTarget = nil }
    }

    private func dropHighlight(for url: URL) -> Color {
        dropTarget == url ? Color.accentColor.opacity(0.18) : .clear
    }
}

private extension LibraryEntry {
    var caption: String {
        if let itemCount {
            return itemCount == 0 ? "Leer" : itemCount == 1 ? "1 Objekt" : "\(itemCount) Objekte"
        }
        return modified?.formatted(date: .abbreviated, time: .omitted) ?? ""
    }
}

private struct LibraryTile: View {
    let entry: LibraryEntry
    let cache: NSCache<NSString, NSImage>
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            LibraryPreview(entry: entry, cache: cache, folderSize: 72, placeholderSize: 44)
                .frame(maxWidth: .infinity).frame(height: 118)
            VStack(spacing: 2) {
                Text(entry.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(2).truncationMode(.middle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(entry.isDirectory || entry.opensInUniPDF ? .primary : .secondary)
                Text(entry.caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .top)
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.isDirectory ? "Ordner \(entry.name)" : entry.name)
        .accessibilityValue(entry.caption)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A folder symbol, or a file's first page once it has loaded.
private struct LibraryPreview: View {
    let entry: LibraryEntry
    let cache: NSCache<NSString, NSImage>
    let folderSize: CGFloat
    let placeholderSize: CGFloat
    /// A selected list row has a strong accent background, where the tinted folder would vanish.
    var onSelection = false
    @State private var thumbnail: NSImage?

    // A saved file gets a new date, and with it a new preview.
    private var cacheKey: String { "\(entry.url.path)|\(entry.modified?.timeIntervalSince1970 ?? 0)" }

    var body: some View {
        Group {
            if entry.isDirectory {
                Image(systemName: "folder.fill")
                    .font(.system(size: folderSize, weight: .light))
                    .foregroundStyle(onSelection ? AnyShapeStyle(.white) : AnyShapeStyle(.tint))
            } else if let thumbnail {
                // Slides and notes are white in the app and on paper, also in dark appearance.
                Image(nsImage: thumbnail)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.black.opacity(0.15)))
            } else {
                Image(systemName: entry.opensInUniPDF ? "doc.richtext" : "doc")
                    .font(.system(size: placeholderSize, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: cacheKey) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard !entry.isDirectory else { return }
        let key = cacheKey as NSString
        if let cached = cache.object(forKey: key) {
            thumbnail = cached
            return
        }
        let size = CGSize(width: 180, height: 130)
        guard let image = await LibraryThumbnail.image(for: entry.url, size: size, scale: 2), !Task.isCancelled else { return }
        let result = NSImage(cgImage: image, size: NSSize(width: image.width / 2, height: image.height / 2))
        cache.setObject(result, forKey: key)
        thumbnail = result
    }
}
