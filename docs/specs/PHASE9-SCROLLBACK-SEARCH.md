# Phase 9: Scrollback Search

**Version:** 0.1.0
**Status:** Draft
**Date:** 2026-02-18
**Authors:** Lilith + Claude (Opus 4.6)
**Parent Spec:** [MORGOTH-SPEC.md](MORGOTH-SPEC.md)

---

## 1. Conceptual Foundation

Phase 2 added a scrollback buffer and leader+k/j for manual scrolling.
Phase 8 (copy mode) adds a cursor for navigating content. Scrollback search
adds the ability to find text in the buffer by typing a query.

### 1.1 Interaction Model

Two entry points:

1. **From normal mode:** `Ctrl-B /` enters search directly
2. **From copy mode:** `/` enters search, results position the copy cursor

Search is incremental: results update as the user types. Matches are
highlighted in the pane content. `n`/`N` navigate between matches.

### 1.2 Search Scope

Search covers the focused pane's scrollback buffer + visible cells.
This is the same content used by copy mode (Phase 8). Scrollback entries
are arrays of `{ch, fg, bg}` cell objects — text must be extracted from
the `ch` field before searching. Search does not cross pane boundaries.

---

## 2. Type Architecture

```
SearchState:
    active: bool
    query: string
    matches: [Position]       // all match positions
    current_match: int        // index into matches (focused match)
    direction: "forward" | "backward"

Position:
    row: int
    col: int
```

---

## 3. Behavioral Contracts

### 3.1 Enter Search

```
on leader + '/' (or '/' in copy mode):
    search_state ← SearchState {
        active: true,
        query: "",
        matches: [],
        current_match: -1,
        direction: "backward",   // search upward by default
    }
    show search prompt: "/" at bottom of pane
    enter text input mode
```

### 3.2 Incremental Search

```
on each keystroke while search active:
    append character to query
    matches ← find_all(content, query)
    if len(matches) > 0:
        // Jump to nearest match above cursor
        current_match ← nearest_match(matches, cursor, direction)
        scroll to show current_match
    highlight all matches
    show match count: "[M/N]" in search prompt
```

### 3.3 Navigation

| Key | Action |
|-----|--------|
| Any printable char | Append to query, re-search |
| Backspace | Remove last char from query, re-search |
| Enter | Accept search, position cursor at match, exit search |
| Escape | Cancel search, restore previous position, exit |
| `n` (after accept) | Jump to next match |
| `N` (after accept) | Jump to previous match |
| Ctrl-N (during search) | Next match while typing |
| Ctrl-P (during search) | Previous match while typing |

### 3.4 Match Highlighting

```
render_search_highlights(content, matches, current_match):
    for each match in matches:
        for each cell in match range:
            if match == matches[current_match]:
                cell.attr ← reverse + bold    // current match
            else:
                cell.attr ← reverse           // other matches
```

Current match is visually distinct (bold + reverse) from other matches
(reverse only).

### 3.5 Case Sensitivity

Search is case-insensitive by default. If the query contains any uppercase
character, search becomes case-sensitive (smartcase, like vim).

```
is_case_sensitive(query):
    return any(c is uppercase for c in query)
```

---

## 4. Constraints & Invariants

```
P1: Search does not modify pane content
    Only overlays highlights

P2: matches is always sorted by position (row, col)
    // Enables efficient n/N navigation

P3: current_match ∈ [-1, len(matches) - 1]
    // -1 means no match focused

P4: Cancel restores pre-search scroll position and cursor
    // No side effects on cancel

P5: After accept, n/N navigation wraps around
    After last match, n goes to first match
    // Consistent with vim/less behavior
```

---

## 5. Error Conditions

| Condition | Behavior |
|-----------|----------|
| Empty query | Clear highlights, show all content |
| No matches | Show "Pattern not found" in search prompt |
| Regex-invalid query | Treat as literal string (no regex support) |
| Very long query | Truncate display at pane width, search still works |

---

## 6. Integration Points

### 6.1 Copy Mode (Phase 8)

If the user enters search from copy mode, the search result positions the
copy mode cursor. Accepting a search match moves the cursor to that
position. The user can then start a selection from the match location.

If Phase 8 is not yet implemented, search from normal mode simply scrolls
to show the match and exits.

### 6.2 Scrollback Buffer (Phase 2)

Search reads from the existing scrollback buffer. No changes to the
scrollback data structure needed — search is read-only.

**Caveat:** The VTerm is currently destroyed on resize (Phase 6 bug), which
clears all scrollback. If Phase 6's `vterm_resize` is not yet implemented,
users will lose searchable history after a terminal resize.

### 6.3 String Matching

The search function needs efficient substring matching. For the expected
buffer sizes (scrollback cap is typically 1000-10000 lines), naive O(n*m)
search is fast enough. No need for KMP or similar.

**Note:** Scrollback entries are arrays of `{ch, fg, bg}` cell objects, not
strings. The search function must first extract text from cells (same as
copy mode — see Phase 8 section 3.1).

**Note:** VTerm is currently destroyed and recreated on resize (see Phase 6),
which loses all scrollback content. If Phase 6 is not yet implemented,
search after a resize will only cover post-resize content.

```
find_all(text_lines, query) → [Position]:
    matches ← []
    ≔ case_sensitive = is_case_sensitive(query)
    ≔ ci_query = query
    ⎇ (not case_sensitive) { ci_query = lower(query); }
    ≔ mut row = 0
    ⟳ (row < len(text_lines)):
        ≔ line = text_lines[row]
        ≔ ci_line = line
        ⎇ (not case_sensitive) { ci_line = lower(line); }
        // index_of takes 2 args — no starting_at offset.
        // Use substring to search past previous matches.
        ≔ mut col = 0
        ≔ mut remaining = ci_line
        ⟳ (len(remaining) > 0):
            ≔ idx = index_of(remaining, ci_query)
            ⎇ (idx >= 0) {
                push(matches, Position { row: row, col: col + idx })
                col = col + idx + 1
                remaining = substring(ci_line, col, len(ci_line))
            } ⎉ {
                remaining = ""   // break
            }
        row = row + 1
    ↩ matches
```

---

## 7. Test Plan

| ID | Test | Validates |
|----|------|-----------|
| P9_900 | Enter search sets active state | 3.1 |
| P9_901 | Typing updates query and finds matches | 3.2 |
| P9_902 | Backspace removes character and re-searches | 3.3 |
| P9_903 | Enter accepts and positions at match | 3.3 |
| P9_904 | Escape cancels and restores position | P4 |
| P9_905 | n/N navigate between matches | 3.3, P5 |
| P9_906 | n wraps from last to first match | P5 |
| P9_907 | No matches shows "Pattern not found" | 5 |
| P9_908 | Smartcase: lower = insensitive, uppercase = sensitive | 3.5 |
| P9_909 | Current match has distinct highlight | 3.4 |
| P9_910 | Search highlights don't modify content | P1 |

---

## 8. Open Questions

1. **Regex support:** Should search support regex patterns?
   - Recommendation: No. Literal substring search covers the common case
     and avoids complexity. Regex can be added later.

2. **Persistent highlights:** After accepting search, should matches stay
   highlighted until the next search?
   - Recommendation: Yes, like vim's `hlsearch`. Clear with `Ctrl-B :noh`
     or on next search.

3. **Cross-pane search:** Search all panes at once?
   - Recommendation: No. Single-pane search only. Cross-pane is a
     Phase 18 concern.

4. **Search history:** Remember previous search queries?
   - Recommendation: Yes, store last 20 queries. Up/Down arrow in search
     prompt cycles through history. But defer to a later iteration.

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0 | 2026-02-18 | Initial draft |
