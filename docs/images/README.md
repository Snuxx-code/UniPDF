# Images for the UniPDF README

[Back to the overview](../../README.md)

All images belong to the project. They only use the purpose-made and visibly labeled demo material from `Sources/UniPDF/PreviewHarness.swift`, never personal notes or someone else's lecture material.

| File | Origin |
| --- | --- |
| `unipdf-logo.png` | The app icon, created with `scripts/make-icon.swift`; PNG at 512 × 512 pixels. |
| `workspace-light.png` | Rendered SwiftUI workspace in the light appearance. |
| `library.png` | Rendered SwiftUI library with sample folders and PDF thumbnails. |
| `study-pdf.png` | First page of the actual sample study PDF created with `PDFExporter.export`. |

## How the images were made

The app views are based on source revision `acf37a3` with the adjusted demo markup from `PreviewHarness.swift`. The sample ellipse is computed from the actual text dimensions, with extra room around the letters. The existing SwiftUI views are captured with `NSHostingView` and `cacheDisplay`. The workspace views use 1320 × 1000 points and the library 720 × 560 points; both are rendered at double pixel density.

Screen capture and GPU-backed PDFKit rendering are limited in the development environment. For these documentation images, the PDF area was therefore replaced, only in a temporary capture build, by a CPU-rendered view of the same original slide with the same annotations (`AnnotationRenderer.thumbnail`). The PDF thumbnails in the library were loaded from the actual sample PDFs into the existing thumbnail cache beforehand, because the Quick Look service does not provide content previews there. Controls, notes, formula, sketch and library come from the existing app views. The images are **rendered app previews**, not captures of a running desktop window. The capture build is not shipped with the app.

The study PDF is exported from the same sample project and rasterized as a PDF page. The image files also carry their origin in their PNG metadata.

To make new images on a Mac, build the app and run the existing preview from the repository folder:

```sh
zsh scripts/build-app.sh
.build/release/UniPDF --preview
```

The preview creates its demo project, the study PDF and the app views in `build/Preview`. It is meant for development. Before replacing the README images, check that the PDF content and annotations are fully visible in the captures; not every capture method records the PDFKit layers.
