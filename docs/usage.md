# UniPDF verwenden

[Zurück zur Übersicht](../README.md)

## Benutzen

1. Mit **⌘O** direkt ein Vorlesungs-PDF öffnen. Alternativ **Ablage → Neu** und **Vorlesungs-PDF öffnen** wählen (⌘I).
2. Links eine Folie auswählen. Rechts Notizen schreiben, mit **Formel** oder **Skizze** weitere Inhalte ergänzen.
3. Mit **⌘S** oder **Speichern** die geöffnete Datei aktualisieren. Bei einer direkt geöffneten PDF wird die ursprüngliche Vorlesungsdatei am selben Pfad durch das Lern-PDF mit Mitschriften ersetzt. Jeder weitere Speichervorgang aktualisiert dieselbe Datei. Die nativen macOS-Sicherungs- und Wiederherstellungsfunktionen verwalten Dokumentänderungen.
4. Dieselbe PDF später wieder in UniPDF öffnen und weiterbearbeiten. Sie enthält neben den sichtbaren Seiten die Originalfolien, Notizen, Formeln und Skizzen in ihren Metadaten. UniPDF stellt daraus den bearbeitbaren Zustand wieder her; wiederholtes Speichern fügt das Layout nicht mehrfach hinzu.
5. **Lern-PDF exportieren** (⇧⌘E) erstellt bei Bedarf eine zusätzliche Kopie an einem gewählten Ort. Lange Mitschriften werden auf Fortsetzungsseiten verteilt. Die Folie wird zur Orientierung wiederholt; die Skizze erscheint auf der ersten Seite zur Folie.

Bestehende `.unipdf`-Projekte bleiben unterstützt. **⌘S** aktualisiert auch diese am bisherigen Speicherort. Um ein solches Projekt auf die PDF-Arbeitsweise umzustellen, einmal als PDF exportieren und anschließend die exportierte PDF öffnen. Soll sie die frühere Vorlesungsdatei ersetzen, beim Export deren Pfad auswählen.

Die bearbeitbaren Daten sind in der PDF eingebettet; es ist keine zusätzliche Projektdatei erforderlich. Andere PDF-Programme können beim erneuten Speichern Metadaten entfernen. Für die weitere Bearbeitung mit Mitschriften die Datei in UniPDF sichern.

Mit **⌘↑ / ⌘↓** zwischen Folien wechseln. Die Breite von PDF und Mitschrift lässt sich an der Trennlinie anpassen. UniPDF merkt sich die Breite der Mitschrift und die Fenstergröße auch über Neustarts hinweg; die Bibliothek hat ihre eigene Fenstergröße. Die Zeichenfläche unterstützt Stift, Linie, Pfeil, Rechteck und Ellipse, vier Farben und drei Strichstärken. Elemente lassen sich schrittweise entfernen und wiederherstellen.

## Auf der Folie markieren

Die Leiste direkt über der Folie legt Anmerkungen auf die Folie selbst, im Unterschied zur **Skizze**, die in der Mitschrift steht.

- **Stift:** frei zeichnen, drei Strichstärken.
- **Textfeld:** auf die Folie klicken und tippen. Schriftart, Größe, Fett, Kursiv und Unterstrichen gelten für das ganze Textfeld. Ein leeres Textfeld verschwindet wieder. Doppelklick bearbeitet den Text später.
- **Formen:** Rechteck, Quadrat, Kreis, Oval und Linie aufziehen. Das Symbol wählt die zuletzt benutzte Form, der Pfeil daneben die anderen. **⇧** hält beim Rechteck und Oval die Proportionen und rastet Linien in 45°-Schritten ein.
- **Bild:** Das Bildsymbol wählt eine Datei, **⌘V** setzt ein Bild aus der Zwischenablage ein, zum Beispiel einen Bildschirmausschnitt. Sehr große Bilder werden auf 2400 Pixel an der längsten Seite verkleinert.
- **Farben:** vier feste Farben und eine beliebige Farbe aus dem Farbfeld. Ist die Leiste schmal, bleibt beim Text nur das Farbfeld.

Mit dem Pfeil-Werkzeug wählst du eine Anmerkung aus, ziehst sie an eine andere Stelle oder änderst ihre Größe an den Griffen. Die Einstellungen in der Leiste gelten dann für die Auswahl. Pfeiltasten verschieben um einen Punkt, mit **⇧** um zehn. **⌫** oder das Papierkorb-Symbol löscht, **⌘X**, **⌘C** und **⌘V** funktionieren, **⌘Z** widerruft. **Esc** beendet ein Werkzeug oder hebt die Auswahl auf. Umrissene Formen reagieren nur auf ihre Linie, damit Text darin auswählbar bleibt; neben Anmerkungen lässt sich weiter PDF-Text markieren.

Anmerkungen bleiben beim Zoomen und auf gedrehten Folien an ihrer Stelle und stehen dort aufrecht. Sie landen im Lern-PDF auf der Folie und bleiben nach dem erneuten Öffnen bearbeitbar; die Originalfolie selbst wird nicht verändert. Text bleibt im PDF durchsuchbar. Fehlt eine Schriftart auf einem anderen Mac, erscheint dort die Systemschrift. Die Kopie **Originalfolie** für den KI-Prompt zeigt die Folie ohne Anmerkungen, das Lernskript mit ihnen.

Dateien mit dem Projektformat 2 lassen sich nur mit dieser oder einer neueren UniPDF-Version öffnen. Ältere Dateien öffnen weiter und werden beim Speichern umgestellt.

## Start ohne Datei

Waren beim Beenden Dateien geöffnet, stellt macOS diese Tabs wieder her. Sonst öffnet UniPDF die zuletzt geöffnete Datei, auch wenn sie inzwischen umbenannt oder verschoben wurde. Gibt es sie nicht mehr oder liegt sie im Papierkorb, öffnet sich die Bibliothek. Dasselbe gilt für einen Klick auf das Dock-Symbol, wenn kein Fenster offen ist. Ein neues leeres Dokument gibt es weiter über **Ablage → Neu** oder **+** in der Tab-Leiste.

## Mehrere Dateien

Geöffnete Dateien liegen als Tabs in einem Fenster, unabhängig von der Tab-Einstellung des Systems. Ein Klick auf einen Tab wechselt die Datei, **+** öffnet einen neuen Tab mit der Startseite. Rechtsklick auf einen Tab bietet **Tab in ein neues Fenster bewegen**; ebenso lässt sich ein Tab aus der Leiste ziehen. **Fenster → Alle Fenster zusammenführen** holt getrennte Fenster wieder zusammen. Die Bibliothek bleibt ein eigenes Fenster.

## Bibliothek

**Ablage → Bibliothek** (⇧⌘L) öffnet den Dateimanager. Mit **Ordner auswählen …** gibst du UniPDF Zugriff auf einen Ordner, zum Beispiel dein Studium. Der Ordner bleibt über Neustarts hinweg verbunden. Ordner und Dateien erscheinen als Kacheln oder als Liste, Dateien mit einem Vorschaubild ihrer ersten Seite. Der Umschalter steht rechts neben dem Pfad; die Wahl bleibt erhalten. Im Viewer öffnet der Ordner-Knopf neben dem Seitenleisten-Knopf die Bibliothek.

- **Navigieren:** Doppelklick geht in einen Ordner. Der Pfad oben und der Zurück-Pfeil (⌘↑) führen wieder hinauf. Pfeiltasten wählen eine Kachel aus, Return öffnet sie.
- **Öffnen:** Doppelklick öffnet PDFs und `.unipdf`-Projekte in UniPDF, andere Dateien im passenden Programm.
- **Ordnen:** Eine Kachel auf einen Ordner ziehen verschiebt sie, ebenso das Ziehen auf einen Eintrag im Pfad. Das Kontextmenü bietet **Umbenennen** und **Im Finder zeigen**; **Neuer Ordner** (⇧⌘N) legt den Ordner im aktuellen Ordner an.
- **Entfernen:** **In den Papierkorb legen** (⌘⌫) fragt vorher nach; alles bleibt aus dem Papierkorb wiederherstellbar.

Vorhandene Dateien werden nie überschrieben, und Änderungen bleiben auf den freigegebenen Ordner beschränkt. Geöffnete Dokumente folgen ihrer Datei beim Umbenennen und Verschieben. Symbolische Links erscheinen als Dateien und werden nicht betreten. Änderungen aus dem Finder erscheinen, sobald die App wieder aktiv wird, oder mit ⌘R. **Ordner trennen** vergisst nur den Ordner; die Dateien bleiben unverändert.

In der Seitenleiste des Viewers steht über den Folien der einklappbare Abschnitt **Dateien**. Er zeigt denselben Ordner als klassischen Baum: Ein Klick klappt einen Ordner auf oder öffnet eine Datei in einem neuen Tab, die geöffnete Datei ist markiert und ihr Ordner beim Start aufgeklappt.

Das Vorschaubild zeigt die tatsächliche erste Seite der Datei, bei einer gespeicherten Lern-PDF also Folie und Mitschrift zusammen.

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
