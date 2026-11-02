import SwiftUI
import UniPDFCore

struct AIPromptPopover: View {
    let context: AIQuestionPrompt
    let copy: (String) -> Bool
    @State private var question = ""
    @State private var copied = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Frage zu Folie \(context.slideNumber)").font(.headline)
                Spacer()
                if copied { Label("Prompt kopiert", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary) }
            }
            Text("Mit ⌘V in deinen KI-Chat einfügen. Du kannst deine Frage auch hier ergänzen.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Was möchtest du zu dieser Folie wissen?", text: $question, axis: .vertical)
                .lineLimit(2...4).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Frage an die KI")
                .onChange(of: question) { copied = false }
            ScrollView {
                Text(context.text(question: question))
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled).padding(12)
            }
            .frame(height: 230)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Die PDF-Kopien liegen lokal im temporären Ordner.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Erneut kopieren" : "Prompt kopieren") {
                    copied = copy(context.text(question: question))
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 480)
    }
}
