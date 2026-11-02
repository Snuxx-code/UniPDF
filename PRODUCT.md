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
Confirmed: a button creates a prompt for asking an AI about the lecture, including the correct file path. The implementation copies the prompt locally, includes the current slide and an optional question, and creates fresh temporary PDF context copies without overwriting the lecture or automatically sending data.
Confirmed saving behavior: saving a directly opened lecture PDF replaces that same PDF at its original path with the slides and notes. Repeated saves update the same file. Editable original slides, notes, formulas and drawings must survive reopening, without repeatedly nesting the study layout.
Implementation choices: offline document-based app; editable project data embedded in PDF XMP metadata. Legacy .unipdf projects remain supported. macOS 14 or later. Formula entry supports a documented subset of mathematical notation, not a complete LaTeX engine.

## Operating Context
German interface. Users work on one lecture at a time and can reopen saved projects.

## Evidence on Hand
No user lecture PDF or brand assets supplied. Any demonstration content must be explicitly labeled.
