import SwiftUI
import UniPDFCore

/// A comment unfolded from its tag in the notes: the passage, the comment, its colour.
struct CommentCard: View {
    let comment: SlideComment
    let fontSize: CGFloat
    let controller: NotesEditorController?
    let setText: (String) -> Void
    let setColor: (CommentColor) -> Void
    let jump: () -> Void
    let delete: () -> Void
    let collapse: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var dark: Bool { colorScheme == .dark }
    private var strong: Color { Color(nsColor: comment.color.strong.nsColor) }
    private var pastel: Color { Color(nsColor: comment.color.pastel.nsColor) }
    private var ink: Color { dark ? pastel : strong }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(action: jump) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: comment.isArea ? "rectangle.dashed" : "text.quote")
                        Text(comment.isArea ? String(localized: "Area on the slide") : String(localized: "“\(quote)”"))
                            .italic()
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Go to the passage on the slide")
                .accessibilityLabel(comment.isArea ? String(localized: "Go to the Area on the Slide") : String(localized: "Go to the passage: \(quote)"))
                Spacer(minLength: 4)
                Menu {
                    ForEach(CommentColor.allCases, id: \.self) { color in
                        Button { setColor(color) } label: {
                            Label(color.label, systemImage: color == comment.color ? "checkmark.circle.fill" : "circle.fill")
                        }
                    }
                } label: {
                    Circle().fill(strong).frame(width: 10, height: 10)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Comment color").accessibilityLabel("Color: \(comment.color.label)")
                Button(action: collapse) { Image(systemName: "chevron.up").font(.caption.weight(.bold)) }
                    .buttonStyle(.plain).foregroundStyle(ink)
                    .help("Collapse").accessibilityLabel("Collapse Comment")
            }
            .font(.callout)

            ZStack(alignment: .topLeading) {
                if comment.text.isEmpty {
                    Text("Write a comment …")
                        .font(.system(size: fontSize)).foregroundStyle(.secondary)
                        .padding(.leading, 5).allowsHitTesting(false)
                }
                NotesEditor(text: Binding(get: { comment.text }, set: setText), fontSize: fontSize,
                            accessibilityLabel: String(localized: "Comment"), controller: controller ?? NotesEditorController(),
                            minimumHeight: 44)
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(dark ? 0.35 : 0.75), in: RoundedRectangle(cornerRadius: 7))

            HStack {
                Text(comment.created, format: .dateTime.day().month().year().hour().minute())
                Spacer()
                Button(role: .destructive, action: delete) { Label("Delete", systemImage: "trash") }
                    .buttonStyle(.borderless)
                    .help("Delete the comment and its mark on the slide")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(dark ? strong.opacity(0.22) : pastel.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
    }

    private var quote: String {
        let words = comment.quote.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.count > 160 ? String(words.prefix(160)) + " …" : words
    }
}
