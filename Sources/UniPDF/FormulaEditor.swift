import SwiftUI
import UniPDFCore

/// The formula field of earlier versions. New formulas go into the notes; this one can move there.
struct FormulaEditor: View {
    @Binding var formula: String
    let moveIntoNotes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            Button("In die Mitschrift übernehmen", systemImage: "arrow.up.doc", action: moveIntoNotes)
                .help("Die Formel als Formelblock ans Ende der Mitschrift setzen. Dort lässt sie sich mit der Formelleiste bearbeiten.")
        }
    }
}
