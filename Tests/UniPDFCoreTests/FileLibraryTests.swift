import CoreGraphics
import Foundation
import Testing
@testable import UniPDFCore

@Suite struct FileLibraryTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ text: String, to url: URL) throws { try Data(text.utf8).write(to: url) }

    @Test func listsFoldersFirstInNaturalOrderWithoutHiddenFiles() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FileLibrary(root: root)
        try write("", to: root.appendingPathComponent("Folie 10.pdf"))
        try write("", to: root.appendingPathComponent("Folie 2.pdf"))
        try write("", to: root.appendingPathComponent(".DS_Store"))
        try library.createFolder(named: "Zusatz", in: root)
        let entries = try library.contents(of: library.root)
        #expect(entries.map(\.name) == ["Zusatz", "Folie 2.pdf", "Folie 10.pdf"])
        #expect(entries[0].isDirectory)
        #expect(entries[1].opensInUniPDF)
    }

    @Test func nothingIsOverwritten() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FileLibrary(root: root)
        let first = root.appendingPathComponent("a.pdf"), second = root.appendingPathComponent("b.pdf")
        try write("A", to: first)
        try write("B", to: second)
        #expect(throws: LibraryError.self) { try library.rename(first, to: "b.pdf") }
        let folder = try library.createFolder(named: "Ordner", in: root)
        #expect(throws: LibraryError.self) { try library.createFolder(named: "Ordner", in: root) }
        try write("C", to: folder.appendingPathComponent("a.pdf"))
        #expect(throws: LibraryError.self) { try library.move(first, into: folder) }
        #expect(try String(contentsOf: first, encoding: .utf8) == "A")
        #expect(try String(contentsOf: second, encoding: .utf8) == "B")
        #expect(try String(contentsOf: folder.appendingPathComponent("a.pdf"), encoding: .utf8) == "C")
    }

    @Test func renameKeepsExtensionAndAllowsCaseChange() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FileLibrary(root: root)
        let file = root.appendingPathComponent("skript.pdf")
        try write("A", to: file)
        let renamed = try library.rename(file, to: "Analysis")
        #expect(renamed.lastPathComponent == "Analysis.pdf")
        let recased = try library.rename(renamed, to: "ANALYSIS.pdf")
        #expect(try library.contents(of: library.root).map(\.name) == [recased.lastPathComponent])
        #expect(recased.lastPathComponent == "ANALYSIS.pdf")
        for name in ["", "   ", ".versteckt", "a/b", "a:b", ".."] {
            #expect(throws: LibraryError.self) { try library.rename(recased, to: name) }
        }
    }

    @Test func movesFoldersWithContentButNotIntoThemselves() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FileLibrary(root: root)
        let parent = try library.createFolder(named: "Semester 1", in: root)
        let child = try library.createFolder(named: "Analysis", in: parent)
        try write("A", to: child.appendingPathComponent("skript.pdf"))
        #expect(throws: LibraryError.self) { try library.move(parent, into: child) }
        #expect(throws: LibraryError.self) { try library.move(parent, into: parent) }
        #expect(try library.move(child, into: parent).path == child.path)
        let moved = try library.move(child, into: root)
        #expect(FileManager.default.fileExists(atPath: moved.appendingPathComponent("skript.pdf").path))
        #expect(!FileManager.default.fileExists(atPath: child.path))
        // "Semester 1" must not count as inside a sibling that merely shares its prefix.
        let sibling = try library.createFolder(named: "Semester 10", in: root)
        #expect(FileLibrary(root: parent).contains(sibling) == false)
    }

    @Test func staysInsideTheGrantedFolder() throws {
        let outer = try makeRoot()
        defer { try? FileManager.default.removeItem(at: outer) }
        let root = outer.appendingPathComponent("Uni", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = outer.appendingPathComponent("privat.pdf")
        try write("P", to: outside)
        let library = FileLibrary(root: root)
        #expect(throws: LibraryError.self) { try library.move(outside, into: root) }
        #expect(throws: LibraryError.self) { try library.rename(outside, to: "x.pdf") }
        #expect(throws: LibraryError.self) { try library.trash(outside) }
        #expect(throws: LibraryError.self) { try library.createFolder(named: "x", in: outer) }
        #expect(throws: LibraryError.self) { try library.contents(of: outer) }
        #expect(throws: LibraryError.self) { try library.trash(root) }
        #expect(throws: LibraryError.self) { try library.rename(root, to: "Anders") }
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func linkedFoldersAreNeitherEnteredNorTargets() throws {
        let outer = try makeRoot()
        defer { try? FileManager.default.removeItem(at: outer) }
        let root = outer.appendingPathComponent("Uni", isDirectory: true)
        let elsewhere = outer.appendingPathComponent("Anderswo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: elsewhere)
        let file = root.appendingPathComponent("a.pdf")
        try write("A", to: file)
        let library = FileLibrary(root: root)
        #expect(try library.contents(of: library.root).first { $0.name == "Link" }?.isDirectory == false)
        #expect(throws: LibraryError.self) { try library.move(file, into: link) }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func trashKeepsTheItemRecoverable() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FileLibrary(root: root)
        let file = root.appendingPathComponent("UniPDF-Test-\(UUID().uuidString).pdf")
        try write("A", to: file)
        let trashed = try #require(try library.trash(file))
        defer { try? FileManager.default.removeItem(at: trashed) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try String(contentsOf: trashed, encoding: .utf8) == "A")
    }
}

@Suite struct LibraryBrowsingTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func onePagePDF() throws -> Data {
        let output = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 640, height: 360)
        let consumer = try #require(CGDataConsumer(data: output))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(srgbRed: 0.1, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    @Test func foldersReportVisibleItemsAndFilesTheirDate() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FileLibrary(root: root)
        let folder = try library.createFolder(named: "Analysis", in: root)
        try Data().write(to: folder.appendingPathComponent("a.pdf"))
        try Data().write(to: folder.appendingPathComponent(".DS_Store"))
        try Data().write(to: root.appendingPathComponent("b.pdf"))
        let entries = try library.contents(of: library.root)
        #expect(entries[0].itemCount == 1)
        #expect(entries[1].itemCount == nil)
        #expect(entries[1].modified != nil)
    }

    @Test func treeRowsFollowOnlyExpandedFolders() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FileLibrary(root: root)
        let semester = try library.createFolder(named: "Semester 1", in: root)
        let analysis = try library.createFolder(named: "Analysis", in: semester)
        try Data().write(to: analysis.appendingPathComponent("a.pdf"))
        try Data().write(to: root.appendingPathComponent("b.pdf"))
        #expect(library.treeRows(expanded: []).map(\.entry.name) == ["Semester 1", "b.pdf"])
        let top = try #require(library.treeRows(expanded: []).first?.entry.url)
        let opened = library.treeRows(expanded: [top])
        #expect(opened.map(\.entry.name) == ["Semester 1", "Analysis", "b.pdf"])
        #expect(opened.map(\.depth) == [0, 1, 0])
        // A nested folder stays hidden while its parent is collapsed.
        #expect(library.treeRows(expanded: [opened[1].entry.url]).map(\.entry.name) == ["Semester 1", "b.pdf"])
        #expect(library.treeRows(expanded: [top, opened[1].entry.url]).map(\.depth) == [0, 1, 2, 0])
    }

    @Test func trailLeadsFromRootToFolder() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = FileLibrary(root: root)
        let first = try library.createFolder(named: "Semester 1", in: root)
        let second = try library.createFolder(named: "Analysis", in: first)
        #expect(library.trail(to: library.root).map(\.lastPathComponent) == [library.root.lastPathComponent])
        #expect(library.trail(to: second).map(\.lastPathComponent) == [library.root.lastPathComponent, "Semester 1", "Analysis"])
        #expect(library.trail(to: root.deletingLastPathComponent()).count == 1)
        // Listings and the path must name a folder identically, also where the system adds /private.
        let listed = try #require(library.contents(of: library.root).first)
        #expect(library.trail(to: first)[1].path == listed.url.path)
    }

    @Test func pdfsAndLegacyProjectsGetAPreview() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let size = CGSize(width: 160, height: 120)
        let pdf = root.appendingPathComponent("Folie.pdf")
        try onePagePDF().write(to: pdf)
        let project = root.appendingPathComponent("Alt.unipdf")
        try StudyProject(title: "Alt", pdfData: onePagePDF()).encoded().write(to: project)
        #expect(await LibraryThumbnail.image(for: pdf, size: size, scale: 2) != nil)
        #expect(await LibraryThumbnail.image(for: project, size: size, scale: 2) != nil)
        // A damaged project must not take the grid down.
        let broken = root.appendingPathComponent("Kaputt.unipdf")
        try Data("kein Projekt".utf8).write(to: broken)
        #expect(await LibraryThumbnail.image(for: broken, size: size, scale: 2) == nil)
    }
}
