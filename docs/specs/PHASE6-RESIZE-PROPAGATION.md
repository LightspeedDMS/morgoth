# Phase 6: Resize Propagation

**Version:** 0.1.0
**Status:** Draft
**Date:** 2026-02-18
**Authors:** Lilith + Claude (Opus 4.6)
**Parent Spec:** [MORGOTH-SPEC.md](MORGOTH-SPEC.md)

---

## 1. Conceptual Foundation

When a user resizes their terminal window, four things must happen:

1. Morgoth detects the new terminal dimensions (SIGWINCH)
2. The layout engine recomputes pane regions for the new size
3. Each pane's VTerm cell grid resizes to match new inner dimensions
4. Each terminal pane's child shell learns about its new size via TIOCSWINSZ

Steps 1, 2, and 4 already partially work — but have bugs. Step 3 is missing
entirely: the VTerm is currently **destroyed and recreated** on resize
(`VTerm·new`), which loses all scrollback content.

### 1.1 Current Bugs

Two bugs in the existing resize path:

1. **Outer dimensions passed to `Pty·set_size`:** Both `Pane·new` (line 67)
   and the SIGWINCH handler (line 1689) call
   `Pty·set_size(fd, region.h, region.w)` — but the inner content area is
   `region.h - 2` by `region.w - 2` (subtracting the border). Child shells
   get the wrong size.

2. **VTerm destroyed on resize:** The SIGWINCH handler does
   `panes[ri].vterm = VTerm·new(h-2, w-2)` which creates a fresh VTerm,
   discarding all scrollback and visible content. The correct behavior is
   to resize the existing VTerm in place.

### 1.2 Key Insight

PTY resize is a two-step process:
1. Set the new dimensions on the PTY master fd via `ioctl(TIOCSWINSZ)`
2. The kernel automatically sends SIGWINCH to the foreground process group
   on the slave side

Step 1 is sufficient — the kernel handles step 2. The stdlib already has
native `ioctl(TIOCSWINSZ)` behind `Pty·set_size` (Phase 5). The fix is
passing inner dimensions (`region.h - 2`, `region.w - 2`) instead of outer.

---

## 2. Behavioral Contracts

### 2.1 Resize Detection

```
on SIGWINCH:
    new_rows, new_cols ← term_get_winsize(stdout)
    if new_rows != screen.rows or new_cols != screen.cols:
        trigger relayout
```

**Already implemented** in the event loop (Phase 2). Morgoth polls
`Sys·signal_pending(SIGWINCH)` each tick and calls `term_get_winsize(1)`.

### 2.2 Layout Recomputation

```
relayout(panes, new_rows, new_cols):
    regions ← compute_grid(grid_config, new_rows, new_cols)
    for each pane, region in zip(panes, regions):
        pane.region ← region
        redraw pane border and content
```

**Already implemented** in the event loop. The screen grid is recreated and
panes are re-rendered.

### 2.3 PTY Size Propagation (BUGFIX)

`Pty·set_size` is already called in the SIGWINCH handler (line 1689), but
passes outer dimensions. The fix is straightforward:

```
// BEFORE (buggy — passes outer dims):
Pty·set_size(panes[ri].master_fd, regions[ri].h, regions[ri].w)

// AFTER (correct — passes inner dims):
≔ inner_rows = regions[ri].h - 2;
≔ inner_cols = regions[ri].w - 2;
Pty·set_size(panes[ri].master_fd, inner_rows, inner_cols);
```

Since Phase 5 added real `ioctl(TIOCSWINSZ)` behind `Pty·set_size`, this
propagates to the child shell automatically.

### 2.4 VTerm Resize (NEW — replaces VTerm destruction)

Currently the SIGWINCH handler destroys the VTerm:
```
panes[ri].vterm = VTerm·new(regions[ri].h - 2, regions[ri].w - 2);
```

This must be replaced with an in-place `vterm_resize` function that
preserves content:

```
rite vterm_resize(vterm, new_rows, new_cols) {
    ≔ old_rows = vterm.rows;
    ≔ old_cols = vterm.cols;

    // 1. Push overflow rows to scrollback
    ⎇ (new_rows < old_rows) {
        ≔ mut i = 0;
        ⟳ (i < old_rows - new_rows) {
            push(vterm.scrollback, vterm.cells[i]);
            i = i + 1;
        }
        // Evict scrollback if over cap
        ⟳ (len(vterm.scrollback) > vterm.scrollback_cap) {
            // remove oldest
            vterm.scrollback = slice(vterm.scrollback, 1, len(vterm.scrollback));
        }
    }

    // 2. Build new cell grid
    ≔ new_cells = [];
    ≔ mut r = 0;
    ⟳ (r < new_rows) {
        ≔ old_r = r + (old_rows - new_rows);  // offset if shrunk
        ⎇ (old_r >= 0 ⩓ old_r < old_rows) {
            // Copy existing row, truncate or extend columns
            ≔ old_row = vterm.cells[old_r];
            ≔ new_row = [];
            ≔ mut c = 0;
            ⟳ (c < new_cols) {
                ⎇ (c < len(old_row)) {
                    push(new_row, old_row[c]);
                } ⎉ {
                    push(new_row, Cell·new(" ", "7", "0"));
                }
                c = c + 1;
            }
            push(new_cells, new_row);
        } ⎉ {
            // New empty row
            push(new_cells, make_empty_row(new_cols));
        }
        r = r + 1;
    }

    // 3. Update VTerm state
    vterm.cells = new_cells;
    vterm.rows = new_rows;
    vterm.cols = new_cols;

    // 4. Clamp cursor
    ⎇ (vterm.cursor_row >= new_rows) { vterm.cursor_row = new_rows - 1; }
    ⎇ (vterm.cursor_col >= new_cols) { vterm.cursor_col = new_cols - 1; }

    // 5. Reset scroll offset
    vterm.scroll_offset = 0;
}
```

This preserves scrollback content and visible cells, pushing overflow rows
into the scrollback buffer when the terminal shrinks.

---

## 3. Constraints & Invariants

```
P1: After resize, ∀ terminal pane p:
    pty_dimensions(p.master_fd) = (p.region.h - 2, p.region.w - 2)
    // PTY size matches inner pane size

P2: After resize, ∀ terminal pane p:
    p.vterm.rows = p.region.h - 2
    p.vterm.cols = p.region.w - 2
    // VTerm grid matches inner pane size

P3: After resize:
    p.vterm.cursor_row < p.vterm.rows
    p.vterm.cursor_col < p.vterm.cols
    // Cursor is within bounds

P4: Resize must complete within one event loop tick
    // No visible partial state
```

---

## 4. Integration Points

### 4.1 Event Loop (morgoth.sg)

The resize path in the event loop currently:
1. Detects SIGWINCH
2. Queries new terminal size
3. Recreates screen grid
4. Recomputes pane regions
5. Re-renders borders and content

**New step** between 4 and 5:
- For each terminal pane: resize VTerm, call `Pty·set_size`

### 4.2 Stdlib (already sufficient)

- `Pty·set_size` already calls `ioctl(TIOCSWINSZ)` for real fds (Phase 5)
- `term_get_winsize` already uses native `ioctl(TIOCGWINSZ)` (Phase 2)
- `Sys·signal_pending(SIGWINCH)` already works (Phase 4)

No stdlib changes needed. All work is in `morgoth.sg`.

### 4.3 Initial Spawn (BUGFIX)

`Pane·new` (line 67) already calls `Pty·set_size` at spawn time, but passes
outer dimensions:

```
// BEFORE (buggy):
Pty·set_size(pty.master_fd, region.h, region.w);

// AFTER (correct):
Pty·set_size(pty.master_fd, region.h - 2, region.w - 2);
```

This is the same outer-dims bug as in the SIGWINCH handler (section 2.3).

---

## 5. Test Plan

| ID | Test | Validates |
|----|------|-----------|
| P6_600 | Pty·set_size after relayout sets correct inner dimensions | P1 |
| P6_601 | VTerm resize clamps cursor to new bounds | P3 |
| P6_602 | VTerm resize adjusts cell grid dimensions | P2 |
| P6_603 | Content outside new bounds moves to scrollback | Edge case |
| P6_604 | Initial spawn sets PTY size to pane inner dims | 4.3 |

### E2E Validation

```
tmux new-session -d -s resize_test -x 120 -y 40
tmux send-keys "$SIGIL run $MORGOTH" Enter
sleep 3
# Resize terminal
tmux resize-window -t resize_test -x 80 -y 24
sleep 1
# Verify child shell sees new size
tmux send-keys "tput cols; tput lines" Enter
sleep 1
tmux capture-pane -p  # Should show ~36 cols, ~9 lines (inner dims)
```

---

## 6. Open Questions

1. **Scrollback on shrink:** When the terminal shrinks, content at the bottom
   of the VTerm is lost. Should it be pushed to scrollback, or just truncated?
   - Recommendation: Push to scrollback (matches xterm/tmux behavior)

2. **Minimum pane size:** What's the smallest usable pane? Should Morgoth
   refuse to resize below some threshold?
   - Recommendation: Minimum 3 rows x 10 cols (1 content row, 2 border)

3. **Rapid resize debouncing:** If the user drags to resize, many SIGWINCH
   signals arrive in rapid succession. Should Morgoth debounce?
   - Recommendation: No debounce needed — the event loop naturally coalesces
     because `Sys·signal_pending` clears on read and we process at most once
     per tick

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0 | 2026-02-18 | Initial draft |
