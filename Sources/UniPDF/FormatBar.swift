import AppKit
import SwiftUI
import UniPDFCore

/// Beneath the notes: one row of buttons that put each kind of formatting where the caret is.
/// The row scrolls sideways, with the trackpad and with a plain mouse wheel alike.
struct FormatBar: View {
    let controller: NotesEditorController
    let toggleFormula: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        WheelScrollRow {
            HStack(spacing: 6) {
                chip("Bold", symbol: "bold", iconOnly: true) { controller.toggle(.bold) }
                chip("Italic", symbol: "italic", iconOnly: true) { controller.toggle(.italic) }
                chip("Strikethrough", symbol: "strikethrough", iconOnly: true) { controller.toggle(.strike) }
                chip("Heading", symbol: "textformat.size.larger") { controller.toggleHeading() }
                chip("Bullet", symbol: "list.bullet") { controller.toggleList(numbered: false) }
                chip("Task", symbol: "checklist") { controller.toggleTask() }
                Menu {
                    ForEach(NotesMarkup.CalloutKind.allCases, id: \.self) { kind in
                        Button { controller.insertCallout(kind) } label: { Label(kind.label, systemImage: kind.symbol) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark")
                        Text("Box")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .chipStyle()
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help(String(localized: "Box"))
                chip("Link", symbol: "link") { controller.insertLink() }
                chip("Code", symbol: "chevron.left.forwardslash.chevron.right") { controller.insertCodeBlock() }
                chip("Formula", symbol: "function") { toggleFormula() }
                chip("Rule", symbol: "minus") { controller.insertRule() }
            }
            // Room to scroll the last button clear of the fade.
            .padding(.trailing, 28)
            .fixedSize()
        }
        .frame(height: 28)
        .overlay(alignment: .trailing) {
            LinearGradient(colors: [Color(nsColor: .textBackgroundColor).opacity(0), Color(nsColor: .textBackgroundColor)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 36).allowsHitTesting(false)
        }
    }

    private func chip(_ title: LocalizedStringKey, symbol: String, iconOnly: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                if !iconOnly { Text(title) }
            }
            .chipStyle()
        }
        .buttonStyle(.plain)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}

private extension View {
    func chipStyle() -> some View {
        font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
    }
}

/// A row that scrolls sideways. A mouse wheel without Shift scrolls it too; on a trackpad an up or down
/// swipe still scrolls the notes around it.
struct WheelScrollRow<Content: View>: NSViewRepresentable {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    func makeNSView(context: Context) -> WheelScrollView {
        let scroll = WheelScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .allowed
        let host = NSHostingView(rootView: content)
        scroll.documentView = host
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        return scroll
    }

    func updateNSView(_ scroll: WheelScrollView, context: Context) {
        guard let host = scroll.documentView as? NSHostingView<Content> else { return }
        host.rootView = content
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
    }
}

final class WheelScrollView: NSScrollView {
    /// How far one notch of a mouse wheel moves the row.
    static let notch: CGFloat = 16

    override func scrollWheel(with event: NSEvent) {
        let vertical = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
        if vertical, !event.hasPreciseScrollingDeltas, scrollSideways(by: -event.scrollingDeltaY * Self.notch) { return }
        // A trackpad's up and down belong to the notes.
        if vertical { nextResponder?.scrollWheel(with: event); return }
        super.scrollWheel(with: event)
    }

    /// Moves the row; false when there is nothing to scroll.
    @discardableResult
    func scrollSideways(by distance: CGFloat) -> Bool {
        guard let document = documentView else { return false }
        let clip = contentView
        let maxX = document.frame.width - clip.bounds.width
        guard maxX > 0 else { return false }
        var origin = clip.bounds.origin
        origin.x = min(max(origin.x + distance, 0), maxX)
        clip.scroll(to: origin)
        reflectScrolledClipView(clip)
        return true
    }
}
