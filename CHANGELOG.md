# Changelog

All notable changes are documented here. Morgoth uses a phase-based development
model; each phase corresponds to a cohesive slice of functionality.

---

## v0.1.0 — 2026-02-20

First public release. 200/200 tests passing.

### Phase 1 — Core Foundation (2026-02-18)
- Layout engine with grid-based tiling
- Screen buffer with dirty-cell diff rendering
- PTY management (fake, replaced in Phase 5)
- Input routing with leader-key state machine
- Signal handling and graceful shutdown
- `Sys·read_string`, `Sys·poll_fd`, `Sys·spawn_bg`, `Sys·spawn_pty`,
  `Sys·kill`, `Sys·waitpid` added to Sigil stdlib

### Phase 2 — VTerm + Config (2026-02-18)
- VTerm terminal emulator: ANSI state machine (normal/escape/CSI modes)
- SGR color attributes, CUP/ED/EL cursor commands
- Scrollback buffer with configurable eviction cap
- JSON configuration (`~/.morgoth/config.json`)
- System monitor plugin reading `~/.claude/stats-cache.json`
- Dynamic terminal size via `TIOCGWINSZ` + `SIGWINCH`
- Adaptive sleep replacing busy-wait

### Phase 3 — Production Sequences (2026-02-18)
- DEC private modes + alternate screen (`?1049h`/`l`)
- OSC/DCS sequence handling; pane titles via OSC 2
- Extended CSI sequences: IL, DL, `@`, P, X, E, F; SGR inverse/defaults
- Input escape forwarding: arrow keys, mouse SGR to focused pane
- Integration test validating `⎇/⎉` chain in VTerm

### Phase 4 — Native Terminal Integration (2026-02-18)
- Real `tcgetattr`/`cfmakeraw`/`tcsetattr` via libc (native feature)
- Real `sigaction` for SIGTERM/SIGINT/SIGWINCH
- `terminal_init()` saves and restores termios on shutdown
- HMR (hot module reload) gated by `cfg.hmr` flag
- `launch.sh` safe wrapper with `stty` save/restore trap

### Phase 5 — Real PTY Spawning (2026-02-18)
- `libc::openpty` + `O_NONBLOCK` on master fd
- `fork`/`setsid`/`TIOCSCTTY`/`dup2`/`execvp` for child shells
- Native `libc::read`/`libc::write`/`libc::close` for real fds
- `TIOCSWINSZ` propagation via `Pty·set_size`
- Fd boundary: real OS fds `< 4000`; fake counters start at `4000+`

### Phase 6 — Resize Propagation (2026-02-18)
- `vterm_resize(vt, new_rows, new_cols)`: in-place grid resize preserving scrollback
- SIGWINCH handler uses `vterm_resize` (was incorrectly creating a new VTerm)
- Pane inner dimensions (`h-2`, `w-2`) passed to `Pty·set_size`, not outer

### Phase 7 — Dynamic Pane Management (2026-02-18)
- Create terminal and monitor panes at runtime (`^B+c`, `^B+m`)
- Close pane with confirmation (`^B+x`)
- Zoom/unzoom focused pane (`^B+z`)
- `recompute_grid`: auto-fits N panes minimizing aspect-ratio distortion
- `relayout_panes`: extracted DRY relayout used by SIGWINCH/create/close
- Configurable `max_panes` (default 12)

### Phase 8 — Copy/Paste Mode (2026-02-19)
- Vim-style copy mode (`^B+[`)
- `h`/`j`/`k`/`l`, `0`/`$`, `w`/`b`, `g`/`G`, `Ctrl-U`/`Ctrl-D` navigation
- Character and line selection (`Space`, `V`)
- Yank to OSC 52 clipboard (`Enter`) and `~/.morgoth/claude-in.txt`
- Freeze render guard prevents screen corruption during copy mode

### Phase 9 — Dynamic Profiles (2026-02-19)
- Load pane layout from `~/.morgoth/profiles/default.json` at startup
- Save current layout with `^B+S`
- Fallback to single terminal pane when no profile exists

### Phase 10 — Scrollback Search (2026-02-19)
- Enter search with `/` (from copy mode) or `^B+/` (from normal mode)
- Incremental search: cursor jumps to nearest match on each keystroke
- Smartcase: lowercase = case-insensitive; any uppercase = case-sensitive
- `Ctrl-N`/`Ctrl-P` navigate during input; `n`/`N` navigate after accept
- Match highlight: current = yellow, others = cyan

### Tier 2 — Polish (2026-02-19)
- **True color**: packed-int SGR `38;2;R;G;B` encoding, stored per-cell
- **Unicode width**: fullwidth characters occupy 2 cells; `flush_dirty` skips
  placeholder cells; `render_border` uses display width
- **Status bar**: dynamic mode pill, pane info, context-sensitive hints

### Phase 14 — UI Refinement (2026-02-19)
- Double-line borders for focused pane; single-line for unfocused
- Pane numbering in title bars (`N:title` / `[N:title]`)
- Styled status bar: mode pill (NORMAL/COPY/SEARCH/CONFIRM) + right-aligned version

### Phase 15 — UX + Security (2026-02-20)
- Quit confirmation (`^B+q` → `y/n` prompt)
- Help overlay (`^B+?`)
- Direct pane focus (`^B+1` through `^B+9`)
- `^B+^B` passthrough of literal leader key to focused pane
- Configurable leader key in `config.json`
- Security: `validate_shell`, `sanitize_title`, buffer caps, `max_panes` clamp
- Mouse click focuses pane at click coordinates; SGR mouse forwarded to child

### Phase 16 — Performance (2026-02-20)
- Adaptive sleep: `Sys·poll_fd(0, POLL_INTERVAL_MS)` only when idle
- PTY drain loop: 16 KB chunks, 64 KB per-pane frame budget
- Coalesced `flush_dirty`: one call per iteration, not per pane
- Smart `Grid·set`: compares `ch`/`fg`/`bg` before marking dirty (zero dirty
  cells in steady state)
- `concat_all` in `flush_dirty`: O(n) output instead of O(n²)

### Phase 17 — Batch Poll (2026-02-20)
- `Sys·poll_fds(fds_array, timeout_ms)` in Sigil stdlib
- Event loop: one `libc::poll` syscall per iteration (was N+2 per pane)
- `had_activity_prev` flag drives adaptive timeout in `poll_fds`

### Phase 18 — Session Persistence (2026-02-20)
- `save_session` writes `~/.morgoth/session.json` on confirmed quit
- `load_session` + 3-second restore prompt on startup
- `vterm_restore_scrollback` repopulates scrollback buffer

### Phase 19 — Named Profiles (2026-02-20)
- `list_profiles` enumerates `~/.morgoth/profiles/*.json`
- Profile picker overlay (`^B+p`): `j`/`k` navigate, `Enter` loads, `ESC` cancels
- `^B+S` saves to active profile (not always `default`)

### Phase 20 — Configurable Keybindings (2026-02-20)
- `load_bindings` parses `bindings` section of `config.json`
- All leader actions configurable: `new_terminal`, `close_pane`, `zoom_toggle`,
  `copy_mode`, `save_profile`, `help`, etc.

### Phase 21 — Manual Splitting (2026-02-20)
- `^B+|`: add pane, force grid to same rows + 1 col
- `^B+-`: add pane, force grid to + 1 row
- `forced_rows`/`forced_cols` state; resets on SIGWINCH if layout no longer fits

### Phase 22 — Claude Code Integration (2026-02-20)
- Monitor pane shows git branch (`git rev-parse --abbrev-ref HEAD`)
- Monitor shows active task from `~/.claude/current-task` when present
- Copy-mode yank (`Enter`) writes to `~/.morgoth/claude-in.txt`
- `bin/claude-pipe.sh`: watches `claude-in.txt`, injects content into focused
  Claude Code pane via `tmux send-keys` using inherited `$TMUX_PANE`
- `launch.sh` starts `claude-pipe.sh` in background when `$TMUX` is set
- `MORGOTH=1` env var set for all child shells

### Phase 23 — Hardening (2026-02-20)
- `$SHELL` env var used as default shell (overrides config default)
- Pane death notification: title becomes `[exited N]`, border dims to fg 8
- `TERM=xterm-256color` and `COLORTERM=truecolor` exported for child shells

### Phase 24 — Real-World Bug Fixes (2026-02-20)
- CSI `<` prefix (SGR mouse from child processes) silently ignored instead
  of crashing with `cannot parse '<' as integer`
- Session restore prompt drains stdin before main loop to prevent response
  keys from leaking to the focused bash pane
- Profile picker `fg` variable declared `mut` (was immutable, caused crash)
- Session restore poll changed from non-blocking (0ms) to 3-second timeout
- Monitor refresh tick resets status bar to clear transient yank messages
