import AppKit
import SwiftUI
import UniPDFCore

/// The slide tools in the header of the slide pane, as capsules in the style of Preview:
/// tools, shapes, image, then zoom.
struct SlideToolBar: View {
    let session: PDFSession
    let chooseImage: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { Color.studyAccent(for: colorScheme) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            groups(compactZoom: false)
            groups(compactZoom: true)
        }
    }

    private func groups(compactZoom: Bool) -> some View {
        HStack(spacing: 8) {
            ToolCapsule {
                toolButton(.select, "Select and move", symbol: "cursorarrow")
                toolButton(.pen, "Pen", symbol: "pencil.tip")
                iconButton("Highlighter", symbol: "highlighter", selected: session.tool == .highlight) { session.activateHighlighter() }
                    .help("Highlighter: select PDF text to highlight it. An existing text selection is highlighted right away.")
                toolButton(.eraser, "Eraser for pen and highlighter", symbol: "eraser")
                iconButton("Comment", symbol: "text.bubble", selected: session.tool == .comment) { session.activateComment() }
                    .help("Comment (⌥⌘M): select text or drag over it. On an empty spot you get an area, ⌥ always makes one.")
                toolButton(.text, session.keepsTextTool ? "Text box (locked)" : "Text box", symbol: "textbox")
                    .overlay(alignment: .bottomTrailing) {
                        if session.keepsTextTool {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(session.tool == .text ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                                .offset(x: -4, y: -4)
                                .accessibilityHidden(true)
                        }
                    }
            }
            shapeCapsule
            ToolCapsule {
                iconButton("Insert image", symbol: "photo", selected: false, action: chooseImage)
            }
            Spacer(minLength: 0)
            ToolCapsule {
                iconButton("Single page", symbol: "rectangle", selected: !session.scrollsContinuously) {
                    session.scrollsContinuously = false
                }
                .help("Single page: one slide after another")
                iconButton("Scroll continuously", symbol: "rectangle.split.1x2", selected: session.scrollsContinuously) {
                    session.scrollsContinuously = true
                }
                .help("Continuous: scroll through all slides one below the other")
            }
            if compactZoom {
                ToolCapsule {
                    Menu {
                        Button("Zoom In") { session.view?.zoomIn(nil) }
                        Button("Zoom Out") { session.view?.zoomOut(nil) }
                        Button("Zoom to Fit") { session.view?.autoScales = true }
                    } label: {
                        Image(systemName: "plus.magnifyingglass").frame(width: 30, height: 30)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Zoom").accessibilityLabel("Zoom")
                }
            } else {
                ToolCapsule {
                    iconButton("Zoom out", symbol: "minus.magnifyingglass", selected: false) { session.view?.zoomOut(nil) }
                    iconButton("Zoom to fit", symbol: "arrow.up.left.and.arrow.down.right", selected: false) { session.view?.autoScales = true }
                    iconButton("Zoom in", symbol: "plus.magnifyingglass", selected: false) { session.view?.zoomIn(nil) }
                }
            }
        }
    }

    /// The last shape, and beside it a menu of all shapes, like Preview's markup button.
    private var shapeCapsule: some View {
        var isActive = false
        if case .shape = session.tool { isActive = true }
        return ToolCapsule {
            iconButton("Shape: \(session.lastShape.label)", symbol: session.lastShape.symbol, selected: isActive) {
                pick(session.lastShape)
            }
            .help("Draw a shape: \(session.lastShape.label). Hold ⇧ while dragging to keep the proportions.")
            Divider().frame(height: 18).padding(.horizontal, 2)
            Menu {
                ForEach(SlideShape.allCases, id: \.self) { shape in
                    Button { pick(shape) } label: { Label(shape.label, systemImage: shape.symbol) }
                }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 30)
                    // Otherwise VoiceOver reads the symbol's name instead of what the menu does.
                    .accessibilityLabel("Choose Shape")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Choose a shape: rectangle, square, circle, oval or line")
            .accessibilityLabel("Choose Shape")
        }
    }

    private func toolButton(_ tool: AnnotationTool, _ label: LocalizedStringKey, symbol: String) -> some View {
        iconButton(label, symbol: symbol, selected: session.tool == tool) { session.tool = tool }
    }

    private func iconButton(_ label: LocalizedStringKey, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
                .background(selected ? accent : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func pick(_ shape: SlideShape) {
        session.lastShape = shape
        session.tool = .shape(shape)
    }
}

/// One group of tools on a capsule: glass on macOS 26, the bar material before.
private struct ToolCapsule<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let row = HStack(spacing: 2) { content }.padding(.horizontal, 4).frame(height: 36)
        if #available(macOS 26, *) {
            row.glassEffect(.regular, in: Capsule())
        } else {
            row.background(.bar, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        }
    }
}

/// The settings of the active tool or of the selected annotation, in the row beneath the tools.
struct AnnotationSettingsBar: View {
    let session: PDFSession
    var swatches = true
    @Environment(\.colorScheme) private var colorScheme

    private static let fontFamilies = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted()
    private static let fontSizes: [Double] = [10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 64, 72, 96]

    private var settings: AnnotationKind? {
        switch session.tool {
        case .pen, .shape: .stroke
        case .text: .text
        case .highlight: .highlight
        case .eraser: .eraser
        case .comment: .comment
        case .select: session.selectedKind
        }
    }

    var body: some View {
        // The room for the widest settings is always kept, so that the row does not reflow when a tool changes.
        ZStack(alignment: .leading) {
            settingsRow(.text, deletable: true, swatches: swatches).hidden()
            settingsRow(settings, deletable: session.selectedAnnotation != nil, swatches: swatches)
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .controlSize(.small)
    }

    private func toolLabel(_ symbol: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .frame(width: 24, height: 24)
            .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .contentShape(Rectangle())
    }

    // MARK: Settings

    private func settingsRow(_ kind: AnnotationKind?, deletable: Bool, swatches: Bool) -> some View {
        HStack(spacing: 10) {
            // First, so that the other settings stay where they are when it appears.
            if deletable {
                Button { session.overlay?.deleteSelection() } label: { Image(systemName: "trash").frame(height: 24) }
                    .help("Delete the selection (⌫)").accessibilityLabel("Delete Selection")
            }
            switch kind {
            case .stroke:
                // Needs less room than text, so the swatches always fit.
                lineWidthPicker
                colors(swatches: true)
            case .text:
                textToolLock
                fontControls
                colors(swatches: swatches)
            case .highlight:
                colors(swatches: true, highlighter: true)
            case .eraser:
                Picker("Eraser mode", selection: Binding(get: { session.style.erasesWholeStrokes },
                                                         set: { session.style.erasesWholeStrokes = $0 })) {
                    Text("Precise").tag(false)
                    Text("Stroke").tag(true)
                }
                // A pop-up like the size: a segmented control inside ViewThatFits ends in an AppKit constraint loop.
                .labelsHidden().fixedSize()
                .help("Precise removes only what the eraser touches, whole characters for highlights. Stroke removes every stroke and highlight it touches entirely.")
                eraserSizePicker
            case .comment:
                commentColors
                if session.tool == .comment {
                    Text("Drag over text to comment on the passage, on an empty spot for an area")
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
            case .image, nil:
                EmptyView()
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AnnotationStyle, Value>) -> Binding<Value> {
        Binding(
            get: { session.style[keyPath: keyPath] },
            set: {
                session.style[keyPath: keyPath] = $0
                session.overlay?.applyStyle()
            }
        )
    }

    private var lineWidthPicker: some View {
        let unit = session.slideUnit
        let widths = [2, 4, 8].map { $0 * unit }
        let current = session.style.lineWidth
        let nearest = widths.min { abs($0 - current) < abs($1 - current) } ?? current
        return Picker("Line width", selection: Binding(get: { nearest }, set: { binding(\.lineWidth).wrappedValue = $0 })) {
            Text("Fine").tag(widths[0])
            Text("Medium").tag(widths[1])
            Text("Bold").tag(widths[2])
        }
        .labelsHidden().fixedSize().help("Line width")
    }

    private var eraserSizePicker: some View {
        let unit = session.slideUnit
        let radii = [5, 10, 20].map { $0 * unit }
        let current = session.style.eraserRadius
        let nearest = radii.min { abs($0 - current) < abs($1 - current) } ?? current
        return Picker("Eraser size", selection: Binding(get: { nearest }, set: { session.style.eraserRadius = $0 })) {
            Text("Small").tag(radii[0])
            Text("Medium").tag(radii[1])
            Text("Large").tag(radii[2])
        }
        .labelsHidden().fixedSize().help("Eraser size")
    }

    /// Pastel, like the comments themselves.
    private var commentColors: some View {
        HStack(spacing: 2) {
            ForEach(CommentColor.allCases, id: \.self) { color in
                let isCurrent = session.style.commentColor == color
                Button { binding(\.commentColor).wrappedValue = color } label: {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: color.pastel.nsColor))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: color.strong.nsColor).opacity(0.6), lineWidth: 1))
                        .frame(width: 17, height: 15)
                        .padding(3)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isCurrent ? Color.primary : .clear, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .help(color.label)
                .accessibilityLabel("Comment color \(color.label)")
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
    }

    private func colors(swatches: Bool, highlighter: Bool = false) -> some View {
        let palette: [(label: String, value: AnnotationColor)] = highlighter ? [
            (String(localized: "Yellow"), PDFTextHighlight.yellow),
            (String(localized: "Green"), AnnotationColor(red: 0.25, green: 0.85, blue: 0.4)),
            (String(localized: "Pink"), AnnotationColor(red: 1, green: 0.4, blue: 0.65)),
            (String(localized: "Blue"), AnnotationColor(red: 0.25, green: 0.65, blue: 1))
        ] : InkColor.allCases.map { ($0.label, AnnotationColor($0)) }
        let keyPath: WritableKeyPath<AnnotationStyle, AnnotationColor> = highlighter ? \.highlightColor : \.color
        let current = session.style[keyPath: keyPath]
        return HStack(spacing: 4) {
            if swatches {
                ForEach(palette, id: \.label) { option in
                    Button { binding(keyPath).wrappedValue = option.value } label: {
                        Circle().fill(Color(nsColor: option.value.nsColor))
                            .frame(width: 15, height: 15)
                            // Graphite would vanish on a dark bar.
                            .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5))
                            .padding(3)
                            .overlay(Circle().strokeBorder(current == option.value ? Color.primary : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain).help(option.label).accessibilityLabel(option.label)
                    .accessibilityAddTraits(current == option.value ? .isSelected : [])
                }
            }
            ColorPicker("Color", selection: Binding(
                get: { Color(nsColor: session.style[keyPath: keyPath].nsColor) },
                set: { binding(keyPath).wrappedValue = AnnotationColor(NSColor($0)) }
            ), supportsOpacity: !highlighter)
            .labelsHidden().help("Choose any color")
        }
    }

    private var textToolLock: some View {
        let isOn = session.keepsTextTool
        return Button { session.toggleTextToolLock() } label: {
            let green = Color.studyAccent(for: colorScheme)
            Image(systemName: isOn ? "lock.fill" : "lock.open")
                .frame(width: 24, height: 24)
                .background(isOn ? green.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(isOn ? green : .primary)
                .contentShape(Rectangle())
        }
        .help(isOn ? String(localized: "The text tool stays active: every click on the slide starts a new text box. Click to release.")
                   : String(localized: "Lock the text tool to write several text boxes in a row"))
        .accessibilityLabel("Lock Text Tool")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var fontControls: some View {
        HStack(spacing: 6) {
            Picker("Font", selection: binding(\.text.fontFamily)) {
                Text("System").tag(String?.none)
                Divider()
                ForEach(Self.fontFamilies, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden().frame(maxWidth: 100).help("Font")

            Menu {
                ForEach(Self.fontSizes, id: \.self) { size in
                    Button("\(Int(size)) pt") { binding(\.text.size).wrappedValue = size }
                }
            } label: {
                Text("\(Int(session.style.text.size)) pt").monospacedDigit()
            }
            .menuStyle(.borderlessButton).fixedSize().help("Font size")
            .accessibilityLabel("Font size, \(Int(session.style.text.size)) points")
            Stepper("Font size", value: binding(\.text.size), in: 6...400).labelsHidden().help("Change the font size")

            styleToggle(\.text.bold, symbol: "bold", label: "Bold")
            styleToggle(\.text.italic, symbol: "italic", label: "Italic")
            styleToggle(\.text.underline, symbol: "underline", label: "Underline")
        }
    }

    private func styleToggle(_ keyPath: WritableKeyPath<AnnotationStyle, Bool>, symbol: String, label: LocalizedStringKey) -> some View {
        let isOn = session.style[keyPath: keyPath]
        return Button { binding(keyPath).wrappedValue.toggle() } label: { toolLabel(symbol, selected: isOn) }
            .help(label).accessibilityLabel(label)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
