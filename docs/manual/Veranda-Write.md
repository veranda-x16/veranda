# Veranda Write

Veranda Write is **Veranda's word processor**. Use it for letters,
stories, notes and any text with fonts and styles. For plain text files
(programs, lists, configuration files) use [Veranda Edit](Veranda-Edit.md).

Veranda Write runs only on Veranda. This page describes version 0.2
("stage 2"). MIT licence, Copyright (c) 2026 Marcin Spoczynski.

Veranda Write was called **Commander Write** before Veranda 1.0. Its
documents (`.cwr`) are the same: those you made before open as they did.
If `/VERANDA/APPS` still has `Commander Write`, you can delete it.

## Start it

- Double-click **Veranda Write** in `/VERANDA/APPS` (the **Apps**
  place in the sidebar).
- Or double-click a `.cwr` document: Veranda Write opens it.

Without a document it starts with an empty page, and its Open and Save
box starts in `/DOCUMENTS`.

New to it? Try [Your first letter](Your-first-letter.md) first.

## The window

- **The menu bar**: Veranda Write, File, Edit, Text, Style, Format,
  Font, Size.
- **The title band**: the document's name, `*` when there are unsaved
  changes.
- **The toolbar**: the font and size; **B**, **I**, **U**; four
  alignment buttons; a bulleted and a numbered list; indent less and
  indent more; the paragraph's style name.
- **The page**: the text wrapped to a 6.5-inch column (A4 or Letter
  with 1-inch margins).
- **The status bar**: page, line, column, and "Modified".

## Features

### Character styles

- Any font in `/VERANDA/FONTS` at its sizes (Gate Sans 9, 12, 18, 27;
  Gate Mono 10 and 12; the system font).
- **Bold**, *italic* and underline, mixed freely on a line.
- **Text > Larger** (Ctrl+E) and **Smaller** (Ctrl+Shift+E) step
  through the font's sizes.
- With text selected, a style changes the selection. With nothing
  selected, it changes what you type next.

### Paragraph styles

The **Style** menu has named styles:

| Style | Looks like |
|---|---|
| Body | normal text |
| Heading 1, 2, 3 | bold, 27, 18 and 12 points |
| Quote | indented on both sides, italic |
| Bulleted list | a bullet before each paragraph |
| Numbered list | 1, 2, 3 ... before each paragraph, counted by itself |

- Return after a heading gives Body.
- Return in an **empty** list item ends the list.
- Clicking an active list button in the toolbar goes back to Body.

The **Format** menu sets: align left, centre, align right, justify;
indent more and less (a quarter inch each); single, one and a half, or
double line spacing; space after paragraphs (on or off). These apply to
the selected paragraphs, or to the cursor's paragraph.

### Find and Replace

**Edit > Find...** (Ctrl+F) or **Replace...** (Ctrl+H) opens a panel
under the text: **Find**, **Replace with**, **Match case**, **Whole
word**, **Find next**, **Replace**, **Replace all**. A match may span a
style change. **Replace all** is one undo step. The text to find is 40
characters at most.

### Other tools

- **Veranda Write > Word count...**: words, characters, characters
  without spaces, paragraphs and pages, and the selection's words.
- **Edit > Go to page...** (Ctrl+Shift+G).
- **Text > Insert date and time** (Ctrl+Shift+D), in the form
  "21 November 2026, 14:05", from the X16's clock.
- **Undo and redo**, many levels: typing, deleting, formatting,
  pasting.
- **Cut, copy and paste.** Inside Veranda Write the styles are kept.
  With other programs the text goes through Veranda's clipboard, as
  plain text.
- **Alt+Tab** puts Veranda Write aside with its document.

## Menus

| Menu | Items |
|---|---|
| Veranda Write | About Veranda Write, Word count... |
| File | New, Open..., Save, Save as..., Close, Quit |
| Edit | Undo, Redo, Cut, Copy, Paste, Select all, Find..., Find next, Replace..., Go to page... |
| Text | Plain, Bold, Italic, Underline, Larger, Smaller, Insert date and time, Page break (not ready yet: it says "Not yet") |
| Style | Body, Heading 1, Heading 2, Heading 3, Quote, Bulleted list, Numbered list |
| Format | Align left, Centre, Align right, Justify, Indent more, Indent less, Single spacing, One and a half lines, Double spacing, Space after paragraphs |
| Font | the installed fonts (up to 8) |
| Size | the sizes of the current font |

## Keys

| Key | Action |
|---|---|
| Arrows | move; with **Shift**: select |
| Ctrl+Left, Ctrl+Right | a word left, right |
| Home, End | start, end of the line |
| PgUp, PgDn | a screen up, down |
| Ctrl+Home (or Ctrl+PgUp), Ctrl+End | start, end of the document |
| Backspace, Delete | delete left, right (or the selection) |
| Return | a new paragraph |
| Tab | a tab (tab stops every half inch) |
| Esc | remove the selection |
| Ctrl+N, Ctrl+O, Ctrl+S | New, Open, Save |
| Ctrl+Shift+S | Save as |
| Ctrl+W, Ctrl+Q | Close, Quit |
| Ctrl+Z, Ctrl+Y | Undo, Redo |
| Ctrl+X, Ctrl+C, Ctrl+V, Ctrl+A | Cut, Copy, Paste, Select all |
| Ctrl+T, Ctrl+B, Ctrl+I, Ctrl+U | Plain, Bold, Italic, Underline |
| Ctrl+E, Ctrl+Shift+E | larger, smaller size |
| Ctrl+L, Ctrl+Shift+C, Ctrl+Shift+R, Ctrl+J | align left, centre, align right, justify |
| Ctrl+F | Find (the panel) |
| Ctrl+H (or Ctrl+R) | Replace (the panel) |
| Ctrl+G | Find next (also with the panel closed) |
| Ctrl+Shift+G | Go to page |
| Ctrl+Shift+D | Insert date and time |
| Alt + any of these letters | the same as Ctrl |
| Alt+Tab | put Veranda Write aside |

**In the Find panel:** typing goes into the field; **Tab** switches
between Find and Replace with; **Return** finds the next; **Alt+C**
Match case; **Alt+W** Whole word; **Alt+N** Find next; **Alt+R**
Replace; **Alt+A** Replace all; **Esc** closes the panel. The arrows and
the Ctrl keys still work on the document.

**The mouse:** a click places the cursor; Shift+click and dragging
select (dragging past the top or bottom scrolls); a double-click selects
a word; the wheel scrolls three lines; a click on the scroll bar goes a
page up or down.

## Files

- Documents are `.cwr` files (Veranda Write's own format, version
  1.1). **Save as** adds `.cwr` to a name without an extension. Names
  can be up to 63 characters.
- **Plain text files** open too (File > Open, choose All files): LF,
  CR LF or CR line ends. The document is then untitled: Save asks for a
  name and saves a `.cwr` file. Veranda Write cannot save plain text.
- Saving is safe: Veranda Write writes a temporary file
  (`~CWRITE.TMP`), then replaces the old file. If the write fails, the
  old file is still there.
- New, Close, Open and Quit ask "Save the changes to ...?" (Yes, No,
  Cancel). Save as asks before it replaces a file.

## Limits

- **Document size:** about 190 KB of text on a 512 KB X16; about 1.2 MB
  with 2 MB.
- In one document: at most 128 character styles, 32 paragraph styles
  and 8 fonts.
- The fonts have the 96 ASCII characters. Letters such as é or ł are
  kept and saved, but shown as `?`.
- A font that is not in `/VERANDA/FONTS` is drawn in Gate Sans (the
  document keeps its name).
- **Undo** keeps about 24 KB of changes. The oldest steps go first. A
  single very large change (for example Replace all of more than about
  800 words) cannot be undone; Veranda Write says so. Save first.
- The clipboard for other programs holds the first 60,000 characters of
  a copy.
- **Not yet:** real pages, margins, headers and footers, page numbers,
  page breaks, printing, PDF. The page count in the status bar is
  nominal (9.7 inches of text a page).
- With a document that fills the memory, Alt+Tab offers to quit instead
  of putting it aside. Save first.
- Speed at 8 MHz with a 162 KB document: about a quarter of a second for
  a key, under a second for Page Down, about 10 seconds to open.

## Tips

- Save often (Ctrl+S).
- Use Gate Sans for most text.
- To send text to another program, select it, Ctrl+C, and paste it
  there.
