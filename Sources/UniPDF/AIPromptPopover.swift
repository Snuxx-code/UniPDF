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
                Text("Question about slide \(context.slideNumber)").font(.headline)
                Spacer()
                if copied { Label("Prompt copied", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary) }
            }
            Text("Paste it into your AI chat with ⌘V. You can also add your question here.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("What would you like to know about this slide?", text: $question, axis: .vertical)
                .lineLimit(2...4).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Question for the AI")
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
                Text("The PDF copies are stored locally in the temporary folder.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(copied ? String(localized: "Copy Again") : String(localized: "Copy Prompt")) {
                    copied = copy(context.text(question: question))
                }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20).frame(width: 480)
    }
}
