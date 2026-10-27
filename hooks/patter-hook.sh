#!/bin/zsh
# Patter hook — drops the Claude Code hook payload into the spool directory.
#
# Claude Code pipes a JSON payload to this script on stdin for every hook event
# it is registered for. We don't parse it here (no jq dependency, ~2 ms runtime):
# we wrap it with a tiny envelope and write it atomically into the spool, where
# the Patter app picks it up and deletes it.
#
# Usage: patter-hook.sh [kind]      kind = "hook" (default) or "status"
#
# Design rules:
#   * never block Claude: registered with "async": true, and always exits 0
#   * never write partial files: write to a dotfile, then mv (atomic on APFS)
#   * no network, no parsing, nothing but a file write

zmodload zsh/datetime 2>/dev/null

kind="${1:-hook}"
[[ "$kind" == (hook|status) ]] || kind="hook"

patter_home="${PATTER_HOME:-$HOME/.patter}"
spool="$patter_home/spool"
mkdir -p "$spool" 2>/dev/null || exit 0

# Microsecond timestamp: orders events, and the app uses it as the event time.
sec="${EPOCHREALTIME%.*}"
frac="${EPOCHREALTIME#*.}"
frac="${(r:6::0:)${frac[1,6]}}"   # exactly 6 digits
ts="$sec$frac"
[[ "$ts" == <-> && ${#ts} -le 18 ]] || ts="$(date +%s)000000"

# Find the Claude Code process (used by the app to drop sessions that crashed).
# Hooks may run via an intermediate shell, so check one level up as well.
claude_pid="$PPID"
comm="$(ps -o comm= -p "$PPID" 2>/dev/null)"
if [[ "$comm" != *claude* ]]; then
  parent="$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')"
  [[ "$parent" == <-> ]] && claude_pid="$parent"
fi
[[ "$claude_pid" == <-> ]] || claude_pid=0

# Terminal app, so the app can bring the right one forward. Strip anything
# that could break the JSON envelope.
term="${TERM_PROGRAM//[^A-Za-z0-9._-]/}"

tmp="$spool/.tmp.$$.$RANDOM"
{
  print -rn -- "{\"_patter\":{\"v\":1,\"ts\":$ts,\"pid\":$claude_pid,\"kind\":\"$kind\",\"term\":\"$term\"},\"payload\":"
  payload="$(cat)"
  if [[ -n "$payload" ]]; then print -rn -- "$payload"; else print -rn -- "null"; fi
  print -r -- "}"
} > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; exit 0; }

mv -f "$tmp" "$spool/$ts-$$.$kind.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
exit 0
