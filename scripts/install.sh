#!/bin/zsh
# Install the Patter hooks and status line into Claude Code's user settings.
#
#   ./scripts/install.sh            install / update (idempotent)
#   ./scripts/install.sh --dry-run  print the resulting settings.json, change nothing
#
# What it does:
#   1. copies hooks/*.sh to ~/.patter/bin
#   2. backs up ~/.claude/settings.json
#   3. registers patter-hook.sh as an async hook for the events Patter uses
#   4. sets patter-statusline.sh as the status line, chaining your previous one
#   5. migrates an install from when Patter was called CC Pulse (~/.cc-pulse)
#
# Re-running replaces Patter's own entries (and CC Pulse's old ones) and
# leaves everything else alone.

set -euo pipefail

dry_run=false
[[ "${1:-}" == "--dry-run" ]] && dry_run=true

repo="${0:A:h:h}"
patter_home="${PATTER_HOME:-$HOME/.patter}"
# Where the previous name, CC Pulse, installed itself.
legacy_home="${CC_PULSE_HOME:-$HOME/.cc-pulse}"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$claude_dir/settings.json"
hook_cmd="$patter_home/bin/patter-hook.sh"
status_cmd="$patter_home/bin/patter-statusline.sh"
chain_file="$patter_home/statusline-chain"
legacy_chain="$legacy_home/statusline-chain"

if ! command -v jq >/dev/null 2>&1; then
  print -u2 "patter: jq is required (macOS 15+ ships it; otherwise: brew install jq)"
  exit 1
fi

if [[ -f "$settings" ]]; then
  current="$(<"$settings")"
  if ! print -r -- "$current" | jq empty 2>/dev/null; then
    print -u2 "patter: $settings is not valid JSON; fix it first, nothing was changed"
    exit 1
  fi
else
  current='{}'
fi

# Events Patter listens to, and their matcher ("" = no matcher).
events='{
  "SessionStart": "", "UserPromptSubmit": "", "PreToolUse": "*", "PostToolUse": "*",
  "PermissionRequest": "*", "Notification": "", "Stop": "", "StopFailure": "",
  "SubagentStart": "", "SubagentStop": "", "TaskCreated": "", "TaskCompleted": "",
  "PreCompact": "", "SessionEnd": ""
}'

# Previous status line, unless it is already ours (under either name).
previous_status="$(print -r -- "$current" | jq -r '.statusLine.command // empty')"
if [[ "$previous_status" == *(patter|pulse)-statusline.sh* ]]; then
  previous_status=""
fi

# Carry the chained status line over from a CC Pulse install.
migrate_chain=false
if [[ -z "$previous_status" && ! -s "$chain_file" && -s "$legacy_chain" ]]; then
  migrate_chain=true
fi
remove_legacy=false
[[ -d "$legacy_home" && "${legacy_home:A}" != "${patter_home:A}" ]] && remove_legacy=true

updated="$(print -r -- "$current" | jq --argjson events "$events" \
  --arg hook "$hook_cmd" --arg status "$status_cmd" '
  def ours: (.command // "") | test("(patter|pulse)-(hook|statusline)\\.sh");
  def entry($m): (if $m == "" then {} else {matcher: $m} end)
    + {hooks: [{type: "command", command: $hook, async: true, timeout: 10}]};
  .hooks = (.hooks // {})
  | reduce ($events | to_entries[]) as $e (.;
      .hooks[$e.key] = (
        ((.hooks[$e.key] // [])
          | map(.hooks |= map(select(ours | not)))
          | map(select((.hooks | length) > 0)))
        + [entry($e.value)]))
  | .statusLine = ((.statusLine // {}) + {type: "command", command: $status})
')"

if $dry_run; then
  print -r -- "$updated"
  [[ -n "$previous_status" ]] && print -u2 "patter: would chain previous status line: $previous_status"
  $migrate_chain && print -u2 "patter: would keep chaining your status line from the CC Pulse install: $(<"$legacy_chain")"
  $remove_legacy && print -u2 "patter: would remove the old CC Pulse directory $legacy_home"
  exit 0
fi

mkdir -p "$patter_home/bin" "$patter_home/spool" "$claude_dir"
cp "$repo/hooks/patter-hook.sh" "$repo/hooks/patter-statusline.sh" "$patter_home/bin/"
chmod +x "$patter_home/bin/"*.sh

if [[ -n "$previous_status" ]]; then
  print -r -- "$previous_status" > "$chain_file"
  print "patter: your previous status line will keep running (saved to $chain_file)"
elif $migrate_chain; then
  cp "$legacy_chain" "$chain_file"
  print "patter: kept your chained status line from CC Pulse (saved to $chain_file)"
fi

if [[ -f "$settings" ]]; then
  backup="$settings.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$settings" "$backup"
  print "patter: backed up settings to $backup"
fi

tmp="$settings.patter.tmp"
print -r -- "$updated" > "$tmp"
mv -f "$tmp" "$settings"

# Only once settings no longer point at it.
if $remove_legacy; then
  rm -rf "$legacy_home"
  print "patter: removed the old CC Pulse directory $legacy_home"
fi

print "patter: hooks and status line installed. New Claude Code sessions will report to Patter."
print "patter: already-running sessions pick it up after a restart."
