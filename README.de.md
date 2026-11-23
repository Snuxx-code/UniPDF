<p align="center">
  <img src="docs/images/unipdf-logo.png" width="112" height="112" alt="UniPDF App-Logo">
</p>

<h1 align="center">UniPDF</h1>

<p align="center">
  <strong>Deine Vorlesung. Deine Gedanken.</strong><br>
  Vorlesungsfolien lesen, daneben mitschreiben und alles als Lern-PDF speichern.
</p>

<p align="center">
  Native Mac-App &nbsp;·&nbsp; macOS 14+ &nbsp;·&nbsp; Lokal und offline &nbsp;·&nbsp; Deutsch und Englisch
</p>

<p align="center"><a href="README.md">English</a> · <strong>Deutsch</strong></p>

<p align="center">
  <a href="#das-kann-unipdf">Funktionen</a> &nbsp;·&nbsp;
  <a href="#schnellstart">Schnellstart</a> &nbsp;·&nbsp;
  <a href="#tastenkürzel">Tastenkürzel</a> &nbsp;·&nbsp;
  <a href="docs/usage.de.md">Bedienung</a> &nbsp;·&nbsp;
  <a href="#entwicklung">Entwicklung</a>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/workspace-dark.png">
  <img src="docs/images/workspace-light.png" alt="UniPDF mit Folienübersicht links, einer markierten Vorlesungsfolie in der Mitte und Mitschrift, Formel und Skizze rechts" width="1320">
</picture>

## Das kann UniPDF

Links steht die Folie, rechts schreibst du mit. Beim Speichern wird daraus eine PDF, die du später in UniPDF weiterbearbeiten kannst.

| Funktion | Für deinen Lernalltag |
| --- | --- |
| **Mitschriften pro Folie** | Getippte Notizen neben der passenden Folie, formatiert wie im Chat mit `**fett**`, `_kursiv_` und `- Stichpunkten`, mit Unterpunkten per Tab und einer Autokorrektur, die Deutsch und Englisch erkennt. Die Trennlinie zwischen Folie und Mitschrift lässt sich verschieben, die Mitschrift ganz einklappen. |
| **Direkt auf der Folie markieren** | PDF-Text mit dem Textmarker hervorheben oder mit Stift, Textfeldern, Formen und Bildern ergänzen. Der Radiergummi entfernt Teile von Strichen und Markierungen. Alles bleibt bearbeitbar. |
| **Formeln und Skizzen** | Formeln mitten im Text zwischen `$ … $`, eine Formelleiste mit Zeichen nach Themengebiet und eine eigene Zeichenfläche mit Stift, Linien, Pfeilen und Formen. |
| **Textstellen kommentieren** | Text markieren, Rechtsklick → **Kommentieren**: Die Stelle wird pastellfarben hinterlegt, in der Mitschrift erscheint ein Tag, der sich zur Kommentar-Karte aufklappen lässt. Auch Bereiche ohne Text lassen sich kommentieren. |
| **Im Dokument suchen** | Durchsucht Folientext, Mitschriften, Textfelder und Kommentare. Die Treffer stehen nach Folien geordnet in der Seitenleiste. |
| **Einzelseite oder fortlaufend** | Folie für Folie arbeiten oder durch alle Folien scrollen, während die Mitschrift mitläuft. |
| **Alles in einer PDF** | Folien, Anmerkungen, Kommentare und Mitschriften gemeinsam speichern oder als zusätzliche Lern-PDF exportieren. |
| **Bibliothek und Tabs** | Vorlesungen in Ordnern verwalten, als Kacheln oder Liste, und mehrere Dateien als Tabs parallel öffnen. |
| **KI-Prompt vorbereiten** | Eine Frage mit dem richtigen Dateipfad und der aktuellen Folie kopieren. Du entscheidest, in welchen KI-Chat sie kommt. |

UniPDF arbeitet komplett lokal mit **SwiftUI, AppKit, PDFKit und CoreText** und hat keine externen Paketabhängigkeiten. Auch der KI-Prompt wird nur in die Zwischenablage kopiert und nie automatisch versendet.

## Ein Blick in die App

| Deine Vorlesungen | Dein Lernskript |
| --- | --- |
| [![Bibliothek mit Ordnern und PDF-Vorschaubildern](docs/images/library.png)](docs/images/library.png) | [![Exportierte Lern-PDF mit annotierter Folie, Mitschrift, Formel und Skizze](docs/images/study-pdf.png)](docs/images/study-pdf.png) |
| Ordner und Dateien mit Vorschau direkt in UniPDF verwalten. | Folie und Mitschrift gemeinsam zum Lernen mitnehmen. |

Alle Abbildungen zeigen **Demomaterial**, keine echten Kursunterlagen ([Herkunft der Bilder](docs/images/README.md)).

## Schnellstart

**Voraussetzungen:** macOS 14 oder neuer. Zum Bauen außerdem die Apple Command Line Tools mit Swift 6.2 oder neuer; die fertige App braucht kein Swift.

```sh
git clone https://github.com/Snuxx-code/UniPDF.git
cd UniPDF
zsh scripts/build-app.sh
open build/UniPDF.app
```

Alternativ `Package.swift` in Xcode öffnen und das Scheme **UniPDF** starten; die App läuft dann nur auf Englisch, weil `build-app.sh` die Übersetzungen hinzufügt. Der Build erstellt `build/UniPDF.app` mit einer lokalen Ad-hoc-Signatur. Eine notarisierte Version oder ein App-Store-Paket gibt es derzeit nicht.

### Von der Vorlesung zum Lernskript

1. Mit **⌘O** eine Vorlesungs-PDF öffnen.
2. Eine Folie auswählen und rechts mitschreiben. Bei Bedarf Formeln, Skizzen, Kommentare oder Anmerkungen auf der Folie ergänzen.
3. Mit **⌘S** speichern.
4. Die PDF später wieder in UniPDF öffnen und weiterarbeiten. **Lern-PDF exportieren** (⇧⌘E) erstellt bei Bedarf eine zusätzliche Kopie an einem Ort deiner Wahl.

> [!IMPORTANT]
> **⌘S ersetzt die geöffnete Vorlesungs-PDF am selben Pfad** durch die Version mit deinen Mitschriften. Jeder weitere Speichervorgang aktualisiert diese Datei. Die Originalfolien und alle bearbeitbaren Inhalte stecken in den Metadaten der PDF, deshalb verschachtelt wiederholtes Speichern die Lernseiten nicht. Andere PDF-Programme können diese Metadaten beim Speichern entfernen. Zum Weiterbearbeiten die Datei also in UniPDF sichern.

## Tastenkürzel

| Aktion | Tastenkürzel |
| --- | --- |
| PDF oder Projekt öffnen | **⌘O** |
| Speichern | **⌘S** |
| Lern-PDF exportieren | **⇧⌘E** |
| Vorherige / nächste Folie | **← ↑ / → ↓** oder **⌘↑ / ⌘↓** |
| Im Dokument suchen | **⌘F** |
| Nächster / vorheriger Treffer | **⌘G / ⇧⌘G** |
| Textstelle kommentieren | **⌥⌘M** |
| Fett / kursiv in der Mitschrift | **⌘B / ⌘I** |
| Fortlaufend scrollen ein/aus | **⌥⌘J** |
| Mitschrift ein-/ausklappen | **⌥⌘0** |
| KI-Prompt vorbereiten | **⌥⌘K** |
| Bibliothek öffnen | **⇧⌘L** |
| Anmerkung löschen | **⌫** |
| Werkzeug beenden / Auswahl aufheben | **Esc** |
| Rückgängig | **⌘Z** |

Die Pfeiltasten wechseln nur dann die Folie, wenn du gerade nicht schreibst. In Mitschrift, Formeln und Textfeldern bewegen sie den Cursor, bei einer ausgewählten Anmerkung verschieben sie diese, in der Bibliothek wählen sie Dateien aus.

## Mehr zur Bedienung

Die [ausführliche Anleitung](docs/usage.de.md) erklärt alles im Detail:

- [Speichern und Wiederöffnen](docs/usage.de.md#benutzen), Einzelseite und fortlaufendes Scrollen
- [Auf der Folie markieren](docs/usage.de.md#auf-der-folie-markieren): Stift, Textmarker, Radiergummi, Textfelder, Formen, Bilder
- [Textstellen kommentieren](docs/usage.de.md#textstellen-kommentieren) und [im Dokument suchen](docs/usage.de.md#im-dokument-suchen)
- [Formatierung der Mitschrift](docs/usage.de.md#formatierung-der-mitschrift) und [Formeln](docs/usage.de.md#formeln) mit der unterstützten Notation
- [Bibliothek](docs/usage.de.md#bibliothek), [mehrere Dateien](docs/usage.de.md#mehrere-dateien) und [KI-Prompts](docs/usage.de.md#eine-frage-an-die-ki-vorbereiten)

Ältere `.unipdf`-Projekte werden weiterhin unterstützt. UniPDF folgt der Sprache deines Macs, Deutsch oder Englisch ([mehr dazu](docs/usage.de.md#sprache)).

## Entwicklung

```sh
# App bauen
zsh scripts/build-app.sh

# Tests ausführen
zsh scripts/test.sh

# Prüfen, ob jeder Text der Oberfläche übersetzt ist
zsh scripts/check-localization.sh
```

Die Texte im Code sind englisch. Die deutsche Übersetzung steht in [`Resources/de.lproj/Localizable.strings`](Resources/de.lproj/Localizable.strings); `check-localization.sh` meldet Texte ohne Übersetzung.

Die Tests prüfen unter anderem das Speichern am Originalpfad, das Wiederöffnen bearbeitbarer PDFs, lange Mitschriften, die Suche und die Position von Anmerkungen auf gedrehten und beschnittenen Folien.

| Pfad | Inhalt |
| --- | --- |
| [`Sources/UniPDF`](Sources/UniPDF) | Native Oberfläche, Dokumente und Bibliothek |
| [`Sources/UniPDFCore`](Sources/UniPDFCore) | Projektmodell, PDF-Export und Rendering |
| [`Tests`](Tests) | Tests für Dokumente, Export, Anmerkungen und Dateiverwaltung |
| [`Resources`](Resources) | Info.plist und Übersetzungen |
| [`scripts`](scripts) | Build, App-Icon, Testlauf und Übersetzungsprüfung |
| [`docs`](docs) | Anleitung und Bilder für dieses README |

## Lizenz

UniPDF ist Open Source unter der [MIT-Lizenz](LICENSE).
