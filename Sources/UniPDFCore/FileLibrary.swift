import Foundation

public struct LibraryEntry: Identifiable, Hashable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    public let modified: Date?
    /// Visible items inside a folder; nil for files or unreadable folders.
    public let itemCount: Int?
    public var id: URL { url }
    public var name: String { url.lastPathComponent }
    public var opensInUniPDF: Bool { !isDirectory && ["pdf", "unipdf"].contains(url.pathExtension.lowercased()) }

    public init(url: URL, isDirectory: Bool, modified: Date? = nil, itemCount: Int? = nil) {
        self.url = URL(fileURLWithPath: url.path, isDirectory: isDirectory)
        self.isDirectory = isDirectory
        self.modified = modified
        self.itemCount = itemCount
    }
}

public struct LibraryTreeRow: Identifiable, Hashable, Sendable {
    public let entry: LibraryEntry
    public let depth: Int
    public var id: URL { entry.url }
}

public enum LibraryError: LocalizedError {
    case invalidName, alreadyExists(String), outsideLibrary, moveIntoItself, protectedRoot, notAFolder

    public var errorDescription: String? {
        switch self {
        case .invalidName: String(localized: "This name is not possible. A name cannot be empty, cannot start with a period and cannot contain “/” or “:”.")
        case .alreadyExists(let name): String(localized: "“\(name)” already exists here. Choose a different name.")
        case .outsideLibrary: String(localized: "This only works with files inside the shared folder.")
        case .moveIntoItself: String(localized: "A folder cannot be moved into itself.")
        case .protectedRoot: String(localized: "The shared folder itself cannot be changed here.")
        case .notAFolder: String(localized: "The destination is not a folder.")
        }
    }
}

/// File operations confined to one folder the user granted. Existing files are never overwritten,
/// and removing goes through the Trash. Moves are coordinated so open documents follow their file.
/// Coordination can wait on an open document, so call the changing operations off the main thread.
public struct FileLibrary: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = URL(fileURLWithPath: root.resolvingSymlinksInPath().path, isDirectory: true)
    }

    public func contents(of folder: URL) throws -> [LibraryEntry] {
        guard contains(folder) else { throw LibraryError.outsideLibrary }
        return try FileManager.default
            .contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: .skipsHiddenFiles)
            .map { listed in
                // Built from `folder`: the system may report the same place under another prefix (/private/tmp).
                let url = folder.appendingPathComponent(listed.lastPathComponent)
                let values = try listed.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                // A symbolic link counts as a file, so browsing never leaves the folder or loops.
                let isDirectory = values.isDirectory == true
                let count = isDirectory ? (try? FileManager.default.contentsOfDirectory(at: listed, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).count) : nil
                return LibraryEntry(url: url, isDirectory: isDirectory, modified: values.contentModificationDate, itemCount: count)
            }
            .sorted { first, second in
                if first.isDirectory != second.isDirectory { return first.isDirectory }
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
    }

    @discardableResult
    public func createFolder(named name: String, in parent: URL) throws -> URL {
        let name = try validated(name)
        try requireFolder(parent)
        let url = parent.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw LibraryError.alreadyExists(name) }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    /// A file keeps its extension when the new name has none.
    @discardableResult
    public func rename(_ url: URL, to name: String) throws -> URL {
        try requireChangeable(url)
        var name = try validated(name)
        let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        if !isDirectory, (name as NSString).pathExtension.isEmpty, !url.pathExtension.isEmpty {
            name += "." + url.pathExtension
        }
        guard name != url.lastPathComponent else { return url }
        return try relocate(url, to: url.deletingLastPathComponent().appendingPathComponent(name, isDirectory: isDirectory))
    }

    @discardableResult
    public func move(_ url: URL, into folder: URL) throws -> URL {
        try requireChangeable(url)
        try requireFolder(folder)
        let source = normalized(url), target = normalized(folder)
        guard source.deletingLastPathComponent().pathComponents != target.pathComponents else { return url }
        guard !target.pathComponents.starts(with: source.pathComponents) else { throw LibraryError.moveIntoItself }
        let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        return try relocate(url, to: folder.appendingPathComponent(url.lastPathComponent, isDirectory: isDirectory))
    }

    /// Returns the item's location in the Trash.
    @discardableResult
    public func trash(_ url: URL) throws -> URL? {
        try requireChangeable(url)
        var trashed: NSURL?
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { current in
            do { try FileManager.default.trashItem(at: current, resultingItemURL: &trashed) }
            catch { failure = error }
        }
        if let error = coordinationError ?? failure { throw error }
        return trashed as URL?
    }

    /// The granted folder's contents as a flat list, descending only into `expanded` folders.
    /// A folder that cannot be read simply shows no children.
    public func treeRows(expanded: Set<URL>) -> [LibraryTreeRow] {
        var rows: [LibraryTreeRow] = []
        func visit(_ folder: URL, depth: Int) {
            for entry in (try? contents(of: folder)) ?? [] {
                rows.append(LibraryTreeRow(entry: entry, depth: depth))
                if entry.isDirectory, expanded.contains(entry.url) { visit(entry.url, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return rows
    }

    /// The folders from the root down to `folder`, for a path bar.
    public func trail(to folder: URL) -> [URL] {
        guard contains(folder) else { return [root] }
        let depth = normalized(folder).pathComponents.count - root.pathComponents.count
        var trail = [root]
        for name in normalized(folder).pathComponents.suffix(depth) {
            trail.append(trail[trail.count - 1].appendingPathComponent(name, isDirectory: true))
        }
        return trail
    }

    public func contains(_ url: URL) -> Bool {
        normalized(url).pathComponents.starts(with: root.pathComponents)
    }

    private func relocate(_ source: URL, to destination: URL) throws -> URL {
        // A case-only rename finds the item itself at the destination on case-insensitive volumes.
        if FileManager.default.fileExists(atPath: destination.path), !isSameItem(source, destination) {
            throw LibraryError.alreadyExists(destination.lastPathComponent)
        }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var failure: Error?
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: destination, options: .forReplacing, error: &coordinationError) { from, to in
            do {
                coordinator.item(at: from, willMoveTo: to)
                try FileManager.default.moveItem(at: from, to: to)
                coordinator.item(at: from, didMoveTo: to)
            } catch { failure = error }
        }
        if let error = coordinationError ?? failure { throw error }
        return destination
    }

    private func isSameItem(_ first: URL, _ second: URL) -> Bool {
        let key = URLResourceKey.fileResourceIdentifierKey
        guard let a = try? first.resourceValues(forKeys: [key]).fileResourceIdentifier,
              let b = try? second.resourceValues(forKeys: [key]).fileResourceIdentifier else { return false }
        return a.isEqual(b)
    }

    private func requireChangeable(_ url: URL) throws {
        guard contains(url) else { throw LibraryError.outsideLibrary }
        guard normalized(url).pathComponents != root.pathComponents else { throw LibraryError.protectedRoot }
    }

    private func requireFolder(_ url: URL) throws {
        guard contains(url) else { throw LibraryError.outsideLibrary }
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw LibraryError.notAFolder }
    }

    private func validated(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":") else {
            throw LibraryError.invalidName
        }
        return name
    }

    // Resolves only the parent: a symbolic link inside the folder is the item itself, not its target.
    private func normalized(_ url: URL) -> URL {
        url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent)
    }
}
