# Morgoth Roadmap

**Current version:** 0.1.0
**Tests:** 200/200 passing
**Last updated:** 2026-02-20

---

## Completed (v0.1.0)

All planned phases are complete. See [CHANGELOG.md](../CHANGELOG.md) for details.

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Core: layout, screen buffer, input routing, signals | Done |
| 2 | VTerm emulator, scrollback, config, monitor plugin | Done |
| 3 | DEC modes, alt screen, OSC/DCS, extended CSI, mouse SGR | Done |
| 4 | Native termios, raw mode, sigaction, launch wrapper | Done |
| 5 | Real PTY spawning (openpty/fork/exec) | Done |
| 6 | Resize propagation (SIGWINCH → vterm_resize + TIOCSWINSZ) | Done |
| 7 | Dynamic pane management (create/close/zoom, auto-grid) | Done |
| 8 | Vim-style copy mode, OSC 52 clipboard | Done |
| 9 | Named profiles, dynamic startup | Done |
| 10 | Scrollback search (incremental, smartcase, n/N) | Done |
| T2 | True color, Unicode width, status bar enrichment | Done |
| 14 | UI refinement (focused borders, pane numbering) | Done |
| 15 | UX + security (quit/close confirm, help, validate_shell) | Done |
| 16 | Performance (batch poll, drain loop, coalesced flush) | Done |
| 17 | `Sys·poll_fds` — single syscall per iteration | Done |
| 18 | Session persistence (save/restore on quit/startup) | Done |
| 19 | Named profiles + picker overlay | Done |
| 20 | Configurable keybindings via config.json | Done |
| 21 | Manual splitting (`^B+\|`, `^B+-`) | Done |
| 22 | Claude integration (monitor pane, claude-pipe.sh) | Done |
| 23 | Hardening ($SHELL, pane death notification, env vars) | Done |
| 24 | Real-world bug fixes (CSI `<`, y-leak, picker crash) | Done |

---

## Future

Items below are scoped but not scheduled. None block current usage.

### Profile Picker: Create + Delete

The picker overlay (`^B+p`) supports load/navigate/cancel but the `n` (new)
and `d` (delete) hints shown in early designs were deferred. A profile can be
created by saving the current layout with `^B+S` after typing a new name —
but there's no in-picker flow for it.

### Tree-Based Layout Engine

The current grid engine places all panes in equal-size cells. An optional
tree engine would allow arbitrary split ratios (30/70, unequal rows, etc.)
without changing the common case (equal-size grid with `recompute_grid`).

### Session Restore: `y` Prompt UX

The restore prompt reads one response byte, then drains stdin. If
`claude-pipe.sh` injects old `claude-in.txt` content within the 3-second
window, the prompt is auto-dismissed before the user can respond. Clearing
`claude-in.txt` on Morgoth startup would prevent this.

### Plugin API

Generalize the monitor pane into a plugin interface. A plugin is a Sigil
script that receives a render region and refresh tick, and can draw arbitrary
content. The monitor and a future git-status pane would both use this.

### Cross-Instance Orchestration

The original Morgoth vision: send commands or context between Claude Code
instances, with an orchestration layer for multi-agent workflows. The current
Claude integration (copy yank → `claude-in.txt` → pipe → input box) is a
manual first step. A fuller implementation would involve structured messaging
between instances.
