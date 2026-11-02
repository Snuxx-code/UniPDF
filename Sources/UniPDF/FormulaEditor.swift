import SwiftUI
import UniPDFCore

struct FormulaEditor: View {
    @Binding var formula: String
    @State private var showsHelp = false
    private let templates: [(String, String)] = [
        ("Bruch", "\\frac{a}{b}"), ("Potenz", "x^{2}"), ("Index", "a_{n}"),
        ("Wurzel", "\\sqrt{x}"), ("Summe", "\\sum_{i=1}^{n} x_{i}"), ("Integral", "\\int f(x) dx")
    ]
    private let symbols = ["α", "β", "γ", "δ", "θ", "λ", "μ", "π", "σ", "Δ", "∞", "±", "×", "·", "≤", "≥", "≠", "≈", "→"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Menu("Vorlage einfügen") {
                    ForEach(templates, id: \.0) { label, value in
                        Button(label) { formula += (formula.isEmpty ? "" : " ") + value }
                    }
                }.fixedSize()
                Menu("Zeichen") {
                    ForEach(symbols, id: \.self) { symbol in Button(symbol) { formula += symbol } }
                }.fixedSize()
                Spacer()
                Button { showsHelp.toggle() } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(.plain).help("Unterstützte Formelnotation").accessibilityLabel("Hilfe zur Formelnotation")
            }
            TextField("z. B. E = m c^{2}", text: $formula, axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...8).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Formel eingeben")
            if !formula.isEmpty {
                Text(AttributedString(MathNotation.formatted(formula)))
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                    .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 8))
                    .environment(\.colorScheme, .light)
                    .textSelection(.enabled)
            }
            if showsHelp {
                Text("Unterstützt: x^{2}, a_{n}, \\frac{a}{b}, \\sqrt{x}, \\alpha, \\sum und \\int. Einfache Formelnotation, kein vollständiges LaTeX. Unbekannte Befehle bleiben als Text sichtbar.")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}
