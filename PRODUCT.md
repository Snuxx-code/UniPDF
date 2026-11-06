# UniPDF

<!-- impeccable:product-schema 1 -->

## Platform
Native macOS.

## Stack
SwiftUI, AppKit, PDFKit and CoreText. The user confirmed a native Mac app.

## Users
A university student taking notes alongside lecture slides and studying from the result.

## Product Purpose
Load a lecture PDF, write notes beside each slide, and export slides and notes together as one study PDF.

## Capabilities and Constraints
Confirmed: typed notes, freehand drawings, geometric shapes, mathematical formulas, PDF export.
Confirmed: plain arrow keys navigate the PDF (right/down forward, left/up backward). Text inputs, file lists and selected annotations retain their normal arrow-key behavior.
Confirmed: a button creates a prompt for asking an AI about the lecture, including the correct file path. The implementation copies the prompt locally, includes the current slide and an optional question, and creates fresh temporary PDF context copies without overwriting the lecture or automatically sending data.
Confirmed saving behavior: saving a directly opened lecture PDF replaces that same PDF at its original path with the slides and notes. Repeated saves update the same file. Editable original slides, notes, formulas and drawings must survive reopening, without repeatedly nesting the study layout.
Confirmed: a file manager inside the app. The user grants access to one folder and manages the folder structure beneath it in the app. Confirmed: folders and files appear as tiles in the style of Goodnotes, and files show a preview. Tiles and a list can be switched. The viewer has a button beside the sidebar button that opens the file manager, and a collapsible Dateien section above the slide list for classic list navigation.
Confirmed: annotations directly on the slide in the viewer: a pen with changeable colors, text boxes with adjustable font, size and style, the shapes rectangle, square, circle, oval and line, and images. They can be selected, moved and deleted, survive saving and reopening, and appear in the exported study PDF at the same place, on rotated slides and at any zoom. The implementation keeps them in the project (format version 3, older files still open), never in the original slide; a text box has one style throughout; shapes are outlined.
Confirmed: a text highlighter for selectable PDF text, rather than freehand strokes. Activating Textmarker highlights an existing text selection, or lets the user drag over words and lines. Highlights are translucent, have a separate color palette, and remain editable after saving and reopening. Scans without a selectable text layer do not support text highlighting.
Confirmed: an eraser for the pen and the text marker on the slide. Confirmed: it switches between a precise mode, which erases only what it touches and removes whole characters from highlights, and a stroke mode, which removes every touched stroke or highlight entirely. Shapes, text boxes and images are left to the delete action. Confirmed: highlights sit behind the text so that its contrast stays.
Confirmed: several open files share one window as tabs, and a tab's context menu can move it to a new window.
Confirmed: starting without a file opens the last opened file, or the file manager when there is none.
Implementation choices: the file manager is a separate Bibliothek window; it never overwrites files, stays inside the granted folder and removes through the Trash. Offline document-based app; editable project data embedded in PDF XMP metadata. Legacy .unipdf projects remain supported. macOS 14 or later. Formula entry supports a documented subset of mathematical notation, not a complete LaTeX engine.

## Operating Context
German interface. Users work on one lecture at a time and can reopen saved projects.

## Evidence on Hand
No user lecture PDF or brand assets supplied. Any demonstration content must be explicitly labeled.
