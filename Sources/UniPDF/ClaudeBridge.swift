import AppKit
import PDFKit
import UniPDFCore

/// An open lecture as Claude's tools see it. The workspace hands in how to read and change it, so that
/// every change goes through the document like one made by hand, with its own undo.
@MainActor
final class ClaudeWorkspace {
    let id = UUID()
    var title: () -> String
    var fileURL: () -> URL?
    var pdf: () -> PDFDocument?
    var currentSlide: () -> Int
    var showSlide: (Int) -> Void
    var notes: (Int) -> PageNotes
    var setNotes: (Int, PageNotes) -> Void
    var slideSelection: () -> String?
    var notesSelection: () -> String?
    var window: () -> NSWindow?
    /// Opens the notes and a comment's card, so that a new comment shows.
    var showComment: (Int, UUID) -> Void

    init(title: @escaping () -> String, fileURL: @escaping () -> URL?, pdf: @escaping () -> PDFDocument?,
         currentSlide: @escaping () -> Int, showSlide: @escaping (Int) -> Void,
         notes: @escaping (Int) -> PageNotes, setNotes: @escaping (Int, PageNotes) -> Void,
         slideSelection: @escaping () -> String?, notesSelection: @escaping () -> String?,
         window: @escaping () -> NSWindow?, showComment: @escaping (Int, UUID) -> Void) {
        self.title = title; self.fileURL = fileURL; self.pdf = pdf
        self.currentSlide = currentSlide; self.showSlide = showSlide
        self.notes = notes; self.setNotes = setNotes
        self.slideSelection = slideSelection; self.notesSelection = notesSelection
        self.window = window; self.showComment = showComment
    }
}

/// The app's end of the link to Claude: it listens on UniPDF's local socket and carries out each tool call
/// on the lecture it names, or the one in front.
@MainActor
final class ClaudeBridge {
    static let shared = ClaudeBridge()
    private var workspaces: [UUID: ClaudeWorkspace] = [:]
    private var started = false

    func register(_ workspace: ClaudeWorkspace) { workspaces[workspace.id] = workspace }
    func unregister(_ workspace: ClaudeWorkspace) { workspaces[workspace.id] = nil }

    /// Starts listening; a second UniPDF that runs at the same time leaves the socket to the first.
    func start() {
        guard !started else { return }
        started = true
        let path = ClaudeLink.socketPath
        // Another UniPDF already answers there.
        if let probe = ClaudeLink.connect(to: path) { close(probe); return }
        guard let server = try? ClaudeLink.listen(at: path) else { return }
        let thread = Thread {
            while true {
                let client = accept(server, nil, nil)
                guard client >= 0 else { continue }
                Self.serve(client)
            }
        }
        thread.name = "UniPDF Claude link"
        thread.start()
    }

    private nonisolated static func serve(_ client: Int32) {
        defer { close(client) }
        guard let line = ClaudeLink.readLine(client),
              let request = try? JSONDecoder().decode(ClaudeLink.Request.self, from: line) else { return }
        let arguments = (try? JSONSerialization.jsonObject(with: Data(request.arguments.utf8)) as? [String: Any]) ?? [:]
        let payload = SendableArguments(value: arguments)
        let response = DispatchQueue.main.sync {
            MainActor.assumeIsolated { ClaudeBridge.shared.handle(request.tool, payload.value) }
        }
        if let data = try? JSONEncoder().encode(response) { ClaudeLink.writeLine(client, data) }
    }

    private nonisolated struct SendableArguments: @unchecked Sendable { let value: [String: Any] }

    // MARK: Tools

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let changingTools: Set<String> = ["add_comment", "edit_comment", "delete_comment", "add_notes", "highlight_text"]
    private var activity: NSObjectProtocol?
    private var activityEnd: DispatchWorkItem?

    func handle(_ tool: String, _ arguments: [String: Any]) -> ClaudeLink.Response {
        stayAwake()
        do {
            let text = try run(tool, arguments)
            if Self.changingTools.contains(tool) { NotificationCenter.default.post(name: AutoSave.changedByClaude, object: nil) }
            return ClaudeLink.Response(text: text)
        } catch { return ClaudeLink.Response(text: error.localizedDescription, isError: true) }
    }

    /// While Claude works, UniPDF usually sits behind Claude's window, where macOS would put it to sleep
    /// and hold back saving. It stays awake until a minute after the last call.
    private func stayAwake() {
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                             reason: "Claude is working on a lecture")
        }
        activityEnd?.cancel()
        let end = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                if let activity = self?.activity { ProcessInfo.processInfo.endActivity(activity) }
                self?.activity = nil
            }
        }
        activityEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: end)
    }

    private func run(_ tool: String, _ arguments: [String: Any]) throws -> String {
        if tool == "open_documents" { return ClaudeEditing.json(listDocuments()) }
        let workspace = try target(arguments["document"] as? String)
        guard let pdf = workspace.pdf() else { throw Failure(message: "The lecture has no slides yet.") }
        if tool == "current_selection" {
            var result: [String: Any] = ["slide": workspace.currentSlide() + 1]
            result["slideSelection"] = workspace.slideSelection() ?? ""
            result["notesSelection"] = workspace.notesSelection() ?? ""
            return ClaudeEditing.json(result)
        }
        let index = try slideIndex(arguments, in: pdf, workspace: workspace)
        guard let page = pdf.page(at: index) else { throw Failure(message: "There is no slide \(index + 1).") }
        let notes = workspace.notes(index)
        let occurrence = arguments["occurrence"] as? Int ?? 1

        switch tool {
        case "read_slide":
            return ClaudeEditing.json(ClaudeEditing.describe(slide: index, of: pdf.pageCount, page: page, notes: notes))
        case "go_to_slide":
            workspace.showSlide(index)
            return "Slide \(index + 1) is on screen."
        case "add_comment":
            let color = try commentColor(arguments["color"])
            let (changed, id) = try ClaudeEditing.addComment(to: notes, page: page, quote: string(arguments, "quote"),
                                                             text: string(arguments, "comment"), color: color,
                                                             occurrence: occurrence, after: arguments["after"] as? String)
            workspace.setNotes(index, changed)
            if index == workspace.currentSlide() { workspace.showComment(index, id) }
            return ClaudeEditing.json(["id": id.uuidString, "slide": index + 1])
        case "edit_comment":
            let changed = try ClaudeEditing.editComment(in: notes, id: string(arguments, "id"), text: arguments["comment"] as? String,
                                                        color: commentColor(arguments["color"]))
            workspace.setNotes(index, changed)
            return "Comment changed."
        case "delete_comment":
            workspace.setNotes(index, try ClaudeEditing.deleteComment(in: notes, id: string(arguments, "id")))
            return "Comment removed from the slide and the notes."
        case "add_notes":
            workspace.setNotes(index, try ClaudeEditing.addNotes(to: notes, text: string(arguments, "text"), after: arguments["after"] as? String))
            return "Added to the notes of slide \(index + 1)."
        case "highlight_text":
            var color = PDFTextHighlight.yellow
            if let name = arguments["color"] as? String {
                guard let match = ClaudeEditing.highlightColors.first(where: { $0.name == name }) else {
                    throw Failure(message: "Unknown colour “\(name)”. Use \(ClaudeEditing.highlightColors.map(\.name).joined(separator: ", ")).")
                }
                color = match.color
            }
            let (changed, id) = try ClaudeEditing.highlight(in: notes, page: page, quote: string(arguments, "quote"), color: color, occurrence: occurrence)
            workspace.setNotes(index, changed)
            return ClaudeEditing.json(["id": id.uuidString, "slide": index + 1])
        default:
            throw Failure(message: "Unknown tool \(tool).")
        }
    }

    private func listDocuments() -> [[String: Any]] {
        let front = frontmost()
        return workspaces.values.compactMap { workspace -> [String: Any]? in
            guard let pdf = workspace.pdf() else { return nil }
            return ["document": workspace.title(), "file": workspace.fileURL()?.path ?? "", "slides": pdf.pageCount,
                    "slideOnScreen": workspace.currentSlide() + 1, "inFront": workspace === front]
        }
    }

    private func frontmost() -> ClaudeWorkspace? {
        let open = workspaces.values.filter { $0.pdf() != nil }
        return open.first { $0.window()?.isKeyWindow == true }
            ?? open.first { $0.window()?.isMainWindow == true }
            ?? open.first { $0.window()?.isVisible == true }
            ?? open.first
    }

    private func target(_ name: String?) throws -> ClaudeWorkspace {
        let open = workspaces.values.filter { $0.pdf() != nil }
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            guard let front = frontmost() else { throw Failure(message: "No lecture is open in UniPDF.") }
            return front
        }
        let wanted = name.lowercased()
        let matches = open.filter {
            $0.title().lowercased() == wanted || $0.fileURL()?.lastPathComponent.lowercased() == wanted
                || $0.fileURL()?.path.lowercased() == wanted
        }
        let loose = matches.isEmpty ? open.filter {
            $0.title().lowercased().contains(wanted) || ($0.fileURL()?.lastPathComponent.lowercased().contains(wanted) ?? false)
        } : matches
        guard loose.count == 1, let found = loose.first else {
            throw Failure(message: loose.isEmpty ? "No open lecture is called “\(name)”. See open_documents."
                          : "Several open lectures match “\(name)”. Use the file name from open_documents.")
        }
        return found
    }

    private func slideIndex(_ arguments: [String: Any], in pdf: PDFDocument, workspace: ClaudeWorkspace) throws -> Int {
        guard let number = arguments["slide"] as? Int else { return workspace.currentSlide() }
        guard number >= 1, number <= pdf.pageCount else {
            throw Failure(message: "Slide \(number) does not exist; the lecture has \(pdf.pageCount) slides.")
        }
        return number - 1
    }

    private func string(_ arguments: [String: Any], _ key: String) throws -> String {
        guard let value = arguments[key] as? String else { throw Failure(message: "“\(key)” is missing.") }
        return value
    }

    private func commentColor(_ value: Any?) throws -> CommentColor? {
        guard let name = value as? String else { return nil }
        guard let color = CommentColor(rawValue: name) else {
            throw Failure(message: "Unknown colour “\(name)”. Use \(CommentColor.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        return color
    }
}
