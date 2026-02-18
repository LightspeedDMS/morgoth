# Morgoth Specification

**Version:** 0.1.0
**Status:** Draft
**Date:** 2026-02-17
**Authors:** Lilith + Claude (Opus 4.6)

---

## 1. Conceptual Foundation

Morgoth is a TUI terminal multiplexer purpose-built for managing multiple
concurrent Claude Code instances within a single terminal window. It provides
dynamic tiling, a plugin system, and keyboard/mouse interaction.

### 1.1 Why This Exists

Claude Code power users run multiple instances simultaneously. Current options:
- **Multiple tabs**: Cannot view instances side-by-side
- **Multiple windows**: Competes with email, Slack, browsers for screen space
- **Generic multiplexers (tmux/zellij)**: Not purpose-built; no Claude-aware features

Morgoth solves this by providing a Claude-Code-aware multiplexer that understands
what it's hosting and can surface instance metadata (context usage, session cost,
etc.) alongside the instances themselves.

### 1.2 Secondary Purpose

Morgoth is a dogfooding exercise for the Sigil language. Building a real-world
TUI application will stress-test Sigil's capabilities and drive expansion of
the stdlib and ecosystem.

### 1.3 Key Abstractions

```
Terminal ← Morgoth manages the physical terminal
  └── Layout ← A tiling arrangement of panes
       └── Pane ← A rectangular region of the terminal
            └── Content ← Either a Claude Code instance or a plugin
```

---

## 2. Compiler & Stdlib Prerequisites

**Status:** ⚠️ **GAP IDENTIFIED** (reassessed on fix/dogfooding-styx-parser branch)

Audit of Sigil's stdlib on `fix/dogfooding-styx-parser` (2026-02-17) reveals
that while the new Sys module (Phase 24) provides a syscall foundation and
epoll-based I/O multiplexing, several OS-level primitives required by Morgoth
are not yet implemented. These MUST be addressed before core Morgoth development
can proceed.

### 2.1 Current Capabilities

| Capability | Status | Location |
|-----------|--------|----------|
| ANSI terminal styling | ✅ | stdlib: register_terminal (Phase 20) |
| TTY detection | ✅ | stdlib: term_is_tty |
| Shell command execution | ✅ | stdlib: shell() |
| Channel IPC | ✅ | stdlib: register_concurrency |
| Futures/async model | ⚠️ Cooperative only | stdlib: register_concurrency |
| Cursor control | ✅ | stdlib: term_cursor_up/down |
| Native syscall layer | ✅ | stdlib: register_sys (Phase 24) |
| File I/O (Sys·read/write/open/close) | ✅ | stdlib: register_sys |
| Networking (socket/connect/bind/listen) | ✅ | stdlib: register_sys |
| Memory mapping (Sys·mmap/munmap) | ✅ | stdlib: register_sys |
| I/O multiplexing (epoll) | ✅ | stdlib: Sys·epoll_create1/ctl/wait |
| Syscall constants (pipe/dup/dup2/poll) | ⚠️ Constants only | rt/sys/linux_x64.sg |

### 2.2 Required Primitives (Still Missing)

| Primitive | Purpose | Priority | Notes |
|-----------|---------|----------|-------|
| Raw terminal mode (termios) | Keystroke-level input | CRITICAL | No termios structs or tcgetattr/tcsetattr |
| PTY creation (openpty/forkpty) | Virtual terminal pairs | CRITICAL | No PTY support at all |
| PTY read/write | Relay I/O to hosted processes | CRITICAL | Depends on PTY creation |
| Window size query (TIOCGWINSZ) | Determine terminal dimensions | CRITICAL | No ioctl terminal wrappers |
| Window size set (TIOCSWINSZ) | Propagate resize to child PTYs | CRITICAL | No ioctl terminal wrappers |
| Process spawn (fork/exec) | Start Claude Code with PTY | CRITICAL | SYS constants exist, no wrappers |
| Pipe creation (pipe/dup2) | I/O redirection for child processes | CRITICAL | SYS_PIPE/DUP/DUP2 constants exist, no wrappers |
| Signal handling (SIGWINCH/SIGCHLD) | Resize detection, child exit | HIGH | No signal infrastructure |
| Mouse event capture | Parse xterm mouse protocol | MEDIUM | No mouse input support |
| Alternate screen buffer | Enter/exit smcup/rmcup | MEDIUM | Trivial escape sequences |

### 2.3 Implementation Order

Per SDD methodology — prerequisites before dependents.

The existing Sys module (register_sys, Phase 24) establishes the pattern:
syscall wrappers in stdlib.rs with interpreter-level simulation. The remaining
primitives follow this same approach. Syscall constants for pipe, dup, dup2,
and poll already exist in `parser/src/rt/sys/linux_x64.sg`.

```
Phase 0: Stdlib Extensions (extend register_sys / register_terminal)

  0.1  Alternate screen buffer (smcup/rmcup)        ← TRIVIAL (escape sequences only)
  0.2  Raw terminal mode (termios get/set)           ← BLOCKING
  0.3  Window size query/set (ioctl TIOCGWINSZ)      ← BLOCKING
  0.4  Pipe creation (Sys·pipe, Sys·dup2)            ← BLOCKING (constants exist)
  0.5  Process spawn (Sys·fork, Sys·execve)          ← BLOCKING (constants exist)
  0.6  PTY creation and I/O (openpty, read, write)   ← BLOCKING
  0.7  Signal handling (SIGWINCH, SIGCHLD)            ← HIGH
  0.8  Mouse event protocol (xterm SGR mode)          ← MEDIUM
       Epoll already available for multiplexed I/O    ← RESOLVED

Phase 1: Core Morgoth (depends on Phase 0)
Phase 2: Monitoring Plugin
Phase 3: Cross-Instance Communication
```

### 2.4 Approach

These primitives should extend the existing Sys module (register_sys, Phase 24
in stdlib.rs) and register_terminal, following the established patterns:

- **Syscall wrappers**: Follow the epoll pattern in register_sys (line ~38845)
- **FFI to POSIX**: Via the C runtime (`parser/runtime/sigil_runtime.c`)
- **Interpreter simulation**: Fake/simulated behavior for interpreter mode
  (as done with FAKE_EPOLL_STATE for epoll)
- **LLVM/native compilation**: Real syscalls when compiled to native binary

The syscall constants in `parser/src/rt/sys/linux_x64.sg` (SYS_PIPE=22,
SYS_DUP=32, SYS_DUP2=33, SYS_POLL=7) provide the foundation — they just
need wrapper functions and interpreter-side implementations.

---

## 3. Type Architecture

### 3.1 Core Types

```
Morgoth:
    terminal: Terminal!
    layout: Layout!
    panes: [Pane]!
    focused: PaneId!
    config: Config!
    running: bool!

Terminal:
    fd: FileDescriptor!
    original_termios: Termios!      // Restored on exit
    size: TermSize!
    in_alternate_screen: bool!

TermSize:
    rows: u16!
    cols: u16!

PaneId:
    raw: u16!
    invariant: raw < max_panes
```

### 3.2 Layout Types

```
Layout:
    grid: Grid!
    gaps: u16!                      // Pixel gap between panes (0 = no gap)

Grid:
    rows: u16!
    cols: u16!
    cells: [Cell]!                  // row-major, length = rows * cols
    invariant: len(cells) = rows * cols

Cell:
    pane_id: PaneId?                // None if cell is empty
    row_span: u16!                  // Default 1
    col_span: u16!                  // Default 1
```

### 3.3 Pane Types

```
Pane:
    id: PaneId!
    region: Region!                 // Where on screen this pane renders
    content: PaneContent!
    border: BorderStyle!
    title: str?
    has_focus: bool!

Region:
    row: u16!                       // Top-left row (0-indexed)
    col: u16!                       // Top-left column (0-indexed)
    height: u16!                    // Rows
    width: u16!                     // Columns

enum PaneContent {
    Instance { pty: Pty!, process: ChildProcess!, scrollback: [str]! },
    Plugin { plugin: Plugin! },
    Empty,
}

enum BorderStyle {
    None,
    Single,                         // ┌─┐│└─┘
    Double,                         // ╔═╗║╚═╝
    Rounded,                        // ╭─╮│╰─╯
    Heavy,                          // ┏━┓┃┗━┛
}
```

### 3.4 Process Types

```
Pty:
    master_fd: FileDescriptor!
    slave_fd: FileDescriptor!
    size: TermSize!

ChildProcess:
    pid: Pid!
    state: ProcessState!

enum ProcessState {
    Running,
    Exited { code: i32! },
    Signaled { signal: i32! },
}
```

### 3.5 Input Types

```
enum InputEvent {
    Key { key: KeyEvent! },
    Mouse { mouse: MouseEvent! },
    Resize { size: TermSize! },
    ChildExited { pane_id: PaneId!, code: i32! },
}

KeyEvent:
    code: KeyCode!
    modifiers: Modifiers!

enum KeyCode {
    Char { c: char! },
    Enter, Escape, Backspace, Tab,
    Up, Down, Left, Right,
    Home, End, PageUp, PageDown,
    F { n: u8! },                   // F1-F12
}

Modifiers:
    ctrl: bool!
    alt: bool!
    shift: bool!

MouseEvent:
    row: u16!
    col: u16!
    kind: MouseKind!

enum MouseKind {
    Press { button: MouseButton! },
    Release,
    Move,
    ScrollUp,
    ScrollDown,
}

enum MouseButton { Left, Right, Middle }
```

### 3.6 Configuration Types

```
Config:
    layout: LayoutConfig!
    keybindings: [Keybinding]!
    theme: Theme!
    leader_key: KeyEvent!           // Prefix key (like tmux prefix)
    plugins: [PluginConfig]!

LayoutConfig:
    rows: u16!
    cols: u16!
    default_pane_content: DefaultContent!

enum DefaultContent {
    ClaudeCode,
    Empty,
}

Keybinding:
    trigger: KeyEvent!
    action: Action!

enum Action {
    FocusPane { id: PaneId! },
    FocusNext,
    FocusPrev,
    FocusUp,
    FocusDown,
    FocusLeft,
    FocusRight,
    ResizePane { direction: Direction!, amount: i16! },
    ClosePane { id: PaneId! },
    NewPane,
    ToggleZoom { id: PaneId! },     // Fullscreen a single pane
    Quit,
    ReloadConfig,
}

Theme:
    border_focused: Color!
    border_unfocused: Color!
    title_focused: Color!
    title_unfocused: Color!
    status_bar: Color!
```

---

## 4. Behavioral Contracts

### 4.1 Startup

```
morgoth·start(config_path):
    config ← load_config(config_path)
    terminal ← Terminal·init()
        enter_raw_mode(terminal.fd)
        enter_alternate_screen(terminal.fd)
        enable_mouse_capture(terminal.fd)
        query_terminal_size(terminal.fd) → terminal.size

    layout ← Layout·from_config(config.layout)
    panes ← []

    for each cell in layout where cell.default = ClaudeCode:
        pty ← Pty·open()
        set_pty_size(pty, cell.region)
        process ← spawn_claude_code(pty)
        pane ← Pane·new(cell.id, pty, process)
        panes.push(pane)

    focused ← panes[0].id
    morgoth ← Morgoth { terminal, layout, panes, focused, config }
    morgoth.run_event_loop()
```

### 4.2 Event Loop

```
morgoth·run_event_loop():
    while self.running:
        // Poll all sources: terminal stdin + all PTY master fds
        fds ← [self.terminal.fd] + self.panes.map(p → p.pty.master_fd)
        ready ← poll(fds, timeout: 16ms)     // ~60fps max

        for fd in ready:
            if fd = self.terminal.fd:
                event ← parse_input(read(fd))
                self.handle_input(event)
            else:
                pane ← self.pane_for_fd(fd)
                output ← read(fd)
                pane.scrollback.append(output)
                self.render_pane(pane)

        // Check for child exits
        for pane in self.panes where pane.content is Instance:
            if pane.process.state is not Running:
                self.handle_child_exit(pane)
```

### 4.3 Input Routing

```
morgoth·handle_input(event):
    match event:
        InputEvent·Key { key }:
            if self.awaiting_leader_chord:
                self.dispatch_chord(key)
                self.awaiting_leader_chord ← false
            elif key = self.config.leader_key:
                self.awaiting_leader_chord ← true
            else:
                // Pass through to focused pane
                write(self.focused_pane().pty.master_fd, key.to_bytes())

        InputEvent·Mouse { mouse }:
            target ← self.pane_at(mouse.row, mouse.col)
            if target ≠ self.focused:
                self.set_focus(target)
            // Translate coordinates to pane-local and forward
            local ← translate_coords(mouse, target.region)
            write(target.pty.master_fd, local.to_escape_sequence())

        InputEvent·Resize { size }:
            self.terminal.size ← size
            self.recalculate_layout()
            for pane in self.panes:
                set_pty_size(pane.pty, pane.region)
                // SIGWINCH propagated automatically via PTY
```

### 4.4 Layout Calculation

```
morgoth·recalculate_layout():
    available_rows ← self.terminal.size.rows - status_bar_height
    available_cols ← self.terminal.size.cols
    row_height ← available_rows / self.layout.grid.rows
    col_width ← available_cols / self.layout.grid.cols
    remainder_rows ← available_rows % self.layout.grid.rows
    remainder_cols ← available_cols % self.layout.grid.cols

    for each cell in self.layout.grid.cells:
        // Distribute remainder pixels to last row/col
        cell.pane.region ← Region {
            row: cell.grid_row * row_height,
            col: cell.grid_col * col_width,
            height: row_height + (1 if cell.grid_row = last_row and remainder_rows > 0),
            width: col_width + (1 if cell.grid_col = last_col and remainder_cols > 0),
        }
```

### 4.5 Rendering

```
morgoth·render():
    buffer ← ScreenBuffer·new(self.terminal.size)

    for pane in self.panes:
        // Draw border
        draw_border(buffer, pane.region, pane.border,
                    focused: pane.id = self.focused)

        // Draw title
        if pane.title is not None:
            draw_title(buffer, pane.region, pane.title,
                       focused: pane.id = self.focused)

        // Draw content (inner region, inside border)
        inner ← pane.region.shrink(1)    // 1-cell border inset
        match pane.content:
            Instance { scrollback, .. }:
                render_scrollback(buffer, inner, scrollback)
            Plugin { plugin }:
                plugin.render(buffer, inner)
            Empty:
                fill(buffer, inner, ' ')

    // Draw status bar
    self.render_status_bar(buffer)

    // Flush diff to terminal
    buffer.flush_diff(self.terminal.fd)
```

---

## 5. Constraints & Invariants

```
P1: ∀ t:
    self.running ⟹ terminal is in raw mode ∧ alternate screen active
    // Terminal state is consistent while Morgoth runs

P2: ∀ pane ∈ self.panes:
    pane.region is within terminal bounds
    // No pane renders outside the terminal

P3: ∀ pane ∈ self.panes where pane.content is Instance:
    pane.pty.size = pane.inner_region.size
    // PTY dimensions match the pane's content area

P4: exactly_one(pane ∈ self.panes where pane.has_focus)
    // Exactly one pane has focus at all times

P5: terminal.original_termios is preserved from init to shutdown
    // Original terminal state is always restorable

P6: ∀ child_process spawned by Morgoth:
    child is reaped on exit (no zombies)
    // All child processes are cleaned up
```

---

## 6. Error Conditions

| Condition | Detection | Response |
|-----------|-----------|----------|
| Terminal too small for layout | On resize / startup | Display error, refuse to render |
| Claude Code process exits | SIGCHLD / poll | Show exit code in pane, offer restart |
| Claude Code process crashes | SIGCHLD / poll | Show error, offer restart |
| PTY allocation fails | openpty returns error | Display error, mark pane as failed |
| Config file malformed | On load / reload | Show parse error, use defaults |
| Terminal loses connection | Read returns 0 / error | Graceful shutdown, clean up children |

---

## 7. Plugin Architecture

### 7.1 Plugin Contract

```
trait Plugin {
    /// Called once when plugin is loaded
    fn init(config: PluginConfig) → Result<Self, Error>

    /// Called each frame to render into the assigned region
    fn render(buffer: ScreenBuffer, region: Region)

    /// Called when plugin receives an event (keyboard/mouse when focused)
    fn handle_event(event: InputEvent) → EventResult

    /// Called on terminal resize
    fn on_resize(new_region: Region)

    /// Called on shutdown
    fn cleanup()
}

enum EventResult {
    Consumed,       // Plugin handled the event
    Ignored,        // Pass to Morgoth for default handling
}
```

### 7.2 System Monitor Plugin (Built-in)

The system monitor displays metadata about active Claude Code instances.

```
SystemMonitor : Plugin {
    instances: [InstanceMetrics]~

    fn render(buffer, region):
        for each instance in self.instances:
            render_instance_card(buffer, instance):
                - Pane label / instance identifier
                - Context window usage (estimated)
                - Session token count
                - Session cost (estimated)
                - Process uptime
                - Current working directory
                - Last activity timestamp
}

InstanceMetrics:
    pane_id: PaneId!
    context_usage_pct: f32~         // Estimated from output patterns
    session_tokens: u64~            // Estimated
    session_cost_usd: f32~          // Estimated
    uptime: Duration!
    working_dir: str~
    last_activity: Timestamp!
```

**Open Question:** How to obtain Claude Code metrics. Options:
- Parse Claude Code's status output (fragile)
- Use Claude Code's MCP or API if available
- Monitor PTY output for status line patterns

---

## 8. Integration Points

### 8.1 Claude Code

Morgoth spawns Claude Code as a child process attached to a PTY:

```
spawn_claude_code(pty):
    exec_in_pty(pty, "claude", [])
    // Claude Code runs as if in a normal terminal
    // All I/O passes through the PTY
```

Morgoth does NOT modify Claude Code's behavior. It is a transparent host.

### 8.2 Terminal Emulator

Morgoth reads from and writes to the parent terminal via stdin/stdout.
It must correctly handle:
- All escape sequences Claude Code produces
- 256-color and truecolor output
- Unicode (including wide characters)
- Bracketed paste mode passthrough

### 8.3 Configuration File

```
// morgoth.config (format TBD — likely Sigil or TOML)

layout: {
    rows: 2,
    cols: 3,
    panes: [
        { row: 0, col: 0, content: "claude" },
        { row: 0, col: 1, content: "plugin:system-monitor" },
        { row: 0, col: 2, content: "claude" },
        { row: 1, col: 0, content: "claude" },
        { row: 1, col: 1, content: "claude" },
        { row: 1, col: 2, content: "claude" },
    ]
}

leader_key: "Ctrl+b"

keybindings: {
    "h": "focus-left",
    "l": "focus-right",
    "k": "focus-up",
    "j": "focus-down",
    "c": "new-pane",
    "x": "close-pane",
    "z": "toggle-zoom",
    "q": "quit",
}

theme: {
    border_focused: "cyan",
    border_unfocused: "gray",
}
```

---

## 9. Shutdown Protocol

```
morgoth·shutdown():
    // 1. Signal all child processes
    for pane in self.panes where pane.content is Instance:
        send_signal(pane.process.pid, SIGTERM)

    // 2. Wait briefly for graceful exit
    wait_with_timeout(all_children, timeout: 3s)

    // 3. Force-kill any remaining
    for pane in self.panes where pane.process.state is Running:
        send_signal(pane.process.pid, SIGKILL)
        waitpid(pane.process.pid)

    // 4. Close all PTYs
    for pane in self.panes where pane.content is Instance:
        close(pane.pty.master_fd)
        close(pane.pty.slave_fd)

    // 5. Restore terminal
    disable_mouse_capture(self.terminal.fd)
    leave_alternate_screen(self.terminal.fd)
    restore_termios(self.terminal.fd, self.terminal.original_termios)
```

Invariant: Terminal MUST be restored regardless of exit path (normal, error, signal).

---

## 10. Open Questions

1. **Project name**: Morgoth is a working title. Final name TBD.

2. **Config format**: Sigil's own syntax? TOML? JSON? Sigil would be
   on-brand but needs a config parser.

3. **Metrics acquisition**: How do we read Claude Code's context/token usage?
   No documented API for this. May need to parse status bar output or request
   this feature upstream.

4. **Session persistence**: Should Morgoth support detach/reattach like tmux?
   If so, this requires a daemon mode with socket-based communication.
   Deferred — not in initial scope.

5. **Scrollback management**: How much scrollback per pane? Memory-mapped?
   Ring buffer? Configurable limit?

6. **Terminal emulation fidelity**: Full VT100/xterm emulation is extremely
   complex. How much do we need to interpret vs. pass through? Since we're
   hosting Claude Code (which handles its own rendering), passthrough may
   suffice — but we still need to track cursor position for rendering pane
   borders correctly.

7. **Plugin discovery**: How are plugins loaded? Compiled into the binary?
   Dynamic loading? Script-based?

8. **Cross-instance communication (Phase 3)**: What form does this take?
   Shared clipboard? Message passing? Ability to pipe output from one
   instance to another?

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0 | 2026-02-17 | Initial draft. Documented stdlib gaps as Phase 0 prerequisites. |
| 0.1.1 | 2026-02-17 | Reassessed on fix/dogfooding-styx-parser branch. Epoll resolved (Sys module Phase 24). Updated Phase 0 ordering. Syscall constants for pipe/dup/dup2/poll confirmed present. |
