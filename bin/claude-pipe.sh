#!/bin/bash
# claude-pipe.sh — Watches ~/.morgoth/claude-in.txt and injects new content
# into the focused pane of the running Morgoth instance.
#
# Started automatically by launch.sh when running inside tmux.
# Stops when the parent Morgoth process exits.
#
# Morgoth routes all keystrokes to its focused terminal pane, so sending
# text to Morgoth's tmux pane is equivalent to typing it into Claude Code
# (when Claude Code is the focused pane).
#
# Multi-line content has newlines collapsed to spaces — Claude Code's input
# box submits on Enter, so raw newlines would prematurely send the message.
#
# TMUX_PANE is inherited from launch.sh at fork time (before exec). It holds
# the tmux pane ID (e.g. %3) for the pane running Morgoth.

CLAUDE_IN="${HOME}/.morgoth/claude-in.txt"
LAST_CONTENT=""

# TMUX_PANE is set by tmux in every pane's environment. Since this script
# is backgrounded before launch.sh execs sigil, it inherits the correct value.
TARGET="${TMUX_PANE}"

if [ -z "$TARGET" ]; then
    # Not inside tmux — nothing to do.
    exit 0
fi

while true; do
    sleep 1

    [ ! -f "$CLAUDE_IN" ] && continue

    CONTENT=$(cat "$CLAUDE_IN" 2>/dev/null)

    # Skip if unchanged or empty
    [ "$CONTENT" = "$LAST_CONTENT" ] && continue
    LAST_CONTENT="$CONTENT"
    [ -z "$CONTENT" ] && continue

    # Collapse newlines → spaces so we don't prematurely submit in Claude Code.
    # Trim trailing whitespace.
    INLINE=$(printf '%s' "$CONTENT" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    [ -z "$INLINE" ] && continue

    # Send as literal text into Morgoth's input. Morgoth forwards it to the
    # focused pane — if that pane is Claude Code, text appears in the prompt.
    # The user sees the yanked text appear and can edit before submitting.
    tmux send-keys -t "$TARGET" -l "$INLINE"
done
