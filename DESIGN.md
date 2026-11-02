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

Green identifies primary actions and selected additions. Semantic AppKit surfaces and secondary text adapt to light and dark appearances. Drawing and formula surfaces are always white with dark ink so their appearance matches the exported PDF. The four ink colors have fixed meanings only as user choices.

## Typography

The system serif introduces the welcome screen and the writing area. The system sans-serif handles all navigation and working controls. Note text is adjustable from 13 to 21 points; its default is the body size. Formula source uses system monospaced text; the preview uses the installed math font with a system fallback.

## Layout

Minimum document window: 1000 × 680 points. Default: 1320 × 850. A collapsible 178-point slide rail precedes a native resizable split between the PDF and the writing pane. Each pane has a 47-point header and a 43-point status/navigation footer. PDF and editor minimum widths are 360 and 350 points. The note area scrolls vertically; the 800 × 500 logical drawing surface scales proportionally.

## Elevation & Depth

Native sidebar material, native buttons and sheets. Flat document surfaces use separators, without decorative shadows or motion.

## Shapes

Soft corners distinguish drawing surfaces and slide thumbnails. Shapes drawn by users are geometrically precise and outlined.

## Components

Use native toolbar buttons, lists, text fields, menus, disclosure actions, open/save panels, and error alerts. Formula and sketch sections are optional additions to each slide. Slide labels expose whether a page contains notes. Every icon-only action has an accessibility label and a tooltip.

The toolbar's Speichern action uses the native document save command. Directly opened PDFs save back to their original path. Lern-PDF exportieren remains an explicit additional-copy action. Both PDFs and legacy projects are selectable in the native Open dialog.

KI-Prompt sits beside Formel and Skizze in the editor action row. It copies a ready prompt and opens a native nonmodal popover with an optional question, selectable prompt preview and an explicit copy action. Copy status clears when the question changes. The popover uses existing semantic surfaces and spacing.

## Do's and Don'ts

Preserve native keyboard shortcuts, focus, text selection, document saving and undo behavior. Keep formula preview and PDF rendering consistent. Do not let decorative layout reduce the available reading or writing space. Label demonstration content explicitly.
