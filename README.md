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

**Phase 1 complete** -- core TUI multiplexer is functional.

| Component | Status |
|-----------|--------|
| Layout engine (grid-based tiling) | Done |
| Screen buffer (diff-based rendering) | Done |
| PTY management (open, spawn, relay) | Done |
| Input routing (leader key, mouse) | Done |
| Signal handling + graceful shutdown | Done |
| System monitor plugin | Phase 2 |
| Cross-instance communication | Phase 3 |
| Configuration files | Phase 2 |
| Scrollback buffer | Phase 2 |

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

Morgoth is a single-file Sigil application (`src/morgoth.sg`) organized into
sections:

| Section | Purpose |
|---------|---------|
| Constants | Version, leader key, escape sequences, box-drawing chars |
| Data Structures | Cell, Region, Pane (with PTY + child process) |
| Layout Engine | Grid calculation with remainder distribution |
| Screen Buffer | Flat cell array with dirty tracking |
| Rendering | Borders, content, status bar, diff flush |
| Input Handling | Leader key state machine, mouse hit-testing |
| Terminal Control | Alt screen, raw mode, mouse tracking |
| Shutdown | SIGTERM -> wait -> SIGKILL -> restore terminal |
| Event Loop | Synchronous poll loop (~60fps) |

### Event Loop

```
while running:
    check signals (SIGTERM, SIGINT, SIGWINCH)
    if poll_fd(stdin, 0):
        read input -> process through state machine
        passthrough to focused pane or handle leader command
    for each pane:
        if poll_fd(pane.master_fd, 0):
            read PTY output -> render into pane region
    flush dirty cells to terminal
```

### Key Bindings

| Key | Action |
|-----|--------|
| `Ctrl-B` | Activate leader mode |
| `Ctrl-B` then `n` | Focus next pane |
| `Ctrl-B` then `p` | Focus previous pane |
| `Ctrl-B` then `q` | Quit |
| Mouse click | Focus clicked pane |

## Tests

```bash
cd ../sigil-lang/jormungandr/tests

# Run Morgoth behavioral tests (21 tests)
./run_tests_rust.sh --spec 23_morgoth

# Run interpreter primitive tests (34 tests including Phase 1.0)
./run_tests_rust.sh --spec 22_native_runtime

# Run full suite (795 passing)
./run_tests_rust.sh
```

## Roadmap

### Phase 2 -- Monitoring & Config
- System monitor plugin (context window, tokens, session cost)
- User-configurable layouts (config file)
- Scrollback buffer
- Terminal emulation (parse SGR, cursor, clear sequences)

### Phase 3 -- Cross-Instance Communication
- Send commands/context between Claude Code instances
- Plugin system for custom tile types
- Orchestration capabilities

## Language

Morgoth is written in Sigil as a dogfooding exercise. It stress-tests Sigil's
capabilities for systems-level TUI work and has driven expansion of the stdlib
with 14 new primitives across Phase 0 and Phase 1.

## License

Proprietary -- Daemoniorum LLC
