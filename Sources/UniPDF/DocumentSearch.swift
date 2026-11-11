import AppKit
import PDFKit
import SwiftUI
import UniPDFCore

/// A place to show once its slide is on screen: the slide view and the notes editor pick it up.
struct SearchReveal: Equatable {
    var page: Int
    var source: TextSearch.Source
    var range: NSRange
    /// Showing the same hit again still pulses it.
    var token = UUID()
}

/// The search of one open document: its query, its hits and the hit shown last.
@Observable
final class DocumentSearch {
    var query = ""
    /// Whether the search field in the sidebar is shown and focused.
    var isPresented = false
    private(set) var hits: [TextSearch.Hit] = []
    private(set) var current: Int?
    /// Set by the workspace: shows the sidebar and the hit's slide.
    var showSidebar: (() -> Void)?
    var reveal: ((TextSearch.Hit) -> Void)?

    private var pageTexts: [String] = []
    private weak var indexed: PDFDocument?

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func update(document: PDFDocument, pages: [Int: PageNotes]) {
        if indexed !== document {
            // The slides' text does not change, so it is read once.
            pageTexts = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
            indexed = document
        }
        let previous = current.map { hits[$0] }
        hits = TextSearch.hits(for: query, pageTexts: pageTexts, pages: pages)
        current = previous.flatMap { hit in hits.firstIndex { $0.page == hit.page && $0.source == hit.source && $0.range == hit.range } }
    }

    func open() {
        showSidebar?()
        isPresented = true
    }

    func show(_ index: Int) {
        guard hits.indices.contains(index) else { return }
        current = index
        reveal?(hits[index])
    }

    /// Return and ⌘G go forward, ⇧⌘G back, round the end.
    func step(_ offset: Int) {
        guard !hits.isEmpty else { return }
        show(((current ?? (offset > 0 ? -1 : 0)) + offset + hits.count) % hits.count)
    }
}

struct DocumentSearchCommands: Commands {
    @FocusedValue(\.documentSearch) private var search
    @FocusedValue(\.slideSession) private var session

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Section {
                Button("Im Dokument suchen …") { search?.open() }
                    .keyboardShortcut("f")
                    .disabled(search == nil)
                Button("Nächster Treffer") { search?.step(1) }
                    .keyboardShortcut("g")
                    .disabled(search?.hits.isEmpty ?? true)
                Button("Vorheriger Treffer") { search?.step(-1) }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled(search?.hits.isEmpty ?? true)
            }
            Section {
                Button("Kommentar hinzufügen") { session?.activateComment() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                    .disabled(session == nil)
            }
        }
    }
}

private struct DocumentSearchKey: FocusedValueKey {
    typealias Value = DocumentSearch
}

private struct SlideSessionKey: FocusedValueKey {
    typealias Value = PDFSession
}

extension FocusedValues {
    var slideSession: PDFSession? {
        get { self[SlideSessionKey.self] }
        set { self[SlideSessionKey.self] = newValue }
    }

    var documentSearch: DocumentSearch? {
        get { self[DocumentSearchKey.self] }
        set { self[DocumentSearchKey.self] = newValue }
    }
}

/// One hit in the sidebar: where it is, and the found text in its sentence.
struct SearchResultRow: View {
    let hit: TextSearch.Hit
    let isCurrent: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var source: (symbol: String, label: String) {
        switch hit.source {
        case .slide: ("doc.text", "Folientext")
        case .notes: ("square.and.pencil", "Mitschrift")
        case .textBox: ("character.textbox", "Textfeld")
        case .comment: ("text.bubble", "Kommentar")
        }
    }

    private var snippet: AttributedString {
        var match = AttributedString(hit.match)
        match.font = .callout.weight(.semibold)
        match.backgroundColor = Color.yellow.opacity(0.35)
        return AttributedString(hit.before) + match + AttributedString(hit.after)
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: source.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                    .help(source.label)
                Text(snippet)
                    .font(.callout)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4).padding(.horizontal, 6)
            .background(isCurrent ? Color.studyAccent(for: colorScheme).opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(source.label), Folie \(hit.page + 1): \(hit.before)\(hit.match)\(hit.after)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
