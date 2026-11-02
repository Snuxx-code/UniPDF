# UniPDF

Eine native Mac-App für Vorlesungsfolien und deine Mitschriften. SwiftUI, PDFKit und CoreText; keine externen Abhängigkeiten und keine Netzwerkverbindung nötig.

## Starten

Die fertige App liegt nach dem Bauen in `build/UniPDF.app`. Zum Bauen sind die Apple Command Line Tools mit Swift 6.2 oder neuer erforderlich; zum Verwenden macOS 14 oder neuer.

```sh
zsh scripts/build-app.sh
open build/UniPDF.app
```

Alternativ `Package.swift` in Xcode öffnen und das Scheme **UniPDF** starten.

## GitHub-Repository verbinden

Das Projekt ist für `https://github.com/Snuxx-code/UniPDF.git` vorbereitet. Im normalen macOS-Terminal im Projektordner ausführen:

```sh
zsh scripts/connect-github.sh
```

Das Skript initialisiert Git, setzt `origin` auf `git@github.com:Snuxx-code/UniPDF.git`, liest vorhandene Remote-Historie ein, erstellt einen Commit und pusht den Branch. Eine vorhandene HTTPS-Verbindung zu genau diesem Repository wird auf SSH umgestellt. Vorhandene Remote-Historie und zusätzliche Remote-Dateien bleiben erhalten. Build-Ausgaben und Beispiel-PDFs werden nicht hochgeladen. Für den Push ist ein bei GitHub hinterlegter SSH-Schlüssel mit Schreibzugriff auf das Repository erforderlich. Bei einem bereits anders verbundenen Repository oder auseinanderlaufender Historie stoppt das Skript.

## Benutzen

1. Mit **⌘O** direkt ein Vorlesungs-PDF öffnen. Alternativ **Ablage → Neu** und **Vorlesungs-PDF öffnen** wählen (⌘I).
2. Links eine Folie auswählen. Rechts Notizen schreiben, mit **Formel** oder **Skizze** weitere Inhalte ergänzen.
3. Mit **⌘S** oder **Speichern** die geöffnete Datei aktualisieren. Bei einer direkt geöffneten PDF wird die ursprüngliche Vorlesungsdatei am selben Pfad durch das Lern-PDF mit Mitschriften ersetzt. Jeder weitere Speichervorgang aktualisiert dieselbe Datei. Die nativen macOS-Sicherungs- und Wiederherstellungsfunktionen verwalten Dokumentänderungen.
4. Dieselbe PDF später wieder in UniPDF öffnen und weiterbearbeiten. Sie enthält neben den sichtbaren Seiten die Originalfolien, Notizen, Formeln und Skizzen in ihren Metadaten. UniPDF stellt daraus den bearbeitbaren Zustand wieder her; wiederholtes Speichern fügt das Layout nicht mehrfach hinzu.
5. **Lern-PDF exportieren** (⇧⌘E) erstellt bei Bedarf eine zusätzliche Kopie an einem gewählten Ort. Lange Mitschriften werden auf Fortsetzungsseiten verteilt. Die Folie wird zur Orientierung wiederholt; die Skizze erscheint auf der ersten Seite zur Folie.

Bestehende `.unipdf`-Projekte bleiben unterstützt. **⌘S** aktualisiert auch diese am bisherigen Speicherort. Um ein solches Projekt auf die PDF-Arbeitsweise umzustellen, einmal als PDF exportieren und anschließend die exportierte PDF öffnen. Soll sie die frühere Vorlesungsdatei ersetzen, beim Export deren Pfad auswählen.

Die bearbeitbaren Daten sind in der PDF eingebettet; es ist keine zusätzliche Projektdatei erforderlich. Andere PDF-Programme können beim erneuten Speichern Metadaten entfernen. Für die weitere Bearbeitung mit Mitschriften die Datei in UniPDF sichern.

Mit **⌘↑ / ⌘↓** zwischen Folien wechseln. Die Breite von PDF und Mitschrift lässt sich an der Trennlinie anpassen. Die Zeichenfläche unterstützt Stift, Linie, Pfeil, Rechteck und Ellipse, vier Farben und drei Strichstärken. Elemente lassen sich schrittweise entfernen und wiederherstellen.

## Eine Frage an die KI vorbereiten

**KI-Prompt** neben **Formel** und **Skizze** anklicken (⌥⌘K). Der Prompt wird sofort in die Zwischenablage kopiert und als Vorschau angezeigt. Im Fragefeld eine eigene Frage ergänzen und mit **Prompt kopieren** erneut übernehmen. Anschließend mit **⌘V** in den gewünschten KI-Chat einfügen.

Der Prompt nennt den tatsächlichen Pfad der geöffneten Datei und die aktuelle Originalfoliennummer. Zusätzlich werden zwei lokale PDF-Kopien im temporären Ordner erzeugt: das aktuelle Lernskript einschließlich ungespeicherter Notizen und die ausgewählte Originalfolie einzeln. So stimmen Dateipfade und Folienzuordnung auch bei Fortsetzungsseiten. Die Originaldatei wird bei dieser Aktion nicht gespeichert oder verändert. Die Kopien enthalten sichtbare PDF-Seiten ohne das eingebettete bearbeitbare Projekt. Jeder Aufruf erzeugt eigene Kopien, sodass ein bereits kopierter Prompt auf denselben Stand verweist.

Die Funktion versendet nichts automatisch. Eine KI mit lokalem Dateizugriff kann die genannten Pfade verwenden. Bei einer KI ohne lokalen Dateizugriff die PDF-Kopien zusätzlich anhängen. Temporäre Dateien können vom Betriebssystem später entfernt werden; der Prompt ist für die zeitnahe Verwendung gedacht.

## Formeln

Das Formelfeld zeigt eine Live-Vorschau einer kleinen, offline verfügbaren Notation:

- Potenzen und Indizes: `x^{2}`, `a_{n}`
- Brüche und Wurzeln: `\frac{a}{b}`, `\sqrt{x}`
- Griechische Zeichen: `\alpha`, `\beta`, `\theta`, `\pi`, `\sigma`, `\Delta`
- Operatoren: `\sum`, `\int`, `\infty`, `\cdot`, `\times`, `\pm`, `\leq`, `\geq`, `\neq`, `\approx`
- Unicode-Zeichen können direkt eingefügt werden. Vorlagen und eine Zeichenpalette stehen bereit.

Dies ist kein vollständiges LaTeX. Brüche werden kompakt mit einem Bruchstrich „⁄“ angezeigt. Unbekannte Befehle bleiben als Text erhalten. Der Export verwendet dieselbe Darstellung wie die Vorschau.

## Prüfen

```sh
zsh scripts/test.sh
```

Tests prüfen zusätzlich das Ersetzen einer PDF am Originalpfad, erneutes Öffnen und Weiterbearbeiten, das Vermeiden verschachtelter Lernseiten und die Kompatibilität bestehender Projekte. Exporttests prüfen Formelnotation, gedrehte Folien und den verlustfreien Überlauf langer Mitschriften.

Die App wird lokal ad hoc signiert. Eine notarisiert signierte Veröffentlichung und ein App-Store-Paket sind nicht Teil dieses Projekts.

## Validierungsstand

Release-Build und lokale Codesignatur erfolgreich geprüft. Automatisierte Tests decken auch lange untrennbare Textfolgen ab. Unter `build/Preview` liegen ein ausdrücklich als Beispiel markiertes Projekt und ein daraus exportiertes Lernskript. Die Oberfläche wurde in hell und dunkel als Offscreen-Ansicht gerendert; PDFKit-Layer werden dabei teilweise nicht aufgenommen. Der vollständige Finder-Start konnte in der eingeschränkten Entwicklungsumgebung nicht verifiziert werden: LaunchServices verweigert hier die App-Registrierung. Die App bitte regulär im Finder starten.
