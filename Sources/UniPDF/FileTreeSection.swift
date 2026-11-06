import SwiftUI
import UniPDFCore

/// What the Dateien section shows: the granted folder and every folder opened beneath it.
@Observable
final class FileTreeModel {
    var expanded: Set<URL> = []
    private(set) var children: [URL: [LibraryEntry]] = [:]
    var openError: String?

    func reload(_ store: LibraryStore) {
        guard let library = store.library else {
            children = [:]
            return
        }
        var result: [URL: [LibraryEntry]] = [:]
        func visit(_ folder: URL) {
            let entries = (try? library.contents(of: folder)) ?? []
            result[folder] = entries
            for entry in entries where entry.isDirectory && expanded.contains(entry.url) { visit(entry.url) }
        }
        visit(library.root)
        children = result
    }

    /// Opens the folders above the current document, so the section starts where the student is.
    func reveal(_ file: URL?, in store: LibraryStore) {
        guard let library = store.library, let file, library.contains(file) else { return }
        expanded.formUnion(library.trail(to: file.deletingLastPathComponent()).dropFirst()
            .map { URL(fileURLWithPath: $0.path, isDirectory: true) })
    }

    func toggle(_ folder: URL, in store: LibraryStore) {
        if expanded.remove(folder) == nil { expanded.insert(folder) }
        reload(store)
    }
}

/// The collapsible „Dateien“ section of the sidebar: the granted folder as a native outline, as in the Finder.
struct FileTreeSection: View {
    let store: LibraryStore
    let currentFile: URL?
    let model: FileTreeModel
    @AppStorage("sidebarFilesExpanded") private var isExpanded = true

    var body: some View {
        Section(isExpanded: $isExpanded) {
            if let library = store.library {
                let entries = model.children[library.root] ?? []
                if entries.isEmpty {
                    Text("Dieser Ordner ist leer.").foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { FileTreeNode(entry: $0, section: self) }
                }
            } else {
                Button { store.chooseRoot() } label: { Label("Ordner auswählen …", systemImage: "folder.badge.plus") }
                    .buttonStyle(.plain)
                    .help("Gib UniPDF Zugriff auf einen Ordner, zum Beispiel dein Studium.")
            }
        } header: {
            Text("Dateien")
        }
    }

    func isCurrent(_ entry: LibraryEntry) -> Bool {
        guard let currentFile else { return false }
        return entry.url.resolvingSymlinksInPath().path == currentFile.resolvingSymlinksInPath().path
    }
}

private struct FileTreeNode: View {
    let entry: LibraryEntry
    let section: FileTreeSection
    @Environment(\.openDocument) private var openDocument

    var body: some View {
        if entry.isDirectory {
            DisclosureGroup(isExpanded: Binding(
                get: { section.model.expanded.contains(entry.url) },
                set: { if $0 != section.model.expanded.contains(entry.url) { section.model.toggle(entry.url, in: section.store) } }
            )) {
                ForEach(section.model.children[entry.url] ?? []) { FileTreeNode(entry: $0, section: section) }
            } label: {
                Button { section.model.toggle(entry.url, in: section.store) } label: {
                    Label(entry.name, systemImage: "folder")
                }
                .buttonStyle(.plain)
                .help(entry.name)
            }
        } else {
            let isCurrent = section.isCurrent(entry)
            Button { open() } label: {
                Label {
                    Text(entry.name).lineLimit(1).truncationMode(.middle)
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundStyle(entry.opensInUniPDF ? .primary : .secondary)
                } icon: {
                    Image(systemName: entry.opensInUniPDF ? "doc.richtext" : "doc")
                        .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
            }
            .buttonStyle(.plain)
            .help(entry.name)
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
        }
    }

    private func open() {
        if entry.opensInUniPDF {
            Task {
                do { try await openDocument(at: entry.url) }
                catch { section.model.openError = error.localizedDescription }
            }
        } else {
            NSWorkspace.shared.open(entry.url)
        }
    }
}
