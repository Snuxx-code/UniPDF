---
name: UniPDF
description: A quiet native workspace for lecture slides and personal understanding.
colors:
  primary: "#296657"
  primary-dark-mode: "#87C7AB"
  ink-graphite: "#293036"
  ink-blue: "#2959BD"
  ink-red: "#BF333B"
  ink-green: "#1F7357"
typography:
  display:
    fontFamily: "New York, system serif"
    fontSize: "43pt"
    fontWeight: 600
    letterSpacing: "-1pt"
  body:
    fontFamily: "SF Pro, system sans-serif"
    fontSize: "15pt"
    fontWeight: 400
rounded:
  canvas: "8pt"
  thumbnail: "4pt"
spacing:
  small: "12pt"
  medium: "18pt"
  large: "24pt"
---

## Overview

Native macOS document workspace. The interface follows the physical relationship of a lecture slide beside a student's thoughts. The persistent signature is that each slide and its notes form a pair, in the workspace and the exported document. Content leads; controls use native macOS affordances and SF Symbols.

## Colors

Green identifies primary actions and selected additions. Semantic AppKit surfaces and secondary text adapt to light and dark appearances. Drawing and formula surfaces are always white with dark ink so their appearance matches the exported PDF. The four ink colors have fixed meanings only as user choices. Slide annotations offer the same four plus any color from the native color well. Selection marks on a slide always use the light-mode green with white handles, because slides stay white in dark appearance.

## Typography

The system serif introduces the welcome screen and the writing area. The system sans-serif handles all navigation and working controls. Note text is adjustable from 13 to 21 points; its default is the body size. Formula source uses system monospaced text; the preview uses the installed math font with a system fallback.

## Layout

Minimum document window: 1000 × 680 points. Default: 1320 × 850. The sidebar is the native one of a NavigationSplitView, 180 to 340 points wide and 220 by default, as in the Finder: on macOS 26 it floats as glass. It lists the collapsible Dateien section above the Folien section and precedes a native resizable split between the PDF and the writing pane. Each pane has a 47-point header and a 43-point status/navigation footer. The writing pane has an action row beneath its header; the PDF pane shows its settings row there only while the active tool or the selection has settings. PDF and editor minimum widths are 360 and 350 points. The window frame and the dragged editor width persist; the editor keeps its width when the window or sidebar changes, and the PDF takes up the difference. The note area scrolls vertically; the 800 × 500 logical drawing surface scales proportionally.

## Elevation & Depth

Native sidebar material, native buttons and sheets. Flat document surfaces use separators, without decorative shadows or motion.

## Shapes

Soft corners distinguish drawing surfaces and slide thumbnails. Shapes drawn by users are geometrically precise and outlined, on slides as well as in sketches.

## Components

Use native toolbar buttons, lists, text fields, menus, disclosure actions, open/save panels, and error alerts. Formula and sketch sections are optional additions to each slide. Slide labels expose whether a page contains notes. Every icon-only action has an accessibility label and a tooltip.

Textmarker uses the native highlighter symbol beside the pen in the slide annotation bar. Its settings offer a separate yellow, green, pink and blue palette plus a custom color. Dragging selects PDF text with an I-beam cursor and previews translucent rectangles per text line; an existing PDF text selection is highlighted immediately on activation. Selection, color changes and deletion use the established annotation controls.

Highlights sit behind the slide's text: in the viewer they live in their own layer between the PDF and the other annotations, multiplied with the slide, and the exported PDF multiplies them as well, so dark text keeps its full contrast.

The eraser follows the marker in the bar, with the native eraser symbol. It works on pen strokes and text highlights only. A pop-up beside the size switches between Präzise and Strich. Präzise splits strokes into the pieces outside its circle and removes whole characters from highlights; Strich removes every stroke and highlight it touches entirely. shapes, text boxes and images are deleted as a whole instead. A light-haloed circle at the pointer shows its size, chosen as Klein, Mittel or Groß relative to the slide. One drag is one undo step.

The PDF pane's header holds the annotation tools as capsules in the style of Preview, glass on macOS 26 and bar material before: selection arrow, pen, marker, eraser and text box; the shape split button, which draws the last shape and has a chevron menu for the others behind a hairline; image; and, on the right, zoom out, fit and zoom in. The active tool is a filled accent circle with a white symbol. In a narrow pane the zoom buttons fold into one menu. The window toolbar keeps the library button, the lecture's name, Speichern and Exportieren. The settings of the active tool or of the selected annotation sit in a row beneath, left-aligned in small controls; a delete action appears first among them. The row appears only when there are settings: never for the selection arrow without a selection. It changes only after the mouse is released, so the slide never moves under the pointer during a gesture. Within the row the room of the widest settings is kept, and the color swatches for text give way first. Selected annotations show a dashed hairline frame and round handles, a line only its two end handles. Text is edited in place at its exported line breaks. Pen stays active after drawing; a shape, text box or image returns to the selection arrow with the new item selected.

The toolbar's title pill is exactly as wide as the lecture's name, up to 360 points, and the window's own title beside the library button is hidden, since tabs and the pill already name the file. Inside the pill beside the name, a quiet save status: a small grey dot while changes are unsaved, a small check in the accent green once everything is saved, each with a tooltip.

The toolbar's Speichern action uses the native document save command. Directly opened PDFs save back to their original path. Lern-PDF exportieren remains an explicit additional-copy action. Both PDFs and legacy projects are selectable in the native Open dialog.

KI-Prompt sits beside Formel and Skizze in the editor action row. It copies a ready prompt and opens a native nonmodal popover with an optional question, selectable prompt preview and an explicit copy action. Copy status clears when the question changes. The popover uses existing semantic surfaces and spacing.

Bibliothek is a separate window, default 720 × 560 points and at least 480 points wide so all toolbar actions stay visible. It shows one folder at a time as an adaptive grid of tiles at least 168 points wide, folders first, with a 47-point path bar above. Folders use a filled accent symbol and an item count; files use a preview of their first page with thumbnail corners and a hairline, plus their date. Previews stay white in dark appearance because they show the page as printed. Files UniPDF cannot open use secondary text. A selected tile gets a soft accent background and outline. Dragging onto a folder tile or a path entry moves; a drop target gets a soft accent background. A segmented control beside the path switches between tiles and a list of rows with a small preview and the same caption; the choice persists.

Document windows use native macOS window tabs in one tab group, whatever the system's tab preference says, with the native tab menu for moving a tab to a new window. Bibliothek never joins a tab group.

The viewer's toolbar places a folder button directly beside the native sidebar button; it opens Bibliothek. The sidebar's Dateien section is a native outline with disclosure triangles: a click on a folder expands it, a click on a file opens it, and the open file is set in semibold with an accent icon. Slide previews keep each page's displayed shape, so portrait and turned pages stay upright and tall, capped at 150 points; a hairline outlines them, with even padding; beneath, the label sits on the left and the notes mark on the right. The open slide is marked by a narrow frame in the accent green, three points around its preview, and a semibold green label, not by a filled list highlight. A quiet caption at the very bottom of the sidebar counts the slides with notes.

## Do's and Don'ts

Preserve native keyboard shortcuts, focus, text selection, document saving and undo behavior. Keep formula preview and PDF rendering consistent. Do not let decorative layout reduce the available reading or writing space. Label demonstration content explicitly.
