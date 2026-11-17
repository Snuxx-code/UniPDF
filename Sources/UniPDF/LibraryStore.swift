import AppKit
import UniPDFCore

/// The granted folder and the folder currently shown. The granted folder is remembered across launches.
@Observable
final class LibraryStore {
    /// The library window and every document's sidebar show the same granted folder.
    static let shared = LibraryStore()
    private static let bookmarkKey = "libraryRootBookmark"

    private(set) var library: FileLibrary?
    private(set) var current: URL?
    private(set) var entries: [LibraryEntry] = []
    var selection: URL?
    var errorMessage: String?
    /// Counts every change to the folder, so views with their own listing can follow.
    private(set) var revision = 0
    @ObservationIgnored let thumbnails = NSCache<NSString, NSImage>()

    /// An explicit root is used as is and does not touch the remembered folder.
    init(root: URL? = nil) {
        if let root { connect(root) } else { restore() }
    }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = String(localized: "Choose a Folder for the Library")
        panel.message = String(localized: "UniPDF shows this folder with all its subfolders and can organize files in it.")
        panel.prompt = String(localized: "Give Access")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            UserDefaults.standard.set(try url.bookmarkData(), forKey: Self.bookmarkKey)
            connect(url)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Only forgets the folder. Its files stay where they are.
    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        library = nil
        current = nil
        entries = []
        selection = nil
        revision += 1
    }

    /// The folders from the granted folder down to the one shown.
    var trail: [URL] {
        guard let library, let current else { return [] }
        return library.trail(to: current)
    }

    var canGoUp: Bool { trail.count > 1 }

    func enter(_ folder: URL) {
        current = folder
        selection = nil
        refresh()
    }

    func goUp() {
        if canGoUp { enter(trail[trail.count - 2]) }
    }

    /// Shows the current folder, or its nearest ancestor if it has disappeared.
    func refresh() {
        guard library != nil else { return }
        let candidates = trail
        for folder in candidates.reversed() {
            guard let contents = try? library?.contents(of: folder) else { continue }
            current = folder
            entries = contents
            revision += 1
            if let selection, !contents.contains(where: { $0.id == selection }) { self.selection = nil }
            return
        }
        errorMessage = if let folder = library?.root.lastPathComponent {
            String(localized: "“\(folder)” can no longer be accessed. Choose the folder again.")
        } else {
            String(localized: "The folder can no longer be accessed. Choose it again.")
        }
        disconnect()
    }

    func createFolder(named name: String) async {
        guard let library, let current else { return }
        await perform { try library.createFolder(named: name, in: current) } done: { [self] url in
            selection = URL(fileURLWithPath: url.path, isDirectory: true)
        }
    }

    func rename(_ entry: LibraryEntry, to name: String) async {
        guard let library else { return }
        await perform { try library.rename(entry.url, to: name) } done: { [self] url in
            selection = URL(fileURLWithPath: url.path, isDirectory: entry.isDirectory)
        }
    }

    func move(_ url: URL, into folder: URL) async {
        guard let library else { return }
        await perform { try library.move(url, into: folder) } done: { _ in }
    }

    func trash(_ entry: LibraryEntry) async {
        guard let library else { return }
        await perform { try library.trash(entry.url) } done: { _ in }
    }

    // Runs off the main thread: file coordination can wait for an open document window.
    private func perform<Result: Sendable>(_ operation: @escaping @Sendable () throws -> Result,
                                           done: (Result) -> Void) async {
        do { done(try await Task.detached(operation: operation).value) }
        catch { errorMessage = error.localizedDescription }
        refresh()
    }

    private func connect(_ url: URL) {
        let library = FileLibrary(root: url)
        self.library = library
        current = library.root
        selection = nil
        refresh()
    }

    private func restore() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &isStale) else {
            errorMessage = String(localized: "The library’s folder was not found. Choose it again.")
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            return
        }
        if isStale, let renewed = try? url.bookmarkData() {
            UserDefaults.standard.set(renewed, forKey: Self.bookmarkKey)
        }
        connect(url)
    }
}
