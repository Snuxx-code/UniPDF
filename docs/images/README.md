# Images for the UniPDF README

[Back to the overview](../../README.md)

All images belong to the project. They only use the purpose-made and visibly labeled demo material from `Sources/UniPDF/PreviewHarness.swift`, never personal notes or someone else's lecture material.

| File | Origin |
| --- | --- |
| `unipdf-logo.png` | The app icon, created with `scripts/make-icon.swift`; PNG at 512 × 512 pixels. It uses the UniPDF symbol from the web app's brand kit in white on the brand gradient. |
| `workspace-light.png` | Window of the running app in the light appearance, in English. |
| `workspace-dark.png` | The same window in the dark appearance; GitHub shows it in dark mode. |
| `library.png` | Library window of the running app with the sample folders and their thumbnails. |
| `study-pdf.png` | First page of the actual sample study PDF created with `PDFExporter.export`. |

## How the images were made

`.build/release/UniPDF --preview` creates the demo lecture, its study PDF and a sample library in `build/Preview`. The images are captures of the running app's windows (`screencapture -l <window id> -o`), made with the built `build/UniPDF.app`:

1. Copy `Example-Study-PDF.pdf` into the sample library as `Semester 1/Linear Algebra.pdf`.
2. Back up the app's preferences (`defaults export de.unipdf.mac`), point its library at `build/Preview/Example-Library` and give the document window 1320 × 820 points.
3. Open the lecture with `open -a build/UniPDF.app … --args -ApplePersistenceIgnoreState YES -AppleLanguages "(en)" -AppleLocale en_US`, adding `-NSRequiresAquaSystemAppearance YES` for the light images. Capture the document window, then open the library with ⇧⌘L and capture it.
4. Quit the app and restore the preferences (`defaults import`).

The study PDF image is the first page of `Example-Study-PDF.pdf`, rasterized at twice its size. Only demo material appears in the images; check that no personal files show up, for example in the sidebar's Files section, before replacing them.
