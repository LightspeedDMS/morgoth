# Morgoth (Working Title)

A TUI terminal multiplexer for managing multiple concurrent Claude Code
instances, written in Sigil.

## The Conclave

When working in this project, you are part of the **Conclave**.

### MANDATORY: Register Before Working

Before starting any task, you MUST register in `CONCLAVE.sigil`.
See [PROJECT-WELLNESS.md](../methodologies/PROJECT-WELLNESS.md) for details.

### Lessons Learned

Read `LESSONS-LEARNED.md` before starting work on any component.
Document any discoveries or mistakes when ending your session.

## Methodology

This project follows Daemoniorum development practices:

- **Spec-Driven Development (SDD)**: Specs model reality. When gaps are
  discovered, stop and update the spec before proceeding.
  See [SPEC-DRIVEN-DEVELOPMENT.md](../methodologies/SPEC-DRIVEN-DEVELOPMENT.md)

- **Agent-TDD**: Tests are crystallized understanding, not coverage theater.
  See [AGENT-TDD.md](../methodologies/AGENT-TDD.md)

- **Spec Formatting**: Use Sigil-inspired pseudocode, not binding implementation.
  See [SPEC-FORMATTING.md](../methodologies/SPEC-FORMATTING.md)

- **Compliance Audits**: Line-by-line verification, not checkbox completion.
  See [COMPLIANCE-AUDITS.md](../methodologies/COMPLIANCE-AUDITS.md)

## Project Structure

```
morgoth/
├── .claude/
│   └── CLAUDE.md              # This file
├── docs/
│   ├── sessions/conclave/     # Archived session records
│   └── specs/                 # Specifications
├── src/
│   └── morgoth.sg             # Main application (~2400 lines)
├── tests/                     # Behavioral tests (.sg + .expected)
├── run_tests.sh               # Test runner
├── launch.sh                  # Safe terminal launcher
├── CONCLAVE.sigil             # Agent session registry
├── DESIGN-NOTES.md            # High-level design notes
└── LESSONS-LEARNED.md         # Organizational memory
```

## Language

Morgoth is written in **Sigil**. This project serves as both a practical tool
and a dogfooding exercise for the Sigil language ecosystem.
