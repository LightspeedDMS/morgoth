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

---

## LL-005: Sigil String API — Functions That Don't Exist

**Date:** 2026-02-18
**Phase:** Phase 2 (VTerm, rendering)
**Severity:** Critical

The following commonly-assumed string functions do NOT exist in Sigil:

| Assumed | Actual | Notes |
|---------|--------|-------|
| `substr(s, start, len)` | `substring(s, start, end)` | End index, not length |
| `chr(n)` | `from_char_code(n)` | Integer to string |
| `ord(s)` | `char_code_at(s, idx)` | Returns integer code at index |

These were used freely in morgoth.sg's rendering functions (render_border,
render_content, render_status_bar) and input processing (process_input). All
crashed at runtime.

**Lesson:** Before writing Sigil code that uses string manipulation, verify the
actual stdlib API. The function names do not follow C, Python, or JavaScript
conventions — they follow their own vocabulary.

---

## LL-006: char_at() Returns Char, Not String

**Date:** 2026-02-18
**Phase:** Phase 2 (VTerm)
**Severity:** Critical

`char_at(str, idx)` returns a **char** type, not a string. Comparing a char to
a string literal (`char_at(s, 0) == "A"`) fails with "Invalid char/string
operation". Passing a char to functions expecting strings (e.g., `Sys·write`,
string concatenation) also fails.

**Fix:** Always wrap: `to_string(char_at(str, idx))`.

**Lesson:** Sigil distinguishes char and string types. Any time you extract a
character from a string, convert it back to string immediately if you need
string operations.

---

## LL-007: Array Concatenation With + Does Not Work

**Date:** 2026-02-18
**Phase:** Phase 2 (VTerm)
**Severity:** Critical

`arr + [item]` and `[a] + [b]` both fail with "Invalid array operation". The
`+` operator is not defined for arrays in Sigil.

**Fix:** Use `push(arr, item)` for appending. For merging arrays, iterate and
push each element.

**Lesson:** Do not assume `+` works on arrays. Sigil arrays are mutable
containers modified via `push()`, `pop()`, and index assignment — not
concatenated via operators.

---

## LL-008: Map Bracket Indexing Doesn't Work on JSON Objects

**Date:** 2026-02-18
**Phase:** Phase 2 (Monitor plugin)
**Severity:** High

`json_parse()` returns a struct/map. Bracket indexing (`obj["key"]`) fails with
"Cannot index". Dot access (`obj.key`) works for known simple identifiers but
crashes on missing fields with "no field 'X' in map".

**Fix:** Use `map_get(obj, "key")` which returns `null` for missing keys.
Use `map_keys(obj)` to enumerate available keys.

**Lesson:** For JSON data with dynamic or potentially-missing keys, always use
`map_get()`. Reserve dot access only for fields you are certain exist.

---

## LL-009: Multiple Early Returns Cause Type Errors

**Date:** 2026-02-18
**Phase:** Phase 2 (Monitor plugin)
**Severity:** High
**Status:** ✅ RESOLVED (2026-02-18)

Functions with multiple `↩` (return) statements in different `⎇` branches
previously triggered "type mismatch in return" errors. The root cause was that
`collect_fn_sig` and `check_function` used `Type::Unit` for unannotated return
types — fresh type variables now unify with any return type.

**Resolution:** The type checker fix (commit 1452796) resolved this. Regression
tests P2_017–P2_020 confirm `↩` works with int, array, null, and multi-branch
returns. The `≔ mut result` workaround is no longer necessary — both styles
(early `↩` and single-return-point) work correctly.

---

## LL-010: Variables Reassigned Inside ⎇ Blocks Need mut

**Date:** 2026-02-18
**Phase:** Phase 2 (SDD audit)
**Severity:** High

Variables declared with `≔` (non-mut) that are reassigned inside `⎇` blocks
cause runtime errors. This is a Sigil scoping rule: `⎇` blocks create a nested
scope, and reassigning an outer variable requires `≔ mut`.

```sigil
// WRONG — will fail
≔ title = "pane";
⎇ focused { title = "[pane]"; }

// RIGHT
≔ mut title = "pane";
⎇ focused { title = "[pane]"; }
```

**Lesson:** Any variable that might be reassigned inside `⎇`, `⎉`, or `⟳`
blocks must be declared `≔ mut`. This includes loop counters reassigned in loop
bodies (though most of those are already caught early).

---

## LL-011: Native Syscall Fallbacks Change Test Behavior

**Date:** 2026-02-18
**Phase:** Phase 2 (native syscalls)
**Severity:** Medium

Adding `#[cfg(all(unix, feature = "native"))]` libc fallbacks to `Sys·poll_fd`
changed behavior for fd 0 (stdin). In interpreter-only mode, polling fd 0
returns false (no fake state). With native fallback, `libc::poll()` correctly
detects piped stdin in the test harness as readable.

**Fix:** P1_103 was restructured to poll an empty PTY master instead of fd 0,
testing the same "poll returns false when no data" behavior without depending
on the stdin environment.

**Lesson:** When adding native syscall fallbacks, audit all tests that rely on
specific fd behavior. Tests run in piped environments, not real terminals.

---

## LL-012: Flat ⎇ Blocks Cause State Machine Fall-Through

**When:** Phase 3 code review (Feb 2026)
**Severity:** P0 — broke ALL escape sequences in production morgoth.sg

**Problem:** vterm_feed used flat (independent) `⎇` blocks for each state:

```sigil
⎇ vt.esc_state == "normal" { ... }   // sets state = "escape"
⎇ vt.esc_state == "escape" { ... }   // FIRES SAME ITERATION — resets to "normal"
⎇ vt.esc_state == "csi" { ... }
```

Each `⎇` is evaluated independently. When the normal handler sets
`esc_state = "escape"`, the escape handler immediately fires on the SAME byte,
resetting state to "normal". Result: ESC is consumed and discarded, no CSI/OSC/DCS
sequence can ever be entered.

**Why not caught:** All test files define their OWN `vterm_feed` with correct
`⎇`/`⎉` chains. They never exercise the production code in morgoth.sg.

**Fix:** Replace flat `⎇` with a single `⎇`/`⎉` chain so exactly one state
handler fires per byte:

```sigil
⎇ vt.esc_state == "csi" { ... }
⎉ { ⎇ vt.esc_state == "osc" { ... }
⎉ { ⎇ vt.esc_state == "escape" { ... }
⎉ { /* normal */ } } }
```

**Prevention:** Added integration test P3_350 that uses the production `⎇`/`⎉`
chain structure to catch divergence between test copies and production code.

**Rule:** In Sigil, NEVER use flat `⎇` blocks when one handler can change
the state variable checked by a subsequent handler. Always use `⎇`/`⎉` chains
for state machines and dispatch tables.

---

## LL-013: starts_with() Fails Type Inference on Implicit Returns

**When:** Phase 3 test fixes (Feb 2026)
**Severity:** P2 — type checker bug, workaround available
**Status:** ✅ RESOLVED (2026-02-18)

**Problem:** `starts_with(fn_result, prefix)` previously failed with "type
mismatch: expected str, found ()" when the function returned a string via
implicit return. This was the same root cause as LL-009 — `Type::Unit` default
for unannotated return types.

**Resolution:** Fixed by the same type inference change (fresh type variables
in `collect_fn_sig`/`check_function`). Verified with a direct test: implicit
returns passed to `starts_with()` and `contains()` work without coercion.
P2_016 (existing test) also confirms this. The `"" + expr` workaround is no
longer necessary.
