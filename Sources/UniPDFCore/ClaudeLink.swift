import Foundation

/// The connection between Claude and the running UniPDF. Claude starts `UniPDF --mcp`, which speaks the
/// Model Context Protocol on its standard input and output and hands every tool call to the app through a
/// local socket that only this user can open. The app applies the call to the open lecture right away.
public enum ClaudeLink {
    /// The socket, in the user's own Application Support folder.
    public static var socketPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("UniPDF/claude.sock").path
    }

    /// A request from the MCP side: one tool and its arguments.
    public struct Request: Codable, Sendable {
        public var tool: String
        public var arguments: String // JSON
        public init(tool: String, arguments: String) { self.tool = tool; self.arguments = arguments }
    }

    public struct Response: Codable, Sendable {
        public var text: String
        public var isError: Bool
        public init(text: String, isError: Bool = false) { self.text = text; self.isError = isError }
    }

    // MARK: The socket

    private static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            for (index, byte) in bytes.enumerated() { raw[index] = byte }
            raw[bytes.count] = 0
        }
        return address
    }

    /// Opens the socket for the app to listen on; replaces one a crashed app left behind.
    public static func listen(at path: String = socketPath) throws -> Int32 {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var address = address(path) else { throw POSIXError(.EINVAL) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { close(fd); throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        // Only this user may talk to the app.
        chmod(path, 0o600)
        guard Darwin.listen(fd, 8) == 0 else { close(fd); throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return fd
    }

    /// Connects to the running app; nil when it does not run.
    public static func connect(to path: String = socketPath) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var address = address(path) else { return nil }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { close(fd); return nil }
        return fd
    }

    /// One line, without its break; nil at the end of the stream.
    public static func readLine(_ fd: Int32) -> Data? {
        var data = Data()
        var byte: UInt8 = 0
        while read(fd, &byte, 1) == 1 {
            if byte == 10 { return data }
            data.append(byte)
        }
        return data.isEmpty ? nil : data
    }

    public static func writeLine(_ fd: Int32, _ data: Data) {
        var bytes = [UInt8](data)
        bytes.append(10)
        var sent = 0
        while sent < bytes.count {
            let written = bytes[sent...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if written <= 0 { return }
            sent += written
        }
    }

    /// One tool call to the running app, as the MCP side makes it.
    public static func call(_ tool: String, arguments: [String: Any], path: String = socketPath) -> Response {
        guard let fd = connect(to: path) else {
            return Response(text: "UniPDF is not running. Ask the user to open UniPDF and the lecture, then try again.", isError: true)
        }
        defer { close(fd) }
        let json = (try? JSONSerialization.data(withJSONObject: arguments)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        guard let request = try? JSONEncoder().encode(Request(tool: tool, arguments: json)) else {
            return Response(text: "The arguments could not be sent.", isError: true)
        }
        writeLine(fd, request)
        guard let line = readLine(fd), let response = try? JSONDecoder().decode(Response.self, from: line) else {
            return Response(text: "UniPDF did not answer.", isError: true)
        }
        return response
    }
}

/// The tools Claude gets, as MCP lists them.
public enum ClaudeTools {
    nonisolated(unsafe) private static let document: [String: Any] = [
        "type": "string",
        "description": "Which open lecture: its title or file name. Leave out for the one in front.",
    ]
    nonisolated(unsafe) private static let slide: [String: Any] = ["type": "integer", "minimum": 1, "description": "The slide number, counting from 1."]
    nonisolated(unsafe) private static let commentColor: [String: Any] = [
        "type": "string", "enum": CommentColor.allCases.map(\.rawValue),
        "description": "The comment's colour. Left out, comments take the colours in turn.",
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any], required: [String] = [],
                             readOnly: Bool = false) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required] as [String: Any],
         "annotations": ["readOnlyHint": readOnly, "destructiveHint": name == "delete_comment"] as [String: Any]]
    }

    nonisolated(unsafe) public static let definitions: [[String: Any]] = [
        tool("open_documents", "Lists the lectures open in UniPDF: title, file, number of slides, the slide on screen and which one is in front.",
             [:], readOnly: true),
        tool("read_slide", "Reads one slide: the text on the slide, the user's notes for it (Markdown-like markup with $formulas$ and [[kommentar:ID]] tags), its comments with their ids, text boxes and how many highlights and drawings it has.",
             ["document": document, "slide": slide], readOnly: true),
        tool("current_selection", "What the user has marked right now: text selected on the slide and in the notes, and the slide on screen.",
             ["document": document], readOnly: true),
        tool("add_comment", "Comments on a passage of a slide, as the user does by hand: the passage gets a pastel mark on the slide and a tag in the notes that opens the comment. The quote must be text that stands on the slide (see read_slide); line breaks and case do not matter.",
             ["document": document, "slide": slide,
              "quote": ["type": "string", "description": "The passage on the slide, word for word."],
              "comment": ["type": "string", "description": "The comment, in the notes' markup: **bold**, _italic_, - bullets, $formula$."],
              "color": commentColor,
              "occurrence": ["type": "integer", "minimum": 1, "description": "Which one, where the passage appears more than once. Default 1."],
              "after": ["type": "string", "description": "Text in the notes after which the tag goes. Left out, the tag goes on a new line at the end."]],
             required: ["slide", "quote", "comment"]),
        tool("edit_comment", "Changes a comment's text or colour.",
             ["document": document, "slide": slide,
              "id": ["type": "string", "description": "The comment's id, from read_slide or add_comment."],
              "comment": ["type": "string", "description": "The new text."], "color": commentColor],
             required: ["slide", "id"]),
        tool("delete_comment", "Removes a comment: its mark on the slide and its tag in the notes.",
             ["document": document, "slide": slide, "id": ["type": "string", "description": "The comment's id."]],
             required: ["slide", "id"]),
        tool("add_notes", "Adds a paragraph to the notes of a slide, in their markup: # heading, **bold**, _italic_, - bullets (indented with two spaces per level), - [ ] task, $formula$, $$ block formula $$, [text](https://…) link, ``` code block ```, --- rule, and boxes: a line > [!DEFINITION], > [!MERKE], > [!BEISPIEL], > [!PRÜFUNG] or > [!ACHTUNG], then the box's text in lines starting with > . It never replaces what is written.",
             ["document": document, "slide": slide,
              "text": ["type": "string", "description": "What to add."],
              "after": ["type": "string", "description": "Text in the notes after whose line it goes. Left out, it goes at the end."]],
             required: ["slide", "text"]),
        tool("highlight_text", "Marks a passage of a slide with the highlighter.",
             ["document": document, "slide": slide,
              "quote": ["type": "string", "description": "The passage on the slide, word for word."],
              "color": ["type": "string", "enum": ClaudeEditing.highlightColors.map(\.name), "description": "Default yellow."],
              "occurrence": ["type": "integer", "minimum": 1, "description": "Which one, where the passage appears more than once. Default 1."]],
             required: ["slide", "quote"]),
        tool("go_to_slide", "Shows a slide in UniPDF, so that the user sees where you work.",
             ["document": document, "slide": slide], required: ["slide"]),
    ]

    public static let instructions = """
        UniPDF is the user's app for lecture slides with notes beside them. These tools act on the lecture open in it, live: \
        every change appears at once and the user can take it back with ⌘Z. Slides count from 1. Read a slide with read_slide \
        before you comment on it or mark it, and quote the slide's text exactly. Go to a slide with go_to_slide before you \
        change it, so that the user sees it happen. Never remove what the user wrote; add to it. Write comments and notes in \
        the language of the user's notes.
        """
}

/// The Model Context Protocol on standard input and output: one JSON-RPC message per line.
public final class MCPServer {
    public typealias Call = (_ tool: String, _ arguments: [String: Any]) -> ClaudeLink.Response
    private let call: Call
    private let version: String

    public init(version: String = "1.0", call: @escaping Call) {
        self.call = call
        self.version = version
    }

    /// Answers one message; nil for notifications, which get no answer.
    public func handle(_ line: Data) -> Data? {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = message["id"] else { return nil }
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        let result: [String: Any]
        switch method {
        case "initialize":
            result = [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "unipdf", "title": "UniPDF", "version": version],
                "instructions": ClaudeTools.instructions,
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": ClaudeTools.definitions]
        case "tools/call":
            guard let name = params["name"] as? String, ClaudeTools.definitions.contains(where: { $0["name"] as? String == name }) else {
                return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Unknown tool"]])
            }
            let response = call(name, params["arguments"] as? [String: Any] ?? [:])
            result = ["content": [["type": "text", "text": response.text]], "isError": response.isError]
        default:
            return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
        }
        return encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func encode(_ value: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes])
    }

    /// Serves until the input ends.
    public func run(input: FileHandle = .standardInput, output: FileHandle = .standardOutput) {
        var buffer = Data()
        while true {
            let chunk = input.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[buffer.index(after: newline)...])
                guard !line.isEmpty, let answer = handle(Data(line)) else { continue }
                output.write(answer + Data([10]))
            }
        }
    }
}
