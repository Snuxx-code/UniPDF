import AppKit
import SwiftUI
import Testing
@testable import UniPDF

/// Text typed into the notes must not be lost to an older copy of it, as a document reloaded from its file brings.
@MainActor struct NotesTypingTests {
    @Test func aStaleCopyOfTheTypingIsRecognised() {
        var stored = "Hall"
        let coordinator = NotesEditor.Coordinator(text: Binding(get: { stored }, set: { stored = $0 }))
        let view = NotesTextView(frame: .zero)
        view.string = "Hallo"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        #expect(stored == "Hallo")
        // The document comes back with the state from before the last letters: it is stale.
        #expect(coordinator.isOlderTyping("Hall"))
        // Something never typed, such as Claude's addition or another slide's notes, is a real change.
        #expect(!coordinator.isOlderTyping("Hallo\nVon Claude"))
    }

    @Test func undoIsARealChange() {
        var stored = "A"
        let coordinator = NotesEditor.Coordinator(text: Binding(get: { stored }, set: { stored = $0 }))
        let view = NotesTextView(frame: .zero)
        view.string = "AB"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        NotificationCenter.default.post(name: .NSUndoManagerDidUndoChange, object: nil)
        #expect(!coordinator.isOlderTyping("A"))
    }
}
