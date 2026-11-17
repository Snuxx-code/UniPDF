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

        static func symbol(_ character: String, _ help: String.LocalizationValue) -> Item {
            Item(label: character, help: String(localized: help), insertion: .symbol(character))
        }
        static func template(_ label: String, _ help: String.LocalizationValue, _ notation: String) -> Item {
            Item(label: label, help: String(localized: help), insertion: .template(notation))
        }
    }

    /// Stays the same in every language, so that the chosen topic is remembered.
    var id: String
    var name: String
    var symbol: String
    var items: [Item]

    static let all: [FormulaTopic] = [
        FormulaTopic(id: "basics", name: String(localized: "Basics"), symbol: "plus.forwardslash.minus", items: [
            .symbol("±", "Plus-minus"), .symbol("×", "Times"), .symbol("·", "Times (dot)"), .symbol("÷", "Divided by"),
            .symbol("≠", "Not equal"), .symbol("≈", "Approximately equal"), .symbol("≤", "Less than or equal"),
            .symbol("≥", "Greater than or equal"), .symbol("≡", "Identical, congruent"), .symbol("∝", "Proportional"),
            .symbol("∞", "Infinity"), .symbol("°", "Degree"),
            .template("√", "Square root", "\\sqrt{‸}"), .template("ⁿ√", "nth root", "\\sqrt[n]{‸}"),
            .template("|x|", "Absolute value", "|‸|"), .template("%", "Percent", "‸ \\%")
        ]),
        FormulaTopic(id: "sets", name: String(localized: "Set Theory"), symbol: "circle.circle", items: [
            .symbol("∈", "Element of"), .symbol("∉", "Not an element of"), .symbol("⊂", "Proper subset"),
            .symbol("⊆", "Subset"), .symbol("⊃", "Proper superset"), .symbol("⊇", "Superset"),
            .symbol("⊈", "Not a subset"), .symbol("∪", "Union"), .symbol("∩", "Intersection"),
            .symbol("∖", "Difference"), .symbol("∅", "Empty set"), .symbol("∁", "Complement"),
            .symbol("ℕ", "Natural numbers"), .symbol("ℤ", "Integers"), .symbol("ℚ", "Rational numbers"),
            .symbol("ℝ", "Real numbers"), .symbol("ℂ", "Complex numbers"), .symbol("𝒫", "Power set"),
            .template("{ }", "Set", "\\{ ‸ \\}"), .template("{x | }", "Set with a condition", "\\{ x \\mid ‸ \\}"),
            .symbol("∀", "For all"), .symbol("∃", "There exists"), .symbol("|", "Such that"),
            .template("⋃", "Big union", "\\bigcup_{i=1}^{n} ‸"), .template("⋂", "Big intersection", "\\bigcap_{i=1}^{n} ‸")
        ]),
        FormulaTopic(id: "logic", name: String(localized: "Logic"), symbol: "checkmark.circle", items: [
            .symbol("∧", "And"), .symbol("∨", "Or"), .symbol("¬", "Not"), .symbol("⇒", "Implies"),
            .symbol("⇔", "If and only if"), .symbol("→", "Arrow, map"), .symbol("↔", "Equivalent"),
            .symbol("∀", "For all"), .symbol("∃", "There exists"), .symbol("∄", "There does not exist"),
            .symbol("⊕", "Exclusive or"), .symbol("⊤", "True"), .symbol("⊥", "False"),
            .symbol("⊢", "Derivable"), .symbol("⊨", "Semantically entails"), .symbol("≡", "Equivalent")
        ]),
        FormulaTopic(id: "analysis", name: String(localized: "Calculus"), symbol: "function", items: [
            .template("∑", "Sum", "\\sum_{i=1}^{n} ‸"), .template("∏", "Product", "\\prod_{i=1}^{n} ‸"),
            .template("∫", "Integral", "\\int ‸ \\,dx"), .template("∫ₐᵇ", "Definite integral", "\\int_{a}^{b} ‸ \\,dx"),
            .template("lim", "Limit", "\\lim_{x \\to ‸}"), .template("d/dx", "Derivative", "\\frac{d}{dx} ‸"),
            .symbol("∂", "Partial derivative"), .symbol("∇", "Nabla, gradient"), .symbol("Δ", "Delta, difference"),
            .symbol("′", "Prime (derivative)"), .symbol("∞", "Infinity"), .symbol("→", "Tends to"),
            .symbol("↦", "Maps to"), .template("e^x", "Exponential function", "e^{‸}"),
            .template("ln", "Natural logarithm", "\\ln(‸)"), .template("sin", "Sine", "\\sin(‸)"),
            .template("cos", "Cosine", "\\cos(‸)")
        ]),
        FormulaTopic(id: "linear-algebra", name: String(localized: "Linear Algebra"), symbol: "square.grid.3x3", items: [
            .template("v⃗", "Vector", "\\vec{‸}"), .template("⟨,⟩", "Inner product", "\\langle ‸ \\rangle"),
            .template("‖‖", "Norm", "\\|‸\\|"), .template("Aᵀ", "Transpose", "‸^{T}"),
            .template("A⁻¹", "Inverse", "‸^{-1}"), .template("det", "Determinant", "\\det(‸)"),
            .template("ℝⁿ", "n-dimensional space", "ℝ^{‸}"), .symbol("·", "Dot product"),
            .symbol("×", "Cross product"), .symbol("⊗", "Tensor product"), .symbol("⊥", "Orthogonal"),
            .symbol("∥", "Parallel"), .symbol("λ", "Eigenvalue"), .template("dim", "Dimension", "\\dim(‸)"),
            .template("ker", "Kernel", "\\ker(‸)"), .symbol("∘", "Composition")
        ]),
        FormulaTopic(id: "stochastics", name: String(localized: "Probability"), symbol: "chart.bar", items: [
            .template("P()", "Probability", "P(‸)"), .template("P(A|B)", "Conditional probability", "P(‸ \\mid B)"),
            .template("E[]", "Expected value", "\\mathbb{E}[‸]"), .template("Var", "Variance", "\\Var(‸)"),
            .symbol("μ", "Mean"), .symbol("σ", "Standard deviation"), .template("σ²", "Variance", "σ^{2}"),
            .template("x̄", "Sample mean", "\\bar{‸}"), .symbol("∼", "Distributed as"),
            .template("n!", "Factorial", "‸!"), .template("(n k)", "Binomial coefficient", "\\binom{n}{‸}"),
            .symbol("∩", "And (intersection)"), .symbol("∪", "Or (union)"), .symbol("Ω", "Sample space")
        ]),
        FormulaTopic(id: "greek", name: String(localized: "Greek"), symbol: "textformat.alt", items:
            ["α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "ι", "κ", "λ", "μ", "ν", "ξ", "π", "ρ", "σ", "τ", "φ", "χ", "ψ", "ω",
             "Γ", "Δ", "Θ", "Λ", "Ξ", "Π", "Σ", "Φ", "Ψ", "Ω"].map { .symbol($0, "Greek letter \($0)") }
        ),
        FormulaTopic(id: "arrows", name: String(localized: "Arrows"), symbol: "arrow.right", items: [
            .symbol("→", "Right"), .symbol("←", "Left"), .symbol("↔", "Both ways"), .symbol("⇒", "Implies"),
            .symbol("⇐", "Is implied by"), .symbol("⇔", "Equivalent"), .symbol("↦", "Maps to"), .symbol("↑", "Up"),
            .symbol("↓", "Down"), .symbol("⇌", "Equilibrium"), .symbol("↗", "Rises"), .symbol("↘", "Falls")
        ])
    ]
}

/// Symbols by topic, plus superscript, subscript and fractions. Writes into the notes at the caret.
struct FormulaPalette: View {
    let insert: (FormulaInsertion) -> Void
    /// Whether the caret is inside a formula, so the palette can say where things go.
    let isInFormula: Bool
    @AppStorage("formulaTopicID") private var topicID = FormulaTopic.all[1].id

    private var topic: FormulaTopic { FormulaTopic.all.first { $0.id == topicID } ?? FormulaTopic.all[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { insert(.block) } label: { Label("Formula Block", systemImage: "plus.rectangle") }
                    .help("Insert a new formula block into the notes. Formulas go between $$ … $$, or between $ … $ within a sentence.")
                Picker("Topic", selection: $topicID) {
                    ForEach(FormulaTopic.all) { topic in Label(topic.name, systemImage: topic.symbol).tag(topic.id) }
                }
                .labelsHidden().fixedSize().help("Topic of the symbols")
                Spacer(minLength: 0)
                structureButton("x²", "Superscript", .superscript)
                structureButton("xₙ", "Subscript", .subscript)
                structureButton("a⁄b", "Fraction", .template("\\frac{‸}{}"))
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
            Text(isInFormula ? String(localized: "Goes into the formula at the cursor.")
                             : String(localized: "Symbols go in at the cursor. Superscript, subscript and templates become a formula, with the word before as its base."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }

    private func structureButton(_ label: String, _ help: LocalizedStringKey, _ insertion: FormulaInsertion) -> some View {
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
