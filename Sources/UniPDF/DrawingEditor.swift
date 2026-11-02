import SwiftUI
import UniPDFCore

struct DrawingEditor: View {
    @Binding var elements: [InkElement]
    @State private var tool = InkTool.pen
    @State private var color = InkColor.graphite
    @State private var width = 2.5
    @State private var draft: InkElement?
    @State private var removed: [InkElement] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(InkTool.allCases, id: \.self) { option in
                    Button { tool = option } label: {
                        Image(systemName: option.symbol).frame(width: 24, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .background(tool == option ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(tool == option ? Color.accentColor : .primary)
                    .help(option.label)
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(tool == option ? .isSelected : [])
                }
                Spacer(minLength: 4)
                Button {
                    if let element = elements.popLast() { removed.append(element) }
                } label: { Image(systemName: "arrow.uturn.backward") }
                .disabled(elements.isEmpty).help("Letztes Element entfernen").accessibilityLabel("Letztes Element entfernen")
                Button {
                    if let element = removed.popLast() { elements.append(element) }
                } label: { Image(systemName: "arrow.uturn.forward") }
                .disabled(removed.isEmpty).help("Element wiederherstellen").accessibilityLabel("Element wiederherstellen")
            }
            .buttonStyle(.borderless)

            HStack(spacing: 10) {
                ForEach(InkColor.allCases, id: \.self) { option in
                    Button { color = option } label: {
                        Circle().fill(Color(nsColor: InkRenderer.color(option)))
                            .frame(width: 17, height: 17)
                            .padding(3)
                            .overlay(Circle().strokeBorder(color == option ? Color.primary : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain).help(option.label).accessibilityLabel(option.label)
                    .accessibilityAddTraits(color == option ? .isSelected : [])
                }
                Spacer()
                Picker("Strichstärke", selection: $width) {
                    Text("Fein").tag(2.5)
                    Text("Mittel").tag(5.0)
                    Text("Breit").tag(9.0)
                }.labelsHidden().frame(width: 95).help("Strichstärke")
            }

            GeometryReader { geometry in
                Canvas { context, size in
                    context.withCGContext { cg in
                        InkRenderer.draw(elements + (draft.map { [$0] } ?? []), in: cg,
                                         rect: CGRect(origin: .zero, size: size))
                    }
                }
                .background(.white)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = InkPoint(x: min(max(value.location.x / geometry.size.width * 800, 0), 800),
                                             y: min(max(value.location.y / geometry.size.height * 500, 0), 500))
                        if draft == nil { draft = InkElement(tool: tool, color: color, width: width, points: [point]) }
                        else if tool == .pen { draft?.points.append(point) }
                        else if let first = draft?.points.first { draft?.points = [first, point] }
                    }
                    .onEnded { _ in
                        if let draft { elements.append(draft); removed.removeAll() }
                        draft = nil
                    })
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.black.opacity(0.15)))
                .accessibilityLabel("Zeichenfläche für \(tool.label). Mit Maus oder Trackpad zeichnen.")
            }
            .aspectRatio(1.6, contentMode: .fit)
            Text("Mit Maus, Trackpad oder Grafiktablett zeichnen.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
