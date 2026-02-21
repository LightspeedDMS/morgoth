#!/bin/bash
# Morgoth safe launch wrapper
# Defense-in-depth: restores terminal even if morgoth crashes before shutdown

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGIL_BIN="${SCRIPT_DIR}/../sigil-lang/parser/target/release/sigil"
MORGOTH_SRC="${SCRIPT_DIR}/src/morgoth.sg"

if [ ! -f "$SIGIL_BIN" ]; then
    echo "Error: sigil binary not found at $SIGIL_BIN"
    echo "Build first: cd sigil-lang/parser && cargo build --release --no-default-features --features jit,native,protocols"
    exit 1
fi

if [ ! -f "$MORGOTH_SRC" ]; then
    echo "Error: morgoth.sg not found at $MORGOTH_SRC"
    exit 1
fi

# --hmr flag enables hot-module-reload (watches morgoth.sg for changes)
[[ " $* " == *" --hmr "* ]] && export MORGOTH_HMR_OVERRIDE=1

# Propagate source path so morgoth can resolve it regardless of cwd
export MORGOTH_SRC="$MORGOTH_SRC"

# Environment for child shells
export MORGOTH=1
export TERM=xterm-256color
export COLORTERM=truecolor

# Save terminal state
saved=$(stty -g)

cleanup() {
    stty "$saved" 2>/dev/null
    printf '\033[?25h\033[?1003l\033[?1006l\033[?1049l'
    echo "Terminal restored."
}
trap cleanup EXIT INT TERM

exec "$SIGIL_BIN" run "$MORGOTH_SRC"
