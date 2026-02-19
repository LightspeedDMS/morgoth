# Agent-TDD Roadmap: Tier 1 (Phases 6–9)

**Version:** 0.1.0
**Status:** Draft
**Date:** 2026-02-18
**Authors:** Lilith + Claude (Opus 4.6)
**Methodology:** [AGENT-TDD.md](../../sigil-lang/kit/methodologies/AGENT-TDD.md)

---

## 1. Current State

**Tests:** 78 total across 3 phases (P1: 21, P2: 22, P3: 35)
**Pass rate:** 79/79 Morgoth tests (100%), 862/866 total (99%)
**ID ranges used:** P1=100s, P2=200s, P3=300s
**ID ranges reserved:** P6=600s, P7=700s, P8=800s, P9=900s

### 1.1 Test Infrastructure

- Test format: `.sg` + `.expected` file pairs
- Runner: `./run_tests_rust.sh --spec 23_morgoth`
- Tests define their own helper functions (VTerm, layout, etc.) rather than
  importing from morgoth.sg — this is intentional for isolation but creates
  divergence risk (see LL-012)
- Real PTY fds (< 4000) use native libc; fake fds (>= 4000) use FAKE_*_STATE

### 1.2 Lessons That Shape This Roadmap

| Lesson | Impact on Test Design |
|--------|----------------------|
| LL-001 | SPECIFY before IMPLEMENT — write tests first |
| LL-002 | Always include roundtrip/property tests |
| LL-005 | Verify stdlib API names before writing tests |
| LL-006 | `char_at()` returns char — wrap with `to_string()` |
| LL-010 | Use `≔ mut` for variables reassigned in `⎇` blocks |
| LL-011 | Native fallbacks change test behavior for real fds |
| LL-012 | Test copies diverge from production — add integration tests |

---

## 2. Phase Ordering Strategy

The specs say Phases 6–9 are independent and can be implemented in any
order. From a testing perspective, the optimal order is:

```
Phase 6 (Resize) ─── first: fixes bugs, enables meaningful Phase 8/9 testing
    │
    ├── Phase 7 (Dynamic Panes) ─── second: needs grid auto-sizing, uses resize
    │
    └── Phase 8 (Copy/Paste) ─── third: needs stable content model
            │
            └── Phase 9 (Search) ─── fourth: reuses Phase 8's text extraction
```

**Rationale:**

- Phase 6 fixes two bugs (outer dims, VTerm destruction) that affect all
  other phases. Without `vterm_resize`, Phase 8/9 testing is meaningless
  after any resize event (scrollback is destroyed).
- Phase 7 depends on Phase 6 for `propagate_sizes` after grid recomputation.
- Phase 8 establishes the content model (cell arrays → text lines) that
  Phase 9 reuses for search.
- Phase 9 is a pure read-only overlay on Phase 8's content extraction.

---

## 3. Phase 6: Resize Propagation

### 3.1 Test Strategy: Explore First

Phase 6 is primarily a bugfix phase. The explore-first approach (Agent-TDD
§2.3) is appropriate because:

- We know the bugs (outer dims, VTerm destruction)
- We need to understand the existing resize path before testing it
- The new `vterm_resize` function has complex cell-grid logic

**Cycle:** UNDERSTAND existing resize path → SPECIFY tests → IMPLEMENT
`vterm_resize` + dim fixes → VERIFY → REFACTOR

### 3.2 Test Plan

| ID | Name | Category | What It Crystallizes |
|----|------|----------|---------------------|
| P6_600 | pty_inner_dims | Spec | `Pty·set_size` receives inner dims (h-2, w-2) after relayout |
| P6_601 | vterm_resize_clamp_cursor | Spec | Cursor clamped to new bounds on shrink |
| P6_602 | vterm_resize_grid_dims | Spec | Cell grid matches new rows × cols after resize |
| P6_603 | vterm_resize_scrollback_preserve | Property | Content pushed to scrollback on shrink, not lost |
| P6_604 | initial_spawn_inner_dims | Spec | `Pane·new` calls `Pty·set_size` with inner dims |
| P6_605 | vterm_resize_expand | Boundary | Growing the grid adds empty rows/cols |
| P6_606 | vterm_resize_noop | Boundary | Same-size resize is idempotent (no content change) |
| P6_607 | vterm_resize_scroll_offset_reset | Spec | `scroll_offset` resets to 0 after resize |
| P6_608 | vterm_resize_scrollback_eviction | Boundary | Scrollback cap enforced during resize-induced push |

**9 tests.** Primarily specification tests validating the corrected behaviors
from the Phase 6 spec review.

### 3.3 Key Test Patterns

```
// P6_603 — Property test: roundtrip content preservation
// Write 10 lines of content, resize from 10 rows to 5 rows.
// Verify: 5 lines moved to scrollback, 5 remain in cells.
// Resize back to 10 rows. Verify: content still accessible via scrollback.
```

```
// P6_600 — Specification test: inner dims
// Create pane with region {h: 24, w: 80}.
// After relayout, verify Pty·set_size called with (22, 78), not (24, 80).
```

### 3.4 Stdlib Functions Used

| Function | Verified Exists | Notes |
|----------|----------------|-------|
| `Pty·set_size(fd, rows, cols)` | Yes | Native ioctl path for real fds |
| `VTerm·new(rows, cols)` | Yes | Will be partially replaced by `vterm_resize` |
| `push(arr, item)` | Yes | For scrollback append |
| `slice(arr, start, end)` | Yes | For scrollback eviction |
| `len(arr)` | Yes | |

---

## 4. Phase 7: Dynamic Pane Management

### 4.1 Test Strategy: Test First

Phase 7 has well-defined behavioral contracts (create pane, close pane,
zoom, grid auto-sizing). The spec is clear enough for test-first.

**Cycle:** SPECIFY all tests → IMPLEMENT `recompute_grid` + leader bindings
→ VERIFY → REFACTOR

### 4.2 Test Plan

| ID | Name | Category | What It Crystallizes |
|----|------|----------|---------------------|
| P7_700 | create_pane | Spec | Create increases pane count, assigns valid fd/pid |
| P7_701 | close_pane | Spec | Close decreases count, cleans up resources |
| P7_702 | cannot_close_last | Boundary | Cannot close when `len(panes) == 1` |
| P7_703 | grid_auto_1_to_8 | Spec | `recompute_grid` returns optimal rows×cols for 1–8 panes |
| P7_704 | focus_after_close | Spec | Focus index adjusts when closed pane was focused |
| P7_705 | zoom_fullscreen | Spec | Zoomed pane fills screen minus status bar |
| P7_706 | unzoom_restore | Spec | Unzoom restores original pane regions |
| P7_707 | zoom_bg_alive | Property | Non-focused panes continue receiving PTY output during zoom |
| P7_708 | close_confirm_cancel | Spec | 'n' during close confirmation cancels |
| P7_709 | close_confirm_proceed | Spec | 'y' during close confirmation proceeds |
| P7_710 | create_monitor | Spec | Leader + 'm' creates monitor pane (master_fd = -1) |
| P7_711 | shell_from_env | Spec | Shell determined by `env("SHELL")` with `/bin/bash` fallback |
| P7_712 | grid_auto_aspect | Property | Grid dimensions minimize aspect ratio distortion |
| P7_713 | pty_open_fail | Boundary | `Pty·open` failure shows error in status bar, no pane created |
| P7_714 | stuck_process_sigkill | Boundary | Close escalates SIGTERM → wait 2s → SIGKILL on stuck process |

**15 tests.** Mix of specification, property, and boundary tests.

### 4.3 Key Test Patterns

```
// P7_703 — Specification test: grid auto-sizing truth table
// 1 pane → 1×1, 2 → 1×2, 3 → 2×2, 4 → 2×2, 5 → 2×3, 6 → 2×3,
// 7 → 3×3, 8 → 3×3
// Each entry verified against recompute_grid(n, 30, 120)
```

```
// P7_707 — Property test: background panes alive during zoom
// Create 2 terminal panes. Zoom pane 0.
// Write to pane 1's master_fd. Poll + read from pane 1's master_fd.
// Verify output received (pane 1 still processing despite not rendered).
```

### 4.4 Stdlib Functions Used

| Function | Verified Exists | Notes |
|----------|----------------|-------|
| `env(name)` | Yes | For `$SHELL` detection |
| `Pty·open()` | Yes | Returns `{master_fd, slave_fd}` |
| `Sys·spawn_pty(cmd, args, slave_fd)` | Yes | Fork/exec |
| `Sys·kill(pid, signal)` | Yes | For close pane |
| `Sys·waitpid(pid, flags)` | Yes | For close pane cleanup |
| `Sys·close(fd)` | Yes | For fd cleanup |
| `ceil(n)` | Yes | 1 arg, returns ceiling integer |

### 4.5 Discovery Risk

`recompute_grid` is entirely new logic. The grid auto-sizing algorithm may
need tuning during implementation. If the heuristic produces unexpected
layouts, update the spec (SDD §2.2) before adjusting tests.

---

## 5. Phase 8: Copy/Paste Mode

### 5.1 Test Strategy: Explore First, Then Test

Phase 8 introduces a new input state (copy mode) that interacts with the
existing input state machine. The content model (cell arrays → text lines)
needs exploration to validate before committing to tests.

**Cycle:** UNDERSTAND input state machine + cell format → SPECIFY text
extraction + cursor tests → IMPLEMENT copy mode → VERIFY → REFACTOR

### 5.2 Test Plan

| ID | Name | Category | What It Crystallizes |
|----|------|----------|---------------------|
| P8_800 | enter_copy_mode | Spec | Sets active flag, extracts text from cells |
| P8_801 | cursor_clamp | Spec | Cursor movement clamped to content bounds |
| P8_802 | begin_selection | Spec | Space toggles selection, records start position |
| P8_803 | extract_char_selection | Spec | Enter extracts text between start and cursor |
| P8_804 | escape_exits | Spec | Escape exits without side effects |
| P8_805 | line_select | Spec | 'V' toggles line mode, selects full lines |
| P8_806 | vim_nav | Spec | g/G/0/$  navigate to content extremes |
| P8_807 | half_page | Spec | Ctrl-U/Ctrl-D move by half-page |
| P8_808 | no_affect_others | Property | Copy mode on focused pane doesn't affect others |
| P8_809 | exit_flush | Property | Exiting copy mode flushes buffered PTY data |
| P8_810 | osc52_output | Spec | Clipboard write produces valid OSC 52 sequence |
| P8_811 | cell_to_text | Spec | Text extraction from `{ch, fg, bg}` cell arrays |
| P8_812 | scrollback_in_content | Spec | text_lines includes scrollback + visible cells |
| P8_813 | word_boundary_nav | Spec | 'w'/'b' move to next/previous word boundary |
| P8_814 | empty_content | Boundary | Empty scrollback + visible → cursor at 0,0 |
| P8_815 | empty_selection_noop | Boundary | Selection start = end → copy is no-op |

**16 tests.**

**Note on invariant P5:** P8_803 should verify that selection highlight
uses reverse video without corrupting underlying cell attributes (fg/bg
values preserved after exiting copy mode).

### 5.3 Critical: Content Model Test

P8_811 is the most important test in this phase. It validates the bridge
between the VTerm's internal representation (arrays of `{ch, fg, bg}` cell
objects) and the string-based model copy mode operates on:

```
// P8_811 — Specification test: cell-to-text extraction
// Given a VTerm with cells:
//   row 0: [{ch:" ",fg:"7",bg:"0"}, {ch:"H",fg:"1",bg:"0"}, {ch:"i",fg:"7",bg:"0"}]
//   row 1: [{ch:"!",fg:"7",bg:"0"}, {ch:" ",fg:"7",bg:"0"}, {ch:" ",fg:"7",bg:"0"}]
// Extracted text_lines should be: [" Hi", "!  "]
```

This test must be written and passing before any selection/copy tests make
sense. It's the foundation.

### 5.4 Stdlib Functions Used

| Function | Verified Exists | Notes |
|----------|----------------|-------|
| `base64_encode(string)` | Yes (line ~10921) | For OSC 52 |
| `map_get(obj, key)` | Yes | For accessing cell `.ch` field safely |
| `len(string)` | Yes | For cursor bounds |
| `substring(s, start, end)` | Yes | For text extraction |
| `to_string(value)` | Yes | For cell char extraction if needed |

---

## 6. Phase 9: Scrollback Search

### 6.1 Test Strategy: Test First

Phase 9 is a pure read-only overlay. The behavioral contracts are precise
and well-suited for test-first. All functions needed are verified to exist
(after the spec corrections).

**Cycle:** SPECIFY all tests → IMPLEMENT search state + find_all + highlight
→ VERIFY → REFACTOR

### 6.2 Test Plan

| ID | Name | Category | What It Crystallizes |
|----|------|----------|---------------------|
| P9_900 | enter_search | Spec | Search state initialized, query empty |
| P9_901 | incremental_search | Spec | Typing updates query and finds matches |
| P9_902 | backspace_research | Spec | Backspace removes char, re-runs search |
| P9_903 | accept_positions | Spec | Enter accepts, cursor at match location |
| P9_904 | escape_restores | Spec | Escape restores pre-search scroll position |
| P9_905 | n_N_navigate | Spec | n/N cycle through matches |
| P9_906 | n_wraps | Property | n wraps from last match to first |
| P9_907 | no_matches | Boundary | Empty result shows "Pattern not found" |
| P9_908 | smartcase | Spec | Lowercase = insensitive, any uppercase = sensitive |
| P9_909 | current_match_highlight | Spec | Current match visually distinct (bold+reverse) |
| P9_910 | search_readonly | Property | Search highlights don't modify cell content |
| P9_911 | find_all_multiple_sorted | Spec | Multiple matches on same line found, sorted by (row, col) [P2] |
| P9_912 | find_all_substring_offset | Spec | `index_of` + `substring` workaround finds overlapping-start matches |
| P9_913 | empty_query_clears | Boundary | Empty query clears all highlights |
| P9_914 | ctrl_n_p_during_search | Spec | Ctrl-N/Ctrl-P navigate matches while typing (before accept) |
| P9_915 | literal_special_chars | Boundary | Query with regex-like chars (`.`, `*`, `[`) treated as literals |

**16 tests.**

**Note on invariant P3:** current_match range [-1, len(matches)-1] is
implicitly verified by P9_900 (initial -1), P9_901 (set to valid index),
and P9_905 (navigation stays in range).

### 6.3 Key Test Patterns

```
// P9_908 — Specification test: smartcase
// Content: ["Hello World", "hello world", "HELLO WORLD"]
// Query "hello" (all lowercase) → matches rows 0, 1, 2 (case-insensitive)
// Query "Hello" (has uppercase) → matches row 0 only (case-sensitive)
```

```
// P9_912 — Specification test: substring offset workaround
// Content: ["aaa"]
// Query "aa" → should find 2 matches: (0,0) and (0,1)
// Validates the index_of + substring loop from corrected spec
```

### 6.4 Stdlib Functions Used

| Function | Verified Exists | Notes |
|----------|----------------|-------|
| `lower(string)` | Yes | For case-insensitive search |
| `index_of(string, substring)` | Yes | 2 args only, no offset param |
| `substring(s, start, end)` | Yes | For offset workaround (`substr` does NOT exist) |
| `len(string)` | Yes | |
| `push(arr, item)` | Yes | For building matches array |
| `char_code_at(s, idx)` | Yes | For uppercase detection in smartcase |

---

## 7. Cross-Phase Integration Tests

After individual phase tests pass, add integration tests that exercise
interactions between phases:

| ID | Name | Phases | What It Crystallizes |
|----|------|--------|---------------------|
| TI_950 | resize_during_copy_mode | 6 + 8 | Copy mode handles resize gracefully (**spec gap**: Phase 8 doesn't define resize-during-copy behavior — resolve before writing test) |
| TI_951 | search_after_resize | 6 + 9 | Search works on content preserved by `vterm_resize` |
| TI_952 | zoom_then_copy | 7 + 8 | Copy mode works in zoomed pane |
| TI_953 | create_pane_resize | 6 + 7 | New pane triggers resize propagation |
| TI_954 | search_from_copy | 8 + 9 | '/' in copy mode enters search, positions cursor |

**5 integration tests.** Write these only after individual phase tests pass.

---

## 8. Test Count Summary

| Phase | Spec Tests | Property Tests | Boundary Tests | Total |
|-------|-----------|---------------|----------------|-------|
| P6 | 5 | 1 | 3 | 9 |
| P7 | 10 | 2 | 3 | 15 |
| P8 | 12 | 2 | 2 | 16 |
| P9 | 11 | 2 | 3 | 16 |
| Integration | 5 | 0 | 0 | 5 |
| **Total** | **43** | **7** | **11** | **61** |

*Includes discovery buffer — expect 1–3 additional tests per phase as
implementation reveals spec gaps (SDD §2.2).*

**Projected total after Tier 1:** 78 (existing) + 61 (new) = ~139 tests

---

## 9. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `vterm_resize` cell logic has edge cases not covered by tests | High | Medium | Add fuzz-style tests with random resize sequences |
| `substring` vs `substr` confusion in tests | Medium | Low | Only `substring(s, start, end)` exists; `substr` does NOT |
| Copy mode input state conflicts with existing leader/escape state | Medium | High | Integration test TI_950; explore input state machine first |
| Test helpers diverge from production code (LL-012) | Medium | High | Add integration tests mirroring production code paths |
| OSC 52 output test polluted by terminal escape rendering | Low | Medium | Write OSC 52 to pipe, not stdout (LL: escape sequences in tests) |

---

## 10. Definition of Done

Each phase is complete when:

1. All spec tests pass (GREEN)
2. All property tests pass
3. All boundary tests pass
4. Full regression suite passes (862/866 baseline, same 4 known failures)
5. No new warnings in `cargo build`
6. Spec updated if any gaps discovered during implementation (SDD §2.2)
7. LESSONS-LEARNED.md updated with any new discoveries
8. Integration tests (section 7) added for completed cross-phase interactions

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0 | 2026-02-18 | Initial draft. Covers Tier 1 (Phases 6–9). |
