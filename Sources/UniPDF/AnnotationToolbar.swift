import AppKit
import SwiftUI
import UniPDFCore

/// The action row above the slide: tools on the left, settings of the active tool or selection on the right.
struct AnnotationToolbar: View {
    let session: PDFSession
    let chooseImage: () -> Void

    private static let fontFamilies = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted()
    private static let fontSizes: [Double] = [10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 64, 72, 96]

    private var settings: AnnotationKind? {
        switch session.tool {
        case .pen, .shape: .stroke
        case .text: .text
        case .highlight: .highlight
        case .select: session.selectedKind
        }
    }

    var body: some View {
        // The room for the widest settings is always kept, so that the slide does not change size when a tool does.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                tools
                Spacer(minLength: 8)
                settingsArea(swatches: true, alignment: .trailing)
            }
            HStack(spacing: 12) {
                tools
                Spacer(minLength: 8)
                settingsArea(swatches: false, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 8) {
                tools
                settingsArea(swatches: true, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 8) {
                tools
                settingsArea(swatches: false, alignment: .leading)
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private func settingsArea(swatches: Bool, alignment: Alignment) -> some View {
        ZStack(alignment: alignment) {
            settingsRow(.text, deletable: true, swatches: swatches).hidden()
            settingsRow(settings, deletable: session.selectedAnnotation != nil, swatches: swatches)
        }
        .controlSize(.small)
    }

    // MARK: Tools

    private var tools: some View {
        HStack(spacing: 2) {
            toolButton(.select, symbol: "cursorarrow", label: "Auswählen und verschieben")
            toolButton(.pen, symbol: "pencil.tip", label: "Stift")
            Button { session.activateHighlighter() } label: {
                toolLabel("highlighter", selected: session.tool == .highlight)
            }
            .help("Textmarker: PDF-Text auswählen und hervorheben. Eine bestehende Textauswahl wird sofort markiert.")
            .accessibilityLabel("Textmarker")
            .accessibilityAddTraits(session.tool == .highlight ? .isSelected : [])
            toolButton(.text, symbol: "textbox", label: "Textfeld")
            shapeMenu
            Button(action: chooseImage) { toolLabel("photo", selected: false) }
                .help("Bild einfügen").accessibilityLabel("Bild einfügen")
        }
    }

    private func toolButton(_ tool: AnnotationTool, symbol: String, label: String) -> some View {
        Button { session.tool = tool } label: { toolLabel(symbol, selected: session.tool == tool) }
            .help(label).accessibilityLabel(label)
            .accessibilityAddTraits(session.tool == tool ? .isSelected : [])
    }

    private func toolLabel(_ symbol: String, selected: Bool) -> some View {
        Image(systemName: symbol)
            .frame(width: 24, height: 24)
            .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(selected ? Color.accentColor : .primary)
            .contentShape(Rectangle())
    }

    private var shapeMenu: some View {
        var isActive = false
        if case .shape = session.tool { isActive = true }
        return Menu {
            ForEach(SlideShape.allCases, id: \.self) { shape in
                Button { pick(shape) } label: { Label(shape.label, systemImage: shape.symbol) }
            }
        } label: {
            toolLabel(session.lastShape.symbol, selected: isActive)
        } primaryAction: {
            pick(session.lastShape)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        // The menu ignores its label's background.
        .background(isActive ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .help("Form einfügen: Rechteck, Quadrat, Kreis, Oval oder Linie. ⇧ beim Ziehen hält die Proportionen.")
        .accessibilityLabel("Form einfügen, zuletzt \(session.lastShape.label)")
    }

    private func pick(_ shape: SlideShape) {
        session.lastShape = shape
        session.tool = .shape(shape)
    }

    // MARK: Settings

    private func settingsRow(_ kind: AnnotationKind?, deletable: Bool, swatches: Bool) -> some View {
        HStack(spacing: 10) {
            // First, so that the other settings stay where they are when it appears.
            if deletable {
                Button { session.overlay?.deleteSelection() } label: { Image(systemName: "trash").frame(height: 24) }
                    .help("Auswahl löschen (⌫)").accessibilityLabel("Auswahl löschen")
            }
            switch kind {
            case .stroke:
                // Needs less room than text, so the swatches always fit.
                lineWidthPicker
                colors(swatches: true)
            case .text:
                fontControls
                colors(swatches: swatches)
            case .highlight:
                colors(swatches: true, highlighter: true)
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
        return Picker("Strichstärke", selection: Binding(get: { nearest }, set: { binding(\.lineWidth).wrappedValue = $0 })) {
            Text("Fein").tag(widths[0])
            Text("Mittel").tag(widths[1])
            Text("Breit").tag(widths[2])
        }
        .labelsHidden().fixedSize().help("Strichstärke")
    }

    private func colors(swatches: Bool, highlighter: Bool = false) -> some View {
        let palette: [(label: String, value: AnnotationColor)] = highlighter ? [
            ("Gelb", PDFTextHighlight.yellow),
            ("Grün", AnnotationColor(red: 0.25, green: 0.85, blue: 0.4)),
            ("Pink", AnnotationColor(red: 1, green: 0.4, blue: 0.65)),
            ("Blau", AnnotationColor(red: 0.25, green: 0.65, blue: 1))
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
            ColorPicker("Farbe", selection: Binding(
                get: { Color(nsColor: session.style[keyPath: keyPath].nsColor) },
                set: { binding(keyPath).wrappedValue = AnnotationColor(NSColor($0)) }
            ), supportsOpacity: !highlighter)
            .labelsHidden().help("Beliebige Farbe wählen")
        }
    }

    private var fontControls: some View {
        HStack(spacing: 6) {
            Picker("Schriftart", selection: binding(\.text.fontFamily)) {
                Text("System").tag(String?.none)
                Divider()
                ForEach(Self.fontFamilies, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .labelsHidden().frame(maxWidth: 100).help("Schriftart")

            Menu {
                ForEach(Self.fontSizes, id: \.self) { size in
                    Button("\(Int(size)) pt") { binding(\.text.size).wrappedValue = size }
                }
            } label: {
                Text("\(Int(session.style.text.size)) pt").monospacedDigit()
            }
            .menuStyle(.borderlessButton).fixedSize().help("Schriftgröße")
            .accessibilityLabel("Schriftgröße, \(Int(session.style.text.size)) Punkt")
            Stepper("Schriftgröße", value: binding(\.text.size), in: 6...400).labelsHidden().help("Schriftgröße ändern")

            styleToggle(\.text.bold, symbol: "bold", label: "Fett")
            styleToggle(\.text.italic, symbol: "italic", label: "Kursiv")
            styleToggle(\.text.underline, symbol: "underline", label: "Unterstrichen")
        }
    }

    private func styleToggle(_ keyPath: WritableKeyPath<AnnotationStyle, Bool>, symbol: String, label: String) -> some View {
        let isOn = session.style[keyPath: keyPath]
        return Button { binding(keyPath).wrappedValue.toggle() } label: { toolLabel(symbol, selected: isOn) }
            .help(label).accessibilityLabel(label)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
