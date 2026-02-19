# Phase 7: Dynamic Pane Management

**Version:** 0.1.0
**Status:** Draft
**Date:** 2026-02-18
**Authors:** Lilith + Claude (Opus 4.6)
**Parent Spec:** [MORGOTH-SPEC.md](MORGOTH-SPEC.md)

---

## 1. Conceptual Foundation

Morgoth currently creates all panes at startup from `~/.morgoth/config.json`.
The layout is static for the lifetime of the session. For real use, users need
to create and destroy panes as their work changes.

### 1.1 Operations

Three core operations:

- **Create pane:** Add a new terminal or monitor pane to the layout
- **Close pane:** Kill the child process and remove the pane
- **Zoom pane:** Temporarily make one pane fill the entire screen

Split (horizontal/vertical) is deferred to Tier 3 (Phase 16) because it
requires replacing the flat grid layout with a tree-based layout engine.
For Phase 7, new panes are added to the grid and the grid re-tiles.

### 1.2 Layout Reflow

When panes are added or removed, the grid must reflow:

```
Current: 2x2 grid (4 panes)
    ┌───┬───┐
    │ 1 │ 2 │
    ├───┼───┤
    │ 3 │ 4 │
    └───┴───┘

After close pane 2: 3 panes → 2x2 grid with one empty cell, or 1x3
After add pane: 5 panes → 2x3 or 3x2
```

The grid dimensions auto-adjust to best fit the number of panes. The
algorithm should minimize aspect ratio distortion (panes should be
roughly rectangular, not extremely tall/narrow).

---

## 2. Behavioral Contracts

### 2.1 Keybindings

All operations are triggered via leader key (Ctrl-B):

| Sequence | Action |
|----------|--------|
| `Ctrl-B c` | Create new terminal pane |
| `Ctrl-B x` | Close focused pane (with confirmation) |
| `Ctrl-B z` | Toggle zoom on focused pane |
| `Ctrl-B m` | Create new monitor pane |

### 2.2 Create Pane

```
on leader + 'c':
    pty ← Pty·open()
    grid ← recompute_grid(len(panes) + 1, screen.rows, screen.cols)
    regions ← layout_grid(grid.rows, grid.cols, screen.cols, screen.rows)
    ≔ new_region = regions[len(panes)]
    ≔ inner_rows = new_region.h - 2
    ≔ inner_cols = new_region.w - 2
    Pty·set_size(pty.master_fd, inner_rows, inner_cols)
    ≔ shell = env("SHELL")
    ⎇ (shell == "") { shell = "/bin/bash"; }
    pid ← Sys·spawn_pty(shell, [], pty.slave_fd)
    vterm ← VTerm·new(inner_rows, inner_cols)
    pane ← Pane { type: "terminal", master_fd, pid, vterm, region: new_region, ... }
    push(panes, pane)
    relayout(panes, regions)
    propagate_sizes(panes)    // Phase 6
    focus ← len(panes) - 1   // focus new pane
```

The user's shell is determined by `env("SHELL")`, falling back to
`"/bin/bash"`.

**Current state:** `DEFAULT_SHELL` is hardcoded to `"/bin/bash"` (line 21).
`cfg.shell` is loaded from config (line 1042) but is dead code — never
passed to `Pane·new`. This phase should wire `cfg.shell` through to
`Pane·new` and add `env("SHELL")` as the runtime fallback.

### 2.3 Close Pane

```
on leader + 'x':
    if len(panes) <= 1:
        // Cannot close last pane — show status message
        return

    pane ← panes[focus]
    // Confirmation: show "[close? y/n]" in status bar
    wait for next keystroke
    if keystroke != 'y':
        return

    // Shutdown sequence
    Sys·kill(pane.pid, SIGTERM)
    Sys·waitpid(pane.pid, 0)
    Sys·close(pane.master_fd)

    remove(panes, focus)
    focus ← min(focus, len(panes) - 1)
    grid ← recompute_grid(len(panes), screen.rows, screen.cols)
    relayout(panes, grid)
    propagate_sizes(panes)
```

### 2.4 Zoom Toggle

```
on leader + 'z':
    if zoomed:
        // Unzoom: restore original layout
        zoomed ← false
        relayout(panes, grid)
    else:
        // Zoom: focused pane fills entire screen (minus status bar)
        zoomed ← true
        panes[focus].region ← Region { x: 0, y: 0, w: screen.cols, h: screen.rows - 1 }
        Pty·set_size(panes[focus].master_fd, screen.rows - 3, screen.cols - 2)
        // Other panes hidden but still running
```

### 2.5 Grid Auto-Sizing (NEW)

The current `layout_grid(rows, cols, screen_w, screen_h)` function takes
fixed grid dimensions from `cfg.grid.rows` / `cfg.grid.cols`. It does not
auto-size. This phase adds a new `recompute_grid` function that determines
optimal grid dimensions from pane count:

```
rite recompute_grid(num_panes, total_rows, total_cols) {
    // Find grid dimensions that minimize aspect ratio distortion
    ≔ mut best_rows = 1;
    ≔ mut best_cols = num_panes;
    ≔ mut best_ratio = 999;
    ≔ mut r = 1;
    ⟳ (r <= num_panes) {
        ≔ c = ceil(num_panes / r);
        ⎇ (r * c >= num_panes) {
            ≔ pane_w = total_cols / c;
            ≔ pane_h = total_rows / r;
            ≔ ratio = pane_w / pane_h;
            ⎇ (ratio < 1) { ratio = pane_h / pane_w; }
            ⎇ (ratio < best_ratio) {
                best_rows = r;
                best_cols = c;
                best_ratio = ratio;
            }
        }
        r = r + 1;
    }
    ↩ { "rows": best_rows, "cols": best_cols };
}
```

After computing optimal grid dimensions, call the existing
`layout_grid(grid.rows, grid.cols, screen_w, screen_h)` to get regions.

---

## 3. Constraints & Invariants

```
P1: len(panes) >= 1
    // Always at least one pane

P2: 0 <= focus < len(panes)
    // Focus index is valid

P3: After create or close:
    grid.rows * grid.cols >= len(panes)
    // Grid has enough cells for all panes

P4: After create:
    panes[len(panes)-1].pid > 0
    panes[len(panes)-1].master_fd > 0
    // New pane has valid process and fd

P5: After close:
    ∀ closed fd: not open
    ∀ closed pid: not running
    // No resource leaks

P6: During zoom:
    only focused pane is rendered
    all panes continue to receive PTY output
    // Background panes stay alive
```

---

## 4. Error Conditions

| Condition | Behavior |
|-----------|----------|
| `Pty·open` fails | Show error in status bar, don't create pane |
| `fork`/`exec` fails | Close PTY fds, show error in status bar |
| Close last pane | Refuse with status bar message |
| Close pane with stuck process | SIGTERM, wait 2s, SIGKILL |
| Create pane when terminal too small | Refuse with "terminal too small" |

---

## 5. Integration Points

### 5.1 Config (optional)

`~/.morgoth/config.json` may specify initial panes (existing behavior).
Dynamic panes extend this — the config provides the starting state, not
the permanent state.

Config fields (note: `shell` already exists in config loading but is dead
code — this phase wires it through):

```json
{
    "shell": "/bin/zsh",
    "max_panes": 12
}
```

### 5.2 Event Loop

The event loop's action dispatch (the `⎇`/`⎉` chain after `process_input`)
needs new action handlers:

- `"create_terminal"` → create pane flow
- `"create_monitor"` → create monitor pane flow
- `"close_pane"` → close pane flow (enters confirmation sub-state)
- `"zoom_toggle"` → zoom/unzoom flow

### 5.3 Input State Machine

`process_input` needs new leader-mode bindings:

| Byte | ASCII | Action |
|------|-------|--------|
| 99 | 'c' | `"create_terminal"` |
| 109 | 'm' | `"create_monitor"` |
| 120 | 'x' | `"close_pane"` |
| 122 | 'z' | `"zoom_toggle"` |

The confirmation sub-state for close requires a new `input_state` field:

```
input_state:
    leader_active: bool
    escape_buf: string
    confirming_close: bool    // NEW
```

---

## 6. Test Plan

| ID | Test | Validates |
|----|------|-----------|
| P7_700 | Create pane increases pane count and assigns valid fd/pid | 2.2, P4 |
| P7_701 | Close pane decreases count and cleans up resources | 2.3, P5 |
| P7_702 | Cannot close last pane | P1 |
| P7_703 | Grid auto-sizes correctly for 1-8 panes | 2.5, P3 |
| P7_704 | Focus adjusts after close | P2 |
| P7_705 | Zoom makes focused pane fill screen | 2.4 |
| P7_706 | Unzoom restores original layout | 2.4 |
| P7_707 | Background panes receive output during zoom | P6 |
| P7_708 | Close confirmation: 'n' cancels | 2.3 |
| P7_709 | Close confirmation: 'y' proceeds | 2.3 |
| P7_710 | Create monitor pane | 2.2 |

---

## 7. Open Questions

1. **Shell detection:** Use `env("SHELL")` or hardcode `/bin/bash`?
   - Recommendation: `env("SHELL")` with `/bin/bash` fallback. Wire
     `cfg.shell` (currently dead code) as the config override, with
     `env("SHELL")` as the runtime fallback.

2. **Grid algorithm:** The "minimize aspect ratio" heuristic may produce
   unexpected layouts. Should the user be able to override?
   - Recommendation: Auto-grid for now, manual grid override in Phase 17

3. **Pane ordering:** When a pane is closed, do remaining panes shift left
   or maintain position with an empty cell?
   - Recommendation: Shift left (re-tile). Empty cells waste space.

4. **Maximum panes:** Should there be a hard limit?
   - Recommendation: Soft limit of 12 (configurable). Beyond that, panes
     become too small to be useful.

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0 | 2026-02-18 | Initial draft |
