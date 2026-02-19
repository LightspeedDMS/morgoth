# Phase 8: Copy/Paste Mode

**Version:** 0.1.0
**Status:** Draft
**Date:** 2026-02-18
**Authors:** Lilith + Claude (Opus 4.6)
**Parent Spec:** [MORGOTH-SPEC.md](MORGOTH-SPEC.md)

---

## 1. Conceptual Foundation

Terminal multiplexers must let users copy text from pane output. Without this,
the only way to extract text is to pipe commands to files — a non-starter for
interactive use.

### 1.1 Copy Mode Lifecycle

```
Normal mode
    │
    └── Ctrl-B [  ──→  Copy mode
                          │
                          ├── Arrow keys / vim keys: move cursor
                          ├── Space: begin selection
                          ├── Enter: copy selection to clipboard, exit
                          ├── Escape / q: cancel, exit
                          └── /: search (delegates to Phase 9)
```

Copy mode freezes the focused pane's output (new data buffers but doesn't
render) and overlays a movable cursor on the scrollback + visible content.

### 1.2 Selection Model

Two selection modes:

- **Character selection** (default): arbitrary start/end positions
- **Line selection** (toggled with 'V'): selects entire lines

Selection is visually highlighted using SGR reverse video.

---

## 2. Type Architecture

```
CopyModeState:
    active: bool
    cursor_row: int         // relative to text_lines
    cursor_col: int
    selecting: bool
    select_start: Position  // (row, col) where selection began
    line_mode: bool         // line selection vs character selection
    text_lines: [string]    // flattened text extracted from cell arrays

Position:
    row: int
    col: int
```

---

## 3. Behavioral Contracts

### 3.1 Enter Copy Mode

```
on leader + '[':
    pane ← panes[focus]
    // Scrollback + visible cells are arrays of {ch, fg, bg} cell objects.
    // Extract the text (ch field) from each cell to build string lines.
    text_lines ← []
    for row in pane.vterm.scrollback ++ pane.vterm.cells:
        line ← ""
        for cell in row:
            line ← line + cell.ch
        push(text_lines, line)
    copy_state ← CopyModeState {
        active: true,
        cursor_row: len(text_lines) - 1,   // start at bottom
        cursor_col: 0,
        selecting: false,
        line_mode: false,
        text_lines: text_lines,
    }
    render copy mode overlay
    show "[COPY]" indicator in status bar
```

### 3.2 Cursor Movement

| Key | Action |
|-----|--------|
| `h` / Left | cursor_col -= 1 (clamped) |
| `j` / Down | cursor_row += 1 (clamped) |
| `k` / Up | cursor_row -= 1 (clamped) |
| `l` / Right | cursor_col += 1 (clamped) |
| `0` | cursor_col = 0 |
| `$` | cursor_col = len(line) - 1 |
| `g` | cursor_row = 0 (top of scrollback) |
| `G` | cursor_row = len(text_lines) - 1 (bottom) |
| `Ctrl-U` | cursor_row -= half_page |
| `Ctrl-D` | cursor_row += half_page |
| `w` | next word boundary |
| `b` | previous word boundary |

### 3.3 Selection

```
on Space:
    if not selecting:
        selecting ← true
        select_start ← (cursor_row, cursor_col)
    else:
        // Space again cancels selection
        selecting ← false
```

While selecting, the region between `select_start` and the current cursor
is highlighted with reverse video.

```
on 'V':
    line_mode ← not line_mode
    if line_mode and selecting:
        // Extend selection to full lines
        select_start.col ← 0
```

### 3.4 Copy and Exit

```
on Enter:
    if selecting:
        text ← extract_selection(text_lines, select_start, cursor, line_mode)
        write_to_clipboard(text)
        show "Copied N lines" in status bar for 2 seconds
    exit copy mode

on Escape or 'q':
    exit copy mode without copying
```

### 3.5 Clipboard Integration

Clipboard access uses the OSC 52 escape sequence, which is supported by
most modern terminals (xterm, iTerm2, alacritty, kitty, WezTerm):

```
write_to_clipboard(text):
    encoded ← base64_encode(text)
    Sys·write(stdout, "\x1b]52;c;" + encoded + "\x1b\\", ...)
```

This writes through Morgoth's own stdout to the host terminal, which
interprets the OSC 52 and puts the text on the system clipboard.

Fallback for terminals without OSC 52 support: write to a temp file and
invoke `xclip`, `xsel`, `pbcopy`, or `wl-copy` as available.

---

## 4. Constraints & Invariants

```
P1: In copy mode, pane output is frozen
    New PTY data is buffered, not rendered

P2: cursor_row ∈ [0, len(text_lines) - 1]
    cursor_col ∈ [0, len(text_lines[cursor_row]) - 1]
    // Cursor always within bounds

P3: Exiting copy mode flushes buffered PTY data
    // No data loss

P4: Copy mode does not affect other panes
    Non-focused panes continue updating normally

P5: Selection highlight uses reverse video only
    // Does not corrupt cell attributes
```

---

## 5. Error Conditions

| Condition | Behavior |
|-----------|----------|
| Empty scrollback + visible | Enter copy mode with cursor at 0,0 |
| OSC 52 not supported by host | Fall back to xclip/xsel/pbcopy |
| No clipboard tool available | Show "clipboard unavailable" in status bar |
| Selection is empty (start = end) | Copy empty string (no-op) |

---

## 6. Integration Points

### 6.1 Stdlib Requirements

Stdlib functions needed (both already exist):

| Function | Purpose | Status |
|----------|---------|--------|
| `base64_encode(string) → string` | For OSC 52 clipboard | Already in stdlib (line ~10921) |
| `env(name) → string` | Read `$SHELL`, detect clipboard tools | Already in stdlib |

No new stdlib functions are required for this phase.

### 6.2 Input State Machine

Copy mode is a distinct input state, separate from normal mode and leader
mode:

```
process_input(input_state, byte, ...):
    if input_state.copy_mode.active:
        return process_copy_mode_input(input_state.copy_mode, byte)
    // ... existing leader/normal logic
```

### 6.3 Rendering

Copy mode rendering overlays the cursor and selection highlight on the
frozen pane content. The cursor is rendered as a block (reverse video at
cursor position). Selection is rendered as reverse video on all selected
cells.

---

## 7. Test Plan

| ID | Test | Validates |
|----|------|-----------|
| P8_800 | Enter copy mode sets active flag, freezes content | 3.1, P1 |
| P8_801 | Cursor movement clamps to bounds | 3.2, P2 |
| P8_802 | Space begins selection | 3.3 |
| P8_803 | Enter extracts selected text | 3.4 |
| P8_804 | Escape exits without copying | 3.4 |
| P8_805 | Line mode selects full lines | 3.3 |
| P8_806 | Vim navigation (g, G, 0, $, w, b) | 3.2 |
| P8_807 | Half-page scroll (Ctrl-U, Ctrl-D) | 3.2 |
| P8_808 | Copy mode doesn't affect other panes | P4 |
| P8_809 | Exiting flushes buffered data | P3 |
| P8_810 | OSC 52 clipboard output is valid | 3.5 |

---

## 8. Open Questions

1. **Mouse selection:** Should click-drag select text in copy mode?
   - Recommendation: Yes, in a future iteration. Keyboard-only for Phase 8.

2. **Rectangular selection:** tmux supports rectangular (block) selection
   with Ctrl-V. Worth adding?
   - Recommendation: Defer. Character + line modes cover 95% of use cases.

3. **Search in copy mode:** Should `/` trigger scrollback search (Phase 9)?
   - Recommendation: Yes, but only if Phase 9 is implemented. Otherwise
     `/` is a no-op in copy mode.

4. **Multi-pane copy:** Should copy mode work across pane boundaries?
   - Recommendation: No. Copy within focused pane only. Cross-pane copy
     is a Phase 18 concern (cross-instance communication).

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0 | 2026-02-18 | Initial draft |
