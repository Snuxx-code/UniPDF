import AppKit
import CoreText
import Foundation
import PDFKit
import Testing
@testable import UniPDFCore

/// A slide with three lines, the middle two one sentence broken over the lines.
private func slide() throws -> PDFPage {
    let bytes = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 640, height: 360)
    let consumer = try #require(CGDataConsumer(data: bytes))
    let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
    context.beginPDFPage(nil)
    for (text, y) in [("Eigenwerte", 300.0), ("Ein Skalar heißt Eigenwert,", 240.0), ("wenn Av gleich lambda v ist.", 200.0), ("Eigenwerte sind wichtig.", 160.0)] {
        context.textPosition = CGPoint(x: 60, y: y)
        let line = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black])
        CTLineDraw(CTLineCreateWithAttributedString(line), context)
    }
    context.endPDFPage()
    context.closePDF()
    let document = try #require(PDFDocument(data: bytes as Data))
    return try #require(document.page(at: 0))
}

struct ClaudeEditingTests {
    @Test func passagesAreFoundAcrossLineBreaksAndCase() throws {
        let page = try slide()
        let selection = try #require(ClaudeEditing.find("heißt Eigenwert, WENN av", on: page))
        #expect(selection.string?.replacingOccurrences(of: "\n", with: " ").contains("heißt Eigenwert, wenn Av") == true)
        #expect(ClaudeEditing.find("steht nicht drauf", on: page) == nil)
        // The second time the word appears.
        let second = try #require(ClaudeEditing.find("Eigenwerte", on: page, occurrence: 2))
        let first = try #require(ClaudeEditing.find("Eigenwerte", on: page))
        #expect(second.bounds(for: page).minY < first.bounds(for: page).minY)
    }

    @Test func aCommentGetsItsMarkAndItsTag() throws {
        let page = try slide()
        var notes = PageNotes()
        notes.text = "# Eigenwerte\nDefinition merken."
        let (changed, id) = try ClaudeEditing.addComment(to: notes, page: page, quote: "Ein Skalar heißt Eigenwert, wenn",
                                                         text: "Gilt nur für v ≠ 0.", after: "Definition")
        #expect(changed.text == "# Eigenwerte\nDefinition \(CommentLinks.token(for: id)) merken.")
        guard case .comment(let comment) = changed.annotations.first?.content else { Issue.record("No comment"); return }
        #expect(comment.rects.count == 2)
        #expect(comment.text == "Gilt nur für v ≠ 0.")
        #expect(comment.color == .rose)
        // Without a place in the notes, the tag goes on a new line at the end; colours take turns.
        let (again, second) = try ClaudeEditing.addComment(to: changed, page: page, quote: "Eigenwerte sind wichtig", text: "Ja.")
        #expect(again.text.hasSuffix("\n" + CommentLinks.token(for: second)))
        if case .comment(let next) = again.annotations.last?.content { #expect(next.color == .peach) }
        #expect(throws: ClaudeEditing.Failure.quoteNotFound("Gibt es nicht")) {
            try ClaudeEditing.addComment(to: notes, page: page, quote: "Gibt es nicht", text: "x")
        }
    }

    @Test func notesGrowWithoutLosingAnything() throws {
        var notes = PageNotes()
        notes.text = "# Titel\n- Punkt eins\n- Punkt zwei"
        #expect(try ClaudeEditing.addNotes(to: notes, text: "  - Unterpunkt", after: "Punkt eins").text
                == "# Titel\n- Punkt eins\n  - Unterpunkt\n- Punkt zwei")
        #expect(try ClaudeEditing.addNotes(to: notes, text: "Am Ende.").text == "# Titel\n- Punkt eins\n- Punkt zwei\nAm Ende.")
        #expect(try ClaudeEditing.addNotes(to: PageNotes(), text: "Erste Zeile").text == "Erste Zeile")
        #expect(throws: ClaudeEditing.Failure.anchorNotFound("fehlt")) { try ClaudeEditing.addNotes(to: notes, text: "x", after: "fehlt") }
    }

    @Test func commentsChangeAndGoWithTheirTag() throws {
        let page = try slide()
        var notes = PageNotes()
        notes.text = "Notiz"
        let (commented, id) = try ClaudeEditing.addComment(to: notes, page: page, quote: "Eigenwerte sind", text: "Alt")
        let edited = try ClaudeEditing.editComment(in: commented, id: id.uuidString, text: "Neu", color: .sky)
        guard case .comment(let comment) = edited.annotations.first?.content else { Issue.record("No comment"); return }
        #expect(comment.text == "Neu" && comment.color == .sky)
        let removed = try ClaudeEditing.deleteComment(in: edited, id: id.uuidString)
        #expect(removed.annotations.isEmpty)
        #expect(removed.text == "Notiz")
        #expect(throws: ClaudeEditing.Failure.noSuchComment("kein-id")) { try ClaudeEditing.deleteComment(in: removed, id: "kein-id") }
    }

    @Test func highlightsAndTheSlideAsClaudeReadsIt() throws {
        let page = try slide()
        let (marked, _) = try ClaudeEditing.highlight(in: PageNotes(), page: page, quote: "lambda v")
        guard case .highlight(let rects, _) = marked.annotations.first?.content else { Issue.record("No highlight"); return }
        #expect(rects.count == 1)
        let read = ClaudeEditing.describe(slide: 0, of: 3, page: page, notes: marked)
        #expect(read["slide"] as? Int == 1 && read["highlights"] as? Int == 1)
        #expect((read["slideText"] as? String)?.contains("Ein Skalar") == true)
    }
}

struct MCPServerTests {
    private func send(_ server: MCPServer, _ message: [String: Any]) throws -> [String: Any] {
        let answer = try #require(server.handle(try JSONSerialization.data(withJSONObject: message)))
        return try #require(try JSONSerialization.jsonObject(with: answer) as? [String: Any])
    }

    @Test func speaksTheProtocolAndHandsCallsOn() throws {
        var calls: [String] = []
        let server = MCPServer { tool, arguments in
            calls.append(tool)
            return ClaudeLink.Response(text: "slide \(arguments["slide"] as? Int ?? 0)")
        }
        let start = try send(server, ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-06-18"]])
        let result = try #require(start["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "unipdf")
        #expect(server.handle(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)) == nil)

        let list = try send(server, ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let tools = try #require((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(Set(tools.compactMap { $0["name"] as? String }) == ["open_documents", "read_slide", "current_selection", "add_comment",
                                                                    "edit_comment", "delete_comment", "add_notes", "highlight_text", "go_to_slide"])

        let call = try send(server, ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "read_slide", "arguments": ["slide": 4]]])
        let content = try #require((call["result"] as? [String: Any])?["content"] as? [[String: Any]])
        #expect(content.first?["text"] as? String == "slide 4")
        #expect(calls == ["read_slide"])

        let unknown = try send(server, ["jsonrpc": "2.0", "id": 4, "method": "resources/list"])
        #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)
    }

    @Test func callsTravelThroughTheLocalSocket() throws {
        let path = NSTemporaryDirectory() + "unipdf-test-\(UUID().uuidString.prefix(8)).sock"
        defer { unlink(path) }
        let server = try ClaudeLink.listen(at: path)
        defer { close(server) }
        let thread = Thread {
            let client = accept(server, nil, nil)
            guard client >= 0, let line = ClaudeLink.readLine(client),
                  let request = try? JSONDecoder().decode(ClaudeLink.Request.self, from: line) else { return }
            let answer = ClaudeLink.Response(text: "got \(request.tool) \(request.arguments)")
            if let data = try? JSONEncoder().encode(answer) { ClaudeLink.writeLine(client, data) }
            close(client)
        }
        thread.start()
        let response = ClaudeLink.call("go_to_slide", arguments: ["slide": 2], path: path)
        #expect(!response.isError)
        #expect(response.text == #"got go_to_slide {"slide":2}"#)
        // Without the app, the tools say so.
        #expect(ClaudeLink.call("read_slide", arguments: [:], path: path + "-missing").isError)
    }
}
