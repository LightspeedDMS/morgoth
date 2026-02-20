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

# Environment for child shells
export MORGOTH=1
export TERM=xterm-256color
export COLORTERM=truecolor

# Save terminal state
saved=$(stty -g)

# Start claude-pipe watcher when running inside tmux.
# It watches ~/.morgoth/claude-in.txt and injects yanked text into the
# Claude Code pane so copy-mode yank flows directly to Claude's input box.
CLAUDE_PIPE_PID=""
if [ -n "$TMUX" ]; then
    "${SCRIPT_DIR}/bin/claude-pipe.sh" &
    CLAUDE_PIPE_PID=$!
fi

cleanup() {
    [ -n "$CLAUDE_PIPE_PID" ] && kill "$CLAUDE_PIPE_PID" 2>/dev/null
    stty "$saved" 2>/dev/null
    printf '\033[?25h\033[?1003l\033[?1006l\033[?1049l'
    echo "Terminal restored."
}
trap cleanup EXIT INT TERM

exec "$SIGIL_BIN" run "$MORGOTH_SRC"
