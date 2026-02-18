# Sigil Runtime API Delta

**Date:** 2026-02-18
**Phase:** Phase 2 SDD Compliance Audit
**Status:** Resolved

This document records all gaps discovered between the assumed Sigil runtime API
and the actual implementation during Morgoth Phase 2 development. Per SDD
methodology, implementation was halted and these gaps were audited and fixed
before proceeding.

---

## 1. String Manipulation Functions

### 1.1 Nonexistent Functions

The following functions were assumed to exist based on common language
conventions but are **not present** in the Sigil stdlib:

| Assumed Function | Actual Equivalent | Signature |
|------------------|-------------------|-----------|
| `substr(s, start, len)` | `substring(s, start, end)` | Note: end index, not length |
| `chr(n)` | `from_char_code(n)` | Integer → single-char string |
| `ord(s)` / `ord(s, i)` | `char_code_at(s, i)` | String + index → integer |

### 1.2 char_at() Return Type

`char_at(str, idx)` returns a **char** type, not a **string**. This is a
distinct type in Sigil. Operations that fail on char:

- String comparison: `char_at(s, 0) == "A"` → error
- String concatenation: `buf + char_at(s, 0)` → error
- Passing to string-expecting functions: `Sys·write(fd, char_at(...), 1)` → error

**Correct pattern:** `to_string(char_at(str, idx))`

### 1.3 Confirmed Working String Functions

| Function | Signature | Notes |
|----------|-----------|-------|
| `len(s)` | String → Int | Character count |
| `char_at(s, i)` | String × Int → Char | Single char extraction |
| `char_code_at(s, i)` | String × Int → Int | Unicode code point |
| `from_char_code(n)` | Int → String | Code point to string |
| `substring(s, start, end)` | String × Int × Int → String | Slice by indices |
| `to_string(x)` | Any → String | Universal conversion |
| `to_int(s)` | String → Int | Parse integer |
| `split(s, delim)` | String × String → [String] | Split to array |
| `contains(s, sub)` | String × String → Bool | Substring search |

---

## 2. Array Operations

### 2.1 No + Concatenation

The `+` operator is **not defined** for arrays. Both `arr + [item]` and
`[a] + [b]` fail with "Invalid array operation".

**Correct patterns:**
- Append: `push(arr, item)`
- Merge: iterate source and `push()` each element

### 2.2 Confirmed Working Array Functions

| Function | Signature | Notes |
|----------|-----------|-------|
| `push(arr, item)` | [T] × T → void | Append in place |
| `pop(arr)` | [T] → T | Remove and return last |
| `len(arr)` | [T] → Int | Element count |
| `arr[i]` | Index access | Read and write |
| `arr[i] = val` | Index assignment | Mutates in place |

---

## 3. Map / JSON Object Access

### 3.1 Bracket Indexing Fails

`obj["key"]` on a JSON-parsed object (or any struct/map) fails with "Cannot
index". This is because JSON objects are parsed as structs, not indexable maps.

### 3.2 Dot Access Crashes on Missing Fields

`obj.field` on a field that doesn't exist crashes with "no field 'X' in map".
No null/undefined fallback.

### 3.3 Safe Access Pattern

| Function | Behavior |
|----------|----------|
| `map_get(obj, "key")` | Returns value or `null` if missing |
| `map_keys(obj)` | Returns array of string keys |
| `obj.field` | Direct access — crashes if field missing |

**Rule:** Use `map_get()` for any field that might not exist. Use `map_keys()`
to enumerate. Reserve dot access for guaranteed-present fields.

---

## 4. Type System Constraints

### 4.1 Mutable Variables in ⎇ Blocks

Variables reassigned inside `⎇` (if) blocks must be declared with `≔ mut`.
Sigil's `⎇` blocks create nested scopes, and writing to an outer `≔` variable
from inside that scope is not permitted.

```
≔ mut x = 0;       // Correct — can be reassigned in ⎇
⎇ condition { x = 1; }

≔ y = 0;            // Incorrect — reassignment in ⎇ will fail
⎇ condition { y = 1; }
```

### 4.2 Multiple Return Type Inference

Functions with multiple `↩` (return) statements in different `⎇` branches can
trigger type inference failures, even when all branches return the same type.

**Workaround:** Use a single `≔ mut result` variable, assign in each branch,
return once at the end.

### 4.3 Middledot (·) Naming

The middledot character `·` in function names (e.g., `Region·new`) is reserved
for stdlib-defined functions. User-defined functions cannot use middledot in
their names.

**Workaround:** Use underscore naming: `make_region()`, `vterm_new()`.

---

## 5. Impact Assessment

| Category | Instances Found | Files Affected | Severity |
|----------|----------------|----------------|----------|
| Nonexistent functions | 4 | morgoth.sg | Critical |
| char→string coercion | 2 | morgoth.sg | Critical |
| Missing mut | 5 | morgoth.sg | High |
| Array concat | Multiple (all fixed during impl) | morgoth.sg, tests | Critical |
| Map access | 3 | test files | High |
| Multiple returns | 1 | morgoth.sg | Medium |

All instances were identified during the Phase 2 SDD compliance audit and
fixed before merging. See `LESSONS-LEARNED.md` entries LL-005 through LL-011.
