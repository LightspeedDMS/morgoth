# Morgoth Roadmap

**Version:** 1.0.0
**Status:** Draft
**Date:** 2026-02-18
**Authors:** Lilith + Claude (Opus 4.6)

---

## Current State

Morgoth is a functional terminal multiplexer written in Sigil. As of Phase 5:

- Real PTY spawning via openpty/fork/exec
- VTerm terminal emulator (ANSI state machine, DEC modes, alt screen)
- Scrollback buffer with leader-key scrolling
- JSON-configurable 2D grid layout
- Monitor panes reading Claude Code stats
- Keyboard input routing with leader key + mouse support
- Signal handling, termios management, clean shutdown
- 79/79 Morgoth tests passing, E2E validated in tmux

It works. You can run real shells in panes, type commands, see output, switch
focus, and quit cleanly. What it lacks is the interactive ergonomics to replace
tmux for daily use.

---

## Tier 1 — Daily-Driver Blockers

These are the features required before Morgoth can replace tmux for a power
user's daily workflow. Each is a hard blocker.

### Phase 6: Resize Propagation

**Goal:** When the host terminal resizes, Morgoth relayouts all panes and
propagates the new dimensions to child shells via TIOCSWINSZ + SIGWINCH.

**Why it blocks:** Without this, resizing the terminal window corrupts the
display and child shells don't reflow their output. Unusable in practice.

**Spec:** [PHASE6-RESIZE-PROPAGATION.md](specs/PHASE6-RESIZE-PROPAGATION.md)

### Phase 7: Dynamic Pane Management

**Goal:** Create, close, and split panes at runtime via leader-key commands,
without restarting Morgoth.

**Why it blocks:** Static layouts from config are fine for testing but useless
for real work where you need to open and close shells as tasks change.

**Spec:** [PHASE7-DYNAMIC-PANES.md](specs/PHASE7-DYNAMIC-PANES.md)

### Phase 8: Copy/Paste Mode

**Goal:** Visual selection mode (like tmux copy-mode) with system clipboard
integration.

**Why it blocks:** Cannot copy text from pane output. Fundamental terminal
multiplexer capability.

**Spec:** [PHASE8-COPY-PASTE.md](specs/PHASE8-COPY-PASTE.md)

### Phase 9: Scrollback Search

**Goal:** Search through scrollback buffer with incremental highlighting.

**Why it blocks:** Long command output scrolls off screen. Without search,
you can't find things. The scrollback buffer already exists (Phase 2) but
has no search interface.

**Spec:** [PHASE9-SCROLLBACK-SEARCH.md](specs/PHASE9-SCROLLBACK-SEARCH.md)

---

## Tier 2 — Polish

Features that improve the experience but aren't hard blockers. Morgoth is
usable without these but noticeably worse.

### Phase 10: Pane Titles from OSC

Terminal applications emit OSC sequences to set window titles (current
directory, running command). Morgoth should capture these and display them
in pane title bars instead of the static "bash" label.

### Phase 11: 24-Bit True Color

VTerm currently handles SGR 256-color (`;5;N`) but not true color
(`;2;R;G;B`). Modern terminal applications (bat, delta, neovim) use
true color extensively.

### Phase 12: Unicode Width Handling

CJK characters, emoji, and other wide characters occupy two cells but
VTerm currently assumes single-cell width. Causes rendering misalignment
when wide characters appear in output.

### Phase 13: Status Bar Enrichment

Show useful context in the status bar: clock, focused pane index, git
branch of focused pane's cwd, system load. Configurable via JSON config.

---

## Tier 3 — Ambitious

Features that transform Morgoth from "tmux clone written in Sigil" into
something with its own identity.

### Phase 14: Session Persistence

Save and restore pane layouts, working directories, and running commands.
`morgoth save` / `morgoth attach` workflow like tmux sessions but with
richer state.

### Phase 15: Plugin System

Generalize the monitor pane into a plugin architecture. Plugins are Sigil
scripts that receive a render region and can draw content. Initial plugin
set: monitor, git status, log tail, process tree.

### Phase 16: Runtime Splits

Split panes horizontally or vertically at runtime (not just grid-based
layout). Requires a tree-based layout engine replacing the current flat
grid.

### Phase 17: Configurable Keybindings

User-configurable leader key and action bindings via config file. The
current hardcoded Ctrl-B + n/p/q/k/j should become defaults overridable
in `~/.morgoth/config.json`.

### Phase 18: Cross-Instance Communication

Send commands or context between Claude Code instances. Orchestration
layer for multi-agent workflows — the original vision from DESIGN-NOTES.md.

---

## Dependency Graph

```
Phase 6 (Resize) ──────────────────────────────────────┐
                                                        │
Phase 7 (Dynamic Panes) ──→ Phase 16 (Runtime Splits)  │
                                                        ├──→ Phase 14 (Sessions)
Phase 8 (Copy/Paste)                                    │
                                                        │
Phase 9 (Scrollback Search) ───────────────────────────┘

Phase 10 (OSC Titles) ── standalone
Phase 11 (True Color) ── standalone
Phase 12 (Unicode Width) ── standalone
Phase 13 (Status Bar) ── standalone

Phase 15 (Plugins) ──→ Phase 18 (Cross-Instance)
Phase 17 (Keybindings) ── standalone
```

Phases 6-9 are independent of each other and can be implemented in any order
or in parallel. Tier 2 phases are all standalone. Tier 3 has the dependency
chain shown above.

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-02-18 | Initial roadmap after Phase 5 E2E validation |
