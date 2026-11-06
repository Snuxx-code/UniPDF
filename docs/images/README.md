# Bilder für die UniPDF-README

[Zurück zur Übersicht](../../README.md)

Alle Bilder gehören zum Projekt. Sie verwenden ausschließlich das eigens erstellte und sichtbar markierte Demomaterial aus `Sources/UniPDF/PreviewHarness.swift`, keine persönlichen Mitschriften oder fremden Vorlesungsunterlagen.

| Datei | Herkunft |
| --- | --- |
| `unipdf-logo.png` | Vorhandenes App-Icon, mit `scripts/make-icon.swift` erzeugt; PNG in 512 × 512 Pixeln. |
| `workspace-light.png` | Gerenderte SwiftUI-Arbeitsansicht im hellen Erscheinungsbild. |
| `library.png` | Gerenderte SwiftUI-Bibliothek mit Beispielordnern und PDF-Vorschaubildern. |
| `study-pdf.png` | Erste Seite der tatsächlichen, mit `PDFExporter.export` erzeugten Beispiel-Lern-PDF. |

## Aufnahmeverfahren

Die App-Ansichten basieren auf dem Quellstand `acf37a3` mit der angepassten Demomarkierung aus `PreviewHarness.swift`. Die Beispiel-Ellipse wird aus den tatsächlichen Textabmessungen mit zusätzlichem Abstand zu den Buchstaben berechnet. Die bestehenden SwiftUI-Views werden mit `NSHostingView` und `cacheDisplay` aufgenommen. Die Arbeitsansichten verwenden 1320 × 1000 Punkte, die Bibliothek 720 × 560 Punkte; beide werden mit doppelter Pixeldichte gerendert.

Bildschirmaufnahmen und GPU-gestütztes PDFKit-Rendering sind in der Entwicklungsumgebung eingeschränkt. Für diese Dokumentationsbilder wurde der PDF-Bereich deshalb ausschließlich in einer temporären Aufnahmeversion durch eine CPU-gerenderte Ansicht derselben Originalfolie mit denselben Anmerkungen ersetzt (`AnnotationRenderer.thumbnail`). Die PDF-Vorschaubilder in der Bibliothek wurden aus den tatsächlichen Beispiel-PDFs vorab in den vorhandenen Thumbnail-Cache geladen, da der Quick-Look-Dienst hier keine Inhaltsvorschau liefert. Bedienelemente, Mitschrift, Formel, Skizze und Bibliothek stammen aus den vorhandenen App-Views. Die Abbildungen sind **gerenderte App-Vorschauen**, keine Aufnahmen eines laufenden Desktop-Fensters. Die Aufnahmeversion wird nicht mit der App ausgeliefert.

Die Lern-PDF wird aus demselben Beispielprojekt exportiert und als PDF-Seite gerastert. Die Bilddateien enthalten zusätzlich Herkunftsangaben in ihren PNG-Metadaten.

Für neue Aufnahmen auf einem Mac die App bauen und die bestehende Vorschau aus dem Repository-Verzeichnis starten:

```sh
zsh scripts/build-app.sh
.build/release/UniPDF --preview
```

Die Vorschau erzeugt ihr Demoprojekt, die Lern-PDF und die App-Ansichten unter `build/Preview`. Sie ist für Entwicklungszwecke gedacht. Vor dem Ersetzen der README-Bilder prüfen, dass PDF-Inhalt und Anmerkungen in den Aufnahmen vollständig sichtbar sind; nicht alle Aufnahmeverfahren erfassen die PDFKit-Layer.
