# Morgoth

A TUI terminal multiplexer for managing multiple concurrent Claude Code
instances, written in [Sigil](https://github.com/Daemoniorum-LLC/sigil-lang).

```
┌──Claude Code──────┬──System Monitor──┬──Claude Code──────┐
│                    │                  │                    │
│  Instance 1        │  Context: 42%    │  Instance 3        │
│                    │  Tokens: 12.4k   │                    │
│  > implementing    │  Session: $0.34  │  > reviewing PR    │
│    auth module...  │                  │    #127...         │
├──Claude Code──────┼──Claude Code─────┼──Claude Code──────┤
│                    │                  │                    │
│  Instance 4        │  Instance 5      │  Instance 6        │
│                    │                  │                    │
│  > running tests   │  > idle          │  > refactoring     │
│                    │                  │    database...     │
└───────────────────┴──────────────────┴───────────────────┘
 Morgoth v0.1.0 | Ctrl-B: leader | q: quit | n/p: focus
```

## Why

Claude Code power users run multiple instances simultaneously. Current options
fall short:

- **Multiple tabs** -- can't view instances side-by-side
- **Multiple windows** -- competes with other apps for screen real estate
- **Generic multiplexers** (tmux, zellij) -- not Claude-aware; no metadata surfacing

Morgoth is purpose-built: a Claude-Code-aware multiplexer that understands what
it's hosting and can surface instance metadata (context window usage, session
cost, token consumption) alongside the instances themselves.

## Status

**Phase 8 complete** -- daily-driver capable terminal multiplexer.

| Component | Status | Phase |
|-----------|--------|-------|
| Layout engine (grid-based tiling) | Done | 1 |
| Screen buffer (diff-based rendering) | Done | 1 |
| PTY management (open, spawn, relay) | Done | 1 |
| Input routing (leader key, mouse) | Done | 1 |
| Signal handling + graceful shutdown | Done | 1 |
| VTerm terminal emulator (ANSI state machine) | Done | 2 |
| System monitor plugin | Done | 2 |
| JSON configuration (~/.morgoth/config.json) | Done | 2 |
| Scrollback buffer with eviction | Done | 2 |
| DEC private modes + alternate screen | Done | 3 |
| OSC/DCS sequence handling + titles | Done | 3 |
| Extended CSI sequences (IL/DL/@/P/X/E/F) | Done | 3 |
| Input escape forwarding (arrow keys, mouse SGR) | Done | 3 |
| Native termios + raw mode | Done | 4 |
| Real signal handling (sigaction) | Done | 4 |
| Real PTY spawning (openpty/fork/exec) | Done | 5 |
| Terminal resize propagation (SIGWINCH) | Done | 6 |
| Dynamic pane management (create/close/zoom) | Done | 7 |
| Vim-style copy/paste with OSC 52 clipboard | Done | 8 |
| Cross-instance communication | Future |

## Requirements

- [Sigil](https://github.com/Daemoniorum-LLC/sigil-lang) compiler (Rust
  backend, `native` feature)
- Linux (PTY and signal primitives are Linux-specific)

## Build & Run

```bash
# Build the Sigil compiler (if not already built)
cd ../sigil-lang/parser
cargo build --release --no-default-features --features jit,native,protocols

# Run Morgoth
./target/release/sigil run ../../morgoth/src/morgoth.sg
```

## Architecture

Morgoth is a single-file Sigil application (`src/morgoth.sg`, ~2400 lines)
organized into sections:

| Section | Purpose |
|---------|---------|
| Constants | Version, leader key, escape sequences, box-drawing chars |
| Data Structures | Cell, Region, Pane (with PTY + VTerm + child process) |
| Layout Engine | Grid calculation with aspect-ratio-optimized tiling |
| Screen Buffer | Flat cell array with dirty tracking |
| VTerm Emulator | ANSI state machine (normal/escape/CSI/OSC/DCS modes) |
| Copy Mode | Text extraction, selection, cursor movement, clipboard |
| Rendering | Borders, content, status bar, copy overlay, diff flush |
| Input Handling | Leader key, copy mode intercept, close confirmation |
| Config | JSON config loader (~/.morgoth/config.json) with defaults |
| Monitor Plugin | System stats from ~/.claude/stats-cache.json |
| Terminal Control | Alt screen, raw mode, mouse tracking, termios |
| Signal Handling | SIGTERM, SIGINT, SIGWINCH via sigaction |
| Pane Management | Create, close, zoom, relayout |
| Shutdown | SIGTERM -> wait -> SIGKILL -> restore terminal |
| Event Loop | Synchronous poll loop with freeze guard |

### Event Loop

```
while running:
    check signals (SIGTERM, SIGINT, SIGWINCH)
    if SIGWINCH: resize all panes + propagate to PTYs
    if poll_fd(stdin, 0):
        read input -> process through state machine
        copy mode intercept -> leader key -> passthrough to PTY
    for each pane (respecting zoom + copy freeze guards):
        if terminal pane && poll_fd(pane.master_fd, 0):
            read PTY output -> vterm_feed -> render into region
        if monitor pane && refresh interval elapsed:
            read stats -> render monitor
    flush dirty cells to terminal
    sleep(poll_interval)
```

### Key Bindings

**Leader key:** `Ctrl-B`

| Key | Action |
|-----|--------|
| `Ctrl-B` | Activate leader mode |
| `Ctrl-B` `n` | Focus next pane |
| `Ctrl-B` `p` | Focus previous pane |
| `Ctrl-B` `c` | Create new terminal pane |
| `Ctrl-B` `m` | Create new monitor pane |
| `Ctrl-B` `x` | Close focused pane (with confirmation) |
| `Ctrl-B` `z` | Toggle zoom on focused pane |
| `Ctrl-B` `k` | Scroll up (scrollback) |
| `Ctrl-B` `j` | Scroll down (scrollback) |
| `Ctrl-B` `[` | Enter copy mode |
| `Ctrl-B` `q` | Quit |
| Mouse click | Focus clicked pane |

**Copy mode** (vim-style):

| Key | Action |
|-----|--------|
| `h` `j` `k` `l` | Cursor movement |
| `0` / `$` | Beginning / end of line |
| `w` / `b` | Word forward / backward |
| `g` / `G` | First / last line |
| `Ctrl-U` / `Ctrl-D` | Half-page up / down |
| `Space` | Start/cancel character selection |
| `V` | Toggle line selection mode |
| `Enter` | Yank selection to clipboard (OSC 52) |
| `q` / `ESC` | Exit copy mode |

## Tests

```bash
# Run all tests (110 tests)
./run_tests.sh

# Run a specific phase
./run_tests.sh --filter P8
```

## Roadmap

### Phase 9 -- Cross-Instance Communication
- Send commands/context between Claude Code instances
- Plugin system for custom tile types
- Orchestration capabilities

## Language

Morgoth is written in Sigil as a dogfooding exercise. It stress-tests Sigil's
capabilities for systems-level TUI work and has driven expansion of the stdlib
with native primitives for PTY management, terminal control, signal handling,
and process spawning across Phases 0--5.

## License

Proprietary -- Daemoniorum LLC
