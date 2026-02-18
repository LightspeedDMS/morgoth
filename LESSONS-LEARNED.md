# Lessons Learned

Organizational memory for the Morgoth project. Document mistakes, discoveries,
and successful patterns here so future sessions don't repeat past errors.

See [PROJECT-WELLNESS.md](../methodologies/PROJECT-WELLNESS.md) for format guidelines.

---

## LL-001: Follow Agent-TDD Cycle Strictly

**Date:** 2026-02-17
**Phase:** Phase 0 (stdlib extensions)
**Severity:** Process

When implementing Phase 0 stdlib primitives, the agent jumped straight to
reading implementation code (IMPLEMENT) without first writing specification
tests (SPECIFY). Lilith caught this: "are we following Daemoniorum best
practices for Agent TDD?"

**Lesson:** Always follow UNDERSTAND → SPECIFY → IMPLEMENT → VERIFY → REFACTOR.
Write all spec tests first (RED), confirm they fail for the right reason, then
implement (GREEN). The temptation to "just read the code and start coding" is
strong but skips the most valuable step — crystallizing understanding as tests.

---

## LL-002: Example Tests Are Not Property Tests

**Date:** 2026-02-17
**Phase:** Phase 0 compliance audit
**Severity:** Quality

The initial test suite had tests that only verified "does the function return
something?" without testing roundtrip properties. For example:

- `term_set_winsize` was tested only for return code 0, not that
  `get_winsize` reflected the change afterward
- `Sys·write` to a pipe was tested but `Sys·read` from that pipe was not
- PTY I/O was entirely untested (no write→read roundtrip)
- Signals could be registered and checked for pending, but no delivery path

**Lesson:** Always include roundtrip/property tests alongside example tests.
If you can `set` something, test that `get` returns it. If you can `write`,
test that `read` gets the data back. A test that only exercises one direction
of a bidirectional API is incomplete.

---

## LL-003: Thread-Local State Maps Need Complete Lifecycle

**Date:** 2026-02-17
**Phase:** Phase 0 compliance audit
**Severity:** Bug risk

Adding new `FAKE_*_STATE` maps (termios, pipe, pty, signal, winsize, pty_buffer)
requires updating three places:

1. **thread_local! block** — declare the map
2. **Sys·close** — clean up entries on fd close
3. **Sys·dup2** — copy entries when fds are duplicated

Missing any of these causes subtle bugs: leaked state on close, or dup2'd fds
that don't inherit the original's properties.

**Lesson:** When adding a new state map, grep for `Sys·close` and `Sys·dup2`
and add cleanup/copy logic immediately. Don't defer it.

---

## LL-004: LLVM Not Available — Build Flags

**Date:** 2026-02-17
**Phase:** Phase 0 build
**Severity:** Infrastructure

This system doesn't have LLVM installed. The default `cargo build --release`
fails with "No suitable version of LLVM was found."

**Fix:** Build with `--no-default-features --features jit,native` to use
Cranelift JIT backend instead of LLVM.
