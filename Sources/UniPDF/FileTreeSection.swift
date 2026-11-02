import SwiftUI
import UniPDFCore

/// The collapsible „Dateien“ section above the slide list: a classic tree of the granted folder.
struct FileTreeSection: View {
    let store: LibraryStore
    let currentFile: URL?
    @AppStorage("sidebarFilesExpanded") private var isExpanded = true
    @State private var expandedFolders: Set<URL> = []
    @State private var rows: [LibraryTreeRow] = []
    @State private var openError: String?
    @Environment(\.openDocument) private var openDocument

    private static let rowHeight: CGFloat = 26
    private static let maxHeight: CGFloat = 230

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { isExpanded.toggle() } label: {
                HStack {
                    Text("Dateien").font(.headline)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Dateien einklappen" : "Dateien ausklappen")
            if isExpanded {
                Divider()
                content
            }
        }
        .onAppear { revealCurrentFile(); reload() }
        .onChange(of: store.revision) { reload() }
        .onChange(of: currentFile) { revealCurrentFile(); reload() }
        .onChange(of: expandedFolders) { reload() }
        // The library window may be closed, so this section notices outside changes by itself.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in reload() }
        .alert("Das hat nicht geklappt", isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button("OK") { openError = nil }
        } message: { Text(openError ?? "") }
    }

    @ViewBuilder private var content: some View {
        if store.library == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Noch kein Ordner verbunden.").font(.caption).foregroundStyle(.secondary)
                Button("Ordner auswählen …") { store.chooseRoot() }.controlSize(.small)
            }
            .padding(14)
        } else if rows.isEmpty {
            Text("Dieser Ordner ist leer.").font(.caption).foregroundStyle(.secondary).padding(14)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in rowView(row) }
                }
                .padding(.vertical, 4)
            }
            .frame(height: min(CGFloat(rows.count) * Self.rowHeight + 8, Self.maxHeight))
        }
    }

    private func rowView(_ row: LibraryTreeRow) -> some View {
        let entry = row.entry
        let isCurrent = isCurrentFile(entry)
        let isOpen = expandedFolders.contains(entry.url)
        return Button { activate(entry) } label: {
            HStack(spacing: 4) {
                Group {
                    if entry.isDirectory {
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 10)
                Image(systemName: entry.isDirectory ? "folder" : entry.opensInUniPDF ? "doc.richtext" : "doc")
                    .font(.caption)
                    .foregroundStyle(entry.isDirectory ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 16)
                Text(entry.name).font(.caption).lineLimit(1).truncationMode(.middle)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(entry.isDirectory || entry.opensInUniPDF ? .primary : .secondary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 8 + CGFloat(row.depth) * 10)
            .padding(.trailing, 8)
            .frame(height: Self.rowHeight)
            .background(isCurrent ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .help(entry.name)
        .accessibilityLabel(entry.isDirectory ? "Ordner \(entry.name), \(isOpen ? "ausgeklappt" : "eingeklappt")" : entry.name)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private func activate(_ entry: LibraryEntry) {
        if entry.isDirectory {
            if expandedFolders.remove(entry.url) == nil { expandedFolders.insert(entry.url) }
        } else if entry.opensInUniPDF {
            Task {
                do { try await openDocument(at: entry.url) }
                catch { openError = error.localizedDescription }
            }
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }

    private func reload() {
        rows = store.library?.treeRows(expanded: expandedFolders) ?? []
    }

    private func isCurrentFile(_ entry: LibraryEntry) -> Bool {
        guard let currentFile else { return false }
        return entry.url.resolvingSymlinksInPath().path == currentFile.resolvingSymlinksInPath().path
    }

    /// Opens the folders above the current document, so the section starts where the student is.
    private func revealCurrentFile() {
        guard let library = store.library, let currentFile, library.contains(currentFile) else { return }
        expandedFolders.formUnion(library.trail(to: currentFile.deletingLastPathComponent()).dropFirst()
            .map { URL(fileURLWithPath: $0.path, isDirectory: true) })
    }
}
