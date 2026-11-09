import SwiftUI
import UniPDFCore

/// What a button of the formula palette puts into the notes.
enum FormulaInsertion: Hashable {
    /// A character such as ∈, which also fits into ordinary text.
    case symbol(String)
    /// Notation such as `\frac{‸}{}`, which belongs in a formula; ‸ is where the caret goes.
    case template(String)
    case superscript, `subscript`
    /// A formula on a line of its own.
    case block
}

struct FormulaTopic: Identifiable, Hashable {
    struct Item: Hashable {
        var label: String
        var help: String
        var insertion: FormulaInsertion

        static func symbol(_ character: String, _ help: String) -> Item { Item(label: character, help: help, insertion: .symbol(character)) }
        static func template(_ label: String, _ help: String, _ notation: String) -> Item {
            Item(label: label, help: help, insertion: .template(notation))
        }
    }

    var id: String { name }
    var name: String
    var symbol: String
    var items: [Item]

    static let all: [FormulaTopic] = [
        FormulaTopic(name: "Grundlagen", symbol: "plus.forwardslash.minus", items: [
            .symbol("±", "Plus-Minus"), .symbol("×", "Mal"), .symbol("·", "Mal (Punkt)"), .symbol("÷", "Geteilt"),
            .symbol("≠", "Ungleich"), .symbol("≈", "Ungefähr gleich"), .symbol("≤", "Kleiner gleich"),
            .symbol("≥", "Größer gleich"), .symbol("≡", "Identisch, kongruent"), .symbol("∝", "Proportional"),
            .symbol("∞", "Unendlich"), .symbol("°", "Grad"),
            .template("√", "Wurzel", "\\sqrt{‸}"), .template("ⁿ√", "n-te Wurzel", "\\sqrt[n]{‸}"),
            .template("|x|", "Betrag", "|‸|"), .template("%", "Prozent", "‸ \\%")
        ]),
        FormulaTopic(name: "Mengenlehre", symbol: "circle.circle", items: [
            .symbol("∈", "Element von"), .symbol("∉", "Kein Element von"), .symbol("⊂", "Echte Teilmenge"),
            .symbol("⊆", "Teilmenge"), .symbol("⊃", "Echte Obermenge"), .symbol("⊇", "Obermenge"),
            .symbol("⊈", "Keine Teilmenge"), .symbol("∪", "Vereinigung"), .symbol("∩", "Schnitt"),
            .symbol("∖", "Differenz"), .symbol("∅", "Leere Menge"), .symbol("∁", "Komplement"),
            .symbol("ℕ", "Natürliche Zahlen"), .symbol("ℤ", "Ganze Zahlen"), .symbol("ℚ", "Rationale Zahlen"),
            .symbol("ℝ", "Reelle Zahlen"), .symbol("ℂ", "Komplexe Zahlen"), .symbol("𝒫", "Potenzmenge"),
            .template("{ }", "Menge", "\\{ ‸ \\}"), .template("{x | }", "Menge mit Bedingung", "\\{ x \\mid ‸ \\}"),
            .symbol("∀", "Für alle"), .symbol("∃", "Es existiert"), .symbol("|", "Mit der Eigenschaft"),
            .template("⋃", "Große Vereinigung", "\\bigcup_{i=1}^{n} ‸"), .template("⋂", "Großer Schnitt", "\\bigcap_{i=1}^{n} ‸")
        ]),
        FormulaTopic(name: "Logik", symbol: "checkmark.circle", items: [
            .symbol("∧", "Und"), .symbol("∨", "Oder"), .symbol("¬", "Nicht"), .symbol("⇒", "Daraus folgt"),
            .symbol("⇔", "Genau dann, wenn"), .symbol("→", "Pfeil, Abbildung"), .symbol("↔", "Äquivalent"),
            .symbol("∀", "Für alle"), .symbol("∃", "Es existiert"), .symbol("∄", "Es existiert kein"),
            .symbol("⊕", "Exklusives Oder"), .symbol("⊤", "Wahr"), .symbol("⊥", "Falsch"),
            .symbol("⊢", "Herleitbar"), .symbol("⊨", "Folgt semantisch"), .symbol("≡", "Äquivalent")
        ]),
        FormulaTopic(name: "Analysis", symbol: "function", items: [
            .template("∑", "Summe", "\\sum_{i=1}^{n} ‸"), .template("∏", "Produkt", "\\prod_{i=1}^{n} ‸"),
            .template("∫", "Integral", "\\int ‸ \\,dx"), .template("∫ₐᵇ", "Bestimmtes Integral", "\\int_{a}^{b} ‸ \\,dx"),
            .template("lim", "Grenzwert", "\\lim_{x \\to ‸}"), .template("d/dx", "Ableitung", "\\frac{d}{dx} ‸"),
            .symbol("∂", "Partielle Ableitung"), .symbol("∇", "Nabla, Gradient"), .symbol("Δ", "Delta, Differenz"),
            .symbol("′", "Strich (Ableitung)"), .symbol("∞", "Unendlich"), .symbol("→", "Gegen"),
            .symbol("↦", "Wird abgebildet auf"), .template("e^x", "Exponentialfunktion", "e^{‸}"),
            .template("ln", "Natürlicher Logarithmus", "\\ln(‸)"), .template("sin", "Sinus", "\\sin(‸)"),
            .template("cos", "Kosinus", "\\cos(‸)")
        ]),
        FormulaTopic(name: "Lineare Algebra", symbol: "square.grid.3x3", items: [
            .template("v⃗", "Vektor", "\\vec{‸}"), .template("⟨,⟩", "Skalarprodukt", "\\langle ‸ \\rangle"),
            .template("‖‖", "Norm", "\\|‸\\|"), .template("Aᵀ", "Transponiert", "‸^{T}"),
            .template("A⁻¹", "Inverse", "‸^{-1}"), .template("det", "Determinante", "\\det(‸)"),
            .template("ℝⁿ", "n-dimensionaler Raum", "ℝ^{‸}"), .symbol("·", "Skalarprodukt"),
            .symbol("×", "Kreuzprodukt"), .symbol("⊗", "Tensorprodukt"), .symbol("⊥", "Orthogonal"),
            .symbol("∥", "Parallel"), .symbol("λ", "Eigenwert"), .template("dim", "Dimension", "\\dim(‸)"),
            .template("ker", "Kern", "\\ker(‸)"), .symbol("∘", "Verkettung")
        ]),
        FormulaTopic(name: "Stochastik", symbol: "chart.bar", items: [
            .template("P()", "Wahrscheinlichkeit", "P(‸)"), .template("P(A|B)", "Bedingte Wahrscheinlichkeit", "P(‸ \\mid B)"),
            .template("E[]", "Erwartungswert", "\\mathbb{E}[‸]"), .template("Var", "Varianz", "\\Var(‸)"),
            .symbol("μ", "Mittelwert"), .symbol("σ", "Standardabweichung"), .template("σ²", "Varianz", "σ^{2}"),
            .template("x̄", "Stichprobenmittel", "\\bar{‸}"), .symbol("∼", "Verteilt nach"),
            .template("n!", "Fakultät", "‸!"), .template("(n k)", "Binomialkoeffizient", "\\binom{n}{‸}"),
            .symbol("∩", "Und (Schnitt)"), .symbol("∪", "Oder (Vereinigung)"), .symbol("Ω", "Ergebnisraum")
        ]),
        FormulaTopic(name: "Griechisch", symbol: "textformat.alt", items:
            ["α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "ι", "κ", "λ", "μ", "ν", "ξ", "π", "ρ", "σ", "τ", "φ", "χ", "ψ", "ω",
             "Γ", "Δ", "Θ", "Λ", "Ξ", "Π", "Σ", "Φ", "Ψ", "Ω"].map { .symbol($0, "Griechischer Buchstabe \($0)") }
        ),
        FormulaTopic(name: "Pfeile", symbol: "arrow.right", items: [
            .symbol("→", "Nach rechts"), .symbol("←", "Nach links"), .symbol("↔", "Beidseitig"), .symbol("⇒", "Folgt"),
            .symbol("⇐", "Folgt aus"), .symbol("⇔", "Äquivalent"), .symbol("↦", "Abbildung"), .symbol("↑", "Nach oben"),
            .symbol("↓", "Nach unten"), .symbol("⇌", "Gleichgewicht"), .symbol("↗", "Steigt"), .symbol("↘", "Fällt")
        ])
    ]
}

/// Symbols by topic, plus superscript, subscript and fractions. Writes into the notes at the caret.
struct FormulaPalette: View {
    let insert: (FormulaInsertion) -> Void
    /// Whether the caret is inside a formula, so the palette can say where things go.
    let isInFormula: Bool
    @AppStorage("formulaTopic") private var topicName = FormulaTopic.all[1].name

    private var topic: FormulaTopic { FormulaTopic.all.first { $0.name == topicName } ?? FormulaTopic.all[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { insert(.block) } label: { Label("Formelblock", systemImage: "plus.rectangle") }
                    .help("Neuen Formelblock in die Mitschrift einfügen. Formeln stehen zwischen $$ … $$, im Satz zwischen $ … $.")
                Picker("Themengebiet", selection: $topicName) {
                    ForEach(FormulaTopic.all) { topic in Label(topic.name, systemImage: topic.symbol).tag(topic.name) }
                }
                .labelsHidden().fixedSize().help("Themengebiet der Zeichen")
                Spacer(minLength: 0)
                structureButton("x²", "Hochgestellt", .superscript)
                structureButton("xₙ", "Tiefgestellt", .subscript)
                structureButton("a⁄b", "Bruch", .template("\\frac{‸}{}"))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 60), spacing: 4)], alignment: .leading, spacing: 4) {
                ForEach(topic.items, id: \.self) { item in
                    Button { insert(item.insertion) } label: {
                        Text(item.label)
                            .font(.system(size: 15))
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PaletteButtonStyle())
                    .help(item.help)
                    .accessibilityLabel(item.help)
                }
            }
            Text(isInFormula ? "Wird in die Formel am Cursor eingefügt."
                             : "Zeichen landen am Cursor. Hoch, tief und Vorlagen werden zur Formel, das Wort davor wird ihre Basis.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func structureButton(_ label: String, _ help: String, _ insertion: FormulaInsertion) -> some View {
        Button { insert(insertion) } label: {
            Text(label).font(.system(size: 14)).frame(minWidth: 34, minHeight: 26).contentShape(Rectangle())
        }
        .buttonStyle(PaletteButtonStyle())
        .help(help).accessibilityLabel(help)
    }
}

private struct PaletteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PaletteButton(configuration: configuration)
    }

    private struct PaletteButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(Color.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.08 : 0.04),
                            in: RoundedRectangle(cornerRadius: 6))
                .onHover { hovering = $0 }
        }
    }
}
