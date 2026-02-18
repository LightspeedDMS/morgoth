# Morgoth (Working Title) — Design Notes

## Vision

A custom TUI application written in Sigil that serves as a terminal multiplexer
purpose-built for managing multiple concurrent Claude Code instances. Tiled
within a single terminal window, with full keyboard and mouse support.

Secondary goal: dogfood Sigil in a real-world application and expand the
ecosystem.

## Core Concepts

### Dynamic Tiling

- Layout is user-configurable, not hardcoded
- Tiles arranged in a grid system (rows x columns)
- Each tile hosts a Claude Code instance or a plugin (e.g. system monitor)
- Users define their preferred layout via configuration

**Lilith's reference layout (2x3):**

```
+-------------------+-------------------+-------------------+
|                   |                   |                   |
|     1a: Claude    |     1b: System    |     1c: Claude    |
|     Instance      |     Monitor       |     Instance      |
|                   |                   |                   |
+-------------------+-------------------+-------------------+
|                   |                   |                   |
|     2a: Claude    |     2b: Claude    |     2c: Claude    |
|     Instance      |     Instance      |     Instance      |
|                   |                   |                   |
+-------------------+-------------------+-------------------+
```

- Tile 1b is a system monitor plugin tracking:
  - Per-instance context window usage
  - Current session token consumption
  - Other instance metadata (TBD)

### Interaction Model

- **Keyboard-driven**: Primary interaction mode, hotkeys for navigation/tiling
- **Mouse support**: Click to focus tiles, drag to resize (flexibility for
  preference)
- Focus switching between tiles via both input methods

### Plugin System (Implied)

- At minimum, tiles can host either a Claude Code instance or a plugin
- System monitor is the first plugin
- Architecture should accommodate future plugin types

## Roadmap

### Phase 1 — Core
- Terminal multiplexing with PTY management
- Dynamic tiling layout engine
- Keyboard and mouse input handling
- Claude Code process lifecycle management
- User-configurable layouts

### Phase 2 — Monitoring
- System monitor plugin
- Per-instance context tracking
- Session usage metrics

### Phase 3 — Cross-Instance Communication
- Send commands/context between Claude Code instances
- Orchestration capabilities (deferred — details TBD)

## Technical Considerations

### Language: Sigil
- Dogfooding opportunity for the language
- Expands Sigil's ecosystem with a real-world application
- Will stress-test Sigil's capabilities for TUI/systems work

### Key Technical Challenges
- PTY (pseudo-terminal) allocation and management
- Terminal escape sequence passthrough to hosted processes
- Input multiplexing (routing keystrokes to correct instance)
- Terminal resize handling and propagation
- Efficient screen rendering with multiple active panes

## Distribution

- Intended for public use — not just a personal tool
- Packaging/distribution strategy TBD
