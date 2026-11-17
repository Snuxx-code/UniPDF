# Using UniPDF

[Back to the overview](../README.md) · [Deutsch](usage.de.md)

## Getting started

1. Open a lecture PDF directly with **⌘O**. Alternatively, choose **File → New** and **Open Lecture PDF** (⌘I).
2. Choose a slide on the left. On the right, write and format notes, add formulas with **Formula** or draw with **Sketch**.
3. Update the open file with **⌘S** or **Save**. Next to the lecture's name at the top, a grey dot means unsaved changes and a green check mark means everything is saved. For a PDF you opened directly, the original lecture file is replaced at the same path by the study PDF with your notes. Every later save updates the same file. The native macOS versions and revert features manage changes to the document.
4. Open the same PDF in UniPDF later and keep working. Besides the visible pages, its metadata holds the original slides, notes, formulas and sketches. UniPDF restores the editable state from them; saving again does not add the layout a second time.
5. **Export Study PDF** (⇧⌘E) creates an additional copy in a place you choose. Long notes continue on extra pages. The slide is repeated there for orientation; the sketch appears on the first page for the slide.

Existing `.unipdf` projects are still supported. **⌘S** also updates them in their current place. To move such a project to the PDF way of working, export it as a PDF once and then open the exported PDF. If it should replace the earlier lecture file, choose that file's path when exporting.

The editable data is embedded in the PDF; no additional project file is needed. Other PDF apps can remove metadata when they save. To keep editing your notes, save the file in UniPDF.

The two buttons next to the zoom (or View → **Scroll Continuously**, ⌥⌘J) switch between **single page** and **continuous scrolling** through all slides. When scrolling continuously, every visible slide shows its annotations. Wherever you draw, write or comment, that slide becomes the current one without the view jumping, and the notes follow. UniPDF remembers the setting. The notes can be collapsed with the button on the far right of the toolbar or with **⌥⌘0**, and the slide then uses the full width. UniPDF remembers that too. The notes open again by themselves when you create or open a comment or when a search result is in the notes. Change slides with **⌘↑ / ⌘↓**. The divider between the PDF and the notes can be dragged. UniPDF remembers the width of the notes and the window size across launches; the library has its own window size. The sketch area offers a pen, line, arrow, rectangle and ellipse, four colors and three line widths. Elements can be removed and restored step by step.

In the PDF area, **→ / ↓** go to the next slide and **← / ↑** to the previous one. At the first and last slide the selection stays where it is. **⌘↑ / ⌘↓** keep working as direct commands. While you type in notes, formulas and text boxes, the arrow keys move the text cursor. When an annotation is selected, they move the annotation; press **Esc** to deselect it and change slides again. In the file list, the arrows move through the list.

## Marking up the slide

The tools in the header of the slide area put annotations on the slide itself, unlike the **Sketch**, which belongs to the notes.

- **Pen:** draw freely, three line widths.
- **Highlighter:** turn on the highlighter in the header of the slide area and drag over PDF text. The selected words and lines are highlighted; like a real highlighter, the color sits behind the text, so the text stays dark and easy to read. Alternatively, select text with the normal PDF tool first and then click **Highlighter**. Yellow, green, pink and blue are ready to use; the color well lets you choose your own. The highlighter color is stored separately from the pen color. Press **Esc** to return to the selection tool; click a highlight to change its color or delete it with **⌫**. Scanned slides without selectable text lack the text layer this needs; use the pen there.
- **Eraser:** drag over pen strokes and highlights. In the row below the tools you choose between two modes: **Precise** removes only what it touches; a stroke falls apart into the pieces on either side, and highlights always lose whole characters. **Stroke** deletes every stroke and highlight it touches entirely. A circle shows its size; **Small**, **Medium** and **Large** are available. **⌘Z** takes back a whole stroke of the eraser at once. It does not erase shapes, text boxes or images; select those and delete them with **⌫**. The sketch in the notes keeps its own steps for removing and restoring.
- **Text box:** click on the slide and type. Font, size, bold, italic and underline apply to the whole text box. An empty text box disappears again. Double-click to edit the text later. With the **lock** at the start of the text row, the text tool stays active: every further click on the slide starts a new text box right away, and a click on an existing one edits it. **Esc** switches back to selecting. The setting is kept after a restart.
- **Shapes:** drag out a rectangle, square, circle, oval or line. The shape button draws the shape you used last; the arrow next to it chooses a different one. **⇧** keeps the proportions of rectangles and ovals and snaps lines to 45° steps.
- **Image:** the image symbol chooses a file, and **⌘V** inserts an image from the clipboard, such as a screenshot. Very large images are scaled down to 2400 pixels on their longest side.
- **Colors:** four fixed colors and any color from the color well. When the slide area is narrow, text boxes show only the color well.

With the arrow tool you select an annotation, drag it somewhere else or resize it by its handles. The settings in the row below the tools then apply to the selection. The arrow keys move it by one point, with **⇧** by ten. **⌫** or the trash symbol deletes it, **⌘X**, **⌘C** and **⌘V** work, and **⌘Z** undoes. **Esc** ends a tool or clears the selection. Outlined shapes respond only to their line, so that text inside them stays selectable; PDF text next to annotations can still be selected.

Annotations stay in place and upright when you zoom and on rotated slides. They appear on the slide in the study PDF and are still editable after reopening; the original slide itself is not changed. Text stays searchable in the PDF. If a font is missing on another Mac, the system font is used there. The **original slide** copy for the AI prompt shows the slide without annotations, the study PDF with them.

Highlights stay visible when saving and exporting and are editable after reopening. Files in project format 3 need a version of UniPDF that supports the highlighter. Older files still open and are converted when saved.

## Starting without a file

If files were open when you quit, macOS restores those tabs. Otherwise UniPDF opens the file you opened last, even if it has been renamed or moved since. If it no longer exists or is in the Trash, the library opens. The same happens when you click the Dock icon with no window open. A new empty document is still available with **File → New** or **+** in the tab bar.

## Several files

Open files share one window as tabs, regardless of the system's tab setting. Click a tab to switch files; **+** opens a new tab with the start page. Right-click a tab for **Move Tab to New Window**; you can also drag a tab out of the bar. **Window → Merge All Windows** brings separate windows back together. The library stays a window of its own.

## Library

**File → Library** (⇧⌘L) opens the file manager. **Choose Folder …** gives UniPDF access to a folder, such as the one for your studies. The folder stays connected across launches. Folders and files appear as tiles or as a list, files with a thumbnail of their first page. The switch is to the right of the path; your choice is kept. In the viewer, the folder button next to the sidebar button opens the library.

- **Navigating:** double-click to go into a folder. The path at the top and the back arrow (⌘↑) take you back up. The arrow keys select a tile, Return opens it.
- **Opening:** double-click opens PDFs and `.unipdf` projects in UniPDF, other files in their usual app.
- **Organizing:** drag a tile onto a folder to move it, or onto an item in the path. The context menu offers **Rename** and **Show in Finder**; **New Folder** (⇧⌘N) creates the folder in the current folder.
- **Removing:** **Move to Trash** (⌘⌫) asks first; everything can be restored from the Trash.

Existing files are never overwritten, and changes stay within the shared folder. Open documents follow their file when it is renamed or moved. Symbolic links appear as files and are not followed. Changes made in the Finder appear as soon as the app is active again, or with ⌘R. **Disconnect Folder** only forgets the folder; the files stay unchanged.

In the viewer's sidebar, the collapsible **Files** section sits above the slides. It shows the same folder as a tree, as in the Finder: the triangle or a click on a folder expands it, and a click on a file opens it in a new tab. The open file is shown in bold, and its folder is expanded at launch. The sidebar can be widened at its edge and hidden with the sidebar button at the top left.

The thumbnail shows the file's actual first page, so for a saved study PDF it shows the slide and notes together.

## Preparing a question for an AI

Click **AI Prompt** next to **Formula** and **Sketch** (⌥⌘K). The prompt is copied to the clipboard right away and shown as a preview. Add your own question in the question field and copy it again with **Copy Prompt**. Then paste it into the AI chat of your choice with **⌘V**.

The prompt names the actual path of the open file and the current original slide number. It also creates two local PDF copies in the temporary folder: the current study PDF including unsaved notes, and the selected original slide on its own. That way, file paths and slide numbers match even with continuation pages. The original file is not saved or changed by this. The copies contain the visible PDF pages without the embedded editable project. Every use creates its own copies, so a prompt you already copied points to the same state.

Nothing is sent automatically. An AI with access to local files can use the paths. For an AI without local file access, attach the PDF copies as well. The system may remove temporary files later; the prompt is meant to be used soon. The prompt is written in the language you use UniPDF in and asks for an answer in that language.

## Commenting on passages

A comment belongs to a spot on the slide and appears as a tag in your notes.

- **Creating:** select text on the slide and choose **Comment** from the context menu, or press **⌥⌘M**. Alternatively, drag over the text with the **speech bubble** in the toolbar. Whole words always count.
- **Areas:** if the drag with the speech bubble starts on an empty spot, such as next to a graphic, you get an area comment. With **⌥** it is always an area, even over text. Slides without text only have areas. The pointer shows what will happen: over text the text cursor, on an empty spot and with ⌥ a pen.
- **On the slide**, the spot has a pastel background and a slightly darker outline. Hovering over it shows the comment.
- **In the notes**, a tag appears with the beginning of the passage. It goes where your cursor was last, otherwise at the end. A click on the tag expands the **card**. It shows the quote, your comment with the same formatting and formulas as the notes, the color and the date.
- **Linked both ways:** a click on the quote in the card selects the spot on the slide. A click on the spot on the slide opens its card.
- **Colors:** new comments take rose, peach, lemon, mint, sky and lavender in turn. The color can be changed in the row below the tools and in the card.
- **Deleting:** if you delete the tag from the notes, the mark on the slide disappears too, and the other way round; the same goes for **Delete** in the card. A **⌘Z** brings both back. The cursor skips over a tag, and **⌫** always removes it entirely.
- **Search:** ⌘F also finds the text of comments. A result opens the card.
- **Study PDF:** commented spots carry a small number on the slide. In the notes, the tag's position shows the same tag as in the app, with its number and the shortened beginning of the passage. All comments follow below the notes, each with its tag. A vertical bar in the comment's color runs along its full length, including on continuation pages.

UniPDF saves comments in the PDF, like notes and annotations. Older versions of UniPDF cannot open files with comments.

## Searching the document

The **magnifying glass** at the top right or **⌘F** opens the search at the top of the sidebar. It searches the whole document: the text of the slides, your notes and the text boxes on the slides. Upper and lower case and accents do not matter, so "uber" also finds "Über".

- The results are listed by slide in the sidebar, with the found word in its sentence. A symbol shows whether the result is in the slide text, the notes or a text box.
- All results are highlighted in yellow on the slide and in the notes.
- A click on a result opens the slide and selects the spot. A result in a text box selects the text box.
- **Return** or **⌘G** jumps to the next result, **⇧⌘G** to the previous one. After the last one it starts again from the top.
- A selected result in the slide text can be highlighted directly with the **Highlighter**.
- **Esc** or the ✕ in the search field ends the search, and the slides appear again.

## Formatting notes

The notes format themselves as you type, much like chat apps. The markers stay faintly visible; in the study PDF they disappear:

- `**bold**` or `*bold*`, `_italic_`, `~strikethrough~` or `~~strikethrough~~`, `` `code` ``
- `# Heading`, `## smaller heading`
- `- bullet` (also `*` or `•`), where the dash appears as a dot, and `1. numbered list`. **Return** continues the list, **Return** on an empty item ends it.
- `> quote`

**⌘B** and **⌘I** add the markers around the selection or remove them again. The menu with the **B I U** symbol contains the same commands, lists and a quick reference. The notes stay plain text: an AI prompt or a copy contains the markers exactly as you wrote them.

## Formulas

Formulas sit right in the notes: between `$ … $` within a sentence, between `$$ … $$` as a block of their own. When the cursor is not in the formula, UniPDF shows it typeset. A click on it shows the notation again. While you type, a box right below shows the finished formula and changes with every character. A dollar sign after a number, as in "5$", stays normal text.

**Formula** shows the formula bar:

- **Formula Block** inserts a new block on its own line at the cursor.
- The pop-up menu chooses a topic: Basics, Set Theory, Logic, Calculus, Linear Algebra, Probability, Greek or Arrows. Below it are the most common symbols and templates to insert directly. The last topic you chose stays selected.
- **x²** and **xₙ** set superscript and subscript. In a formula they insert `^{}` or `_{}` at the cursor. In normal text, the word before the cursor becomes the base of a new formula: `x`, then **x²** and `2` gives `$x^{2}$`.
- **a⁄b** inserts a fraction.

The notation is a small subset of LaTeX that works offline:

- Powers and indices: `x^{2}`, `a_{n}`
- Fractions, roots, binomial coefficients: `\frac{a}{b}`, `\sqrt{x}`, `\sqrt[3]{x}`, `\binom{n}{k}`
- Number sets: `\mathbb{R}`, `\mathbb{N}`
- Greek letters, operators, arrows, logic and sets, such as `\alpha`, `\sum`, `\int`, `\lim`, `\Rightarrow`, `\forall`, `\in`, `\subseteq`, `\cup`, `\emptyset`
- Functions such as `\sin`, `\ln`, `\det` appear upright. `\vec{v}`, `\bar{x}` and `\text{…}` are supported as well.
- Unicode characters such as ∈ or ℝ can be written directly in the text.

This is not full LaTeX. Fractions are shown compactly with a fraction slash "⁄". Unknown commands stay as text. The export uses the same rendering as the notes.

Older projects had a separate formula field. If a slide still has such a formula, it appears below the notes. **Move into Notes** inserts it there as a formula block.

## Language

UniPDF follows the language of your Mac: with German as your preferred language the app is German, otherwise English. To use a different language for UniPDF only, choose it under System Settings → General → Language & Region → Applications. The language also applies to the study PDF's labels and to the AI prompt.
