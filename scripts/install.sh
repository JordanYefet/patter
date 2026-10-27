#!/bin/zsh
# Install the CC Pulse hooks and status line into Claude Code's user settings.
#
#   ./scripts/install.sh            install / update (idempotent)
#   ./scripts/install.sh --dry-run  print the resulting settings.json, change nothing
#
# What it does:
#   1. copies hooks/*.sh to ~/.cc-pulse/bin
#   2. backs up ~/.claude/settings.json
#   3. registers pulse-hook.sh as an async hook for the events CC Pulse uses
#   4. sets pulse-statusline.sh as the status line, chaining your previous one
#
# Re-running replaces CC Pulse's own entries and leaves everything else alone.

set -euo pipefail

dry_run=false
[[ "${1:-}" == "--dry-run" ]] && dry_run=true

repo="${0:A:h:h}"
pulse_home="${CC_PULSE_HOME:-$HOME/.cc-pulse}"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$claude_dir/settings.json"
hook_cmd="$pulse_home/bin/pulse-hook.sh"
status_cmd="$pulse_home/bin/pulse-statusline.sh"

if ! command -v jq >/dev/null 2>&1; then
  print -u2 "cc-pulse: jq is required (macOS 15+ ships it; otherwise: brew install jq)"
  exit 1
fi

if [[ -f "$settings" ]]; then
  current="$(<"$settings")"
  if ! print -r -- "$current" | jq empty 2>/dev/null; then
    print -u2 "cc-pulse: $settings is not valid JSON; fix it first, nothing was changed"
    exit 1
  fi
else
  current='{}'
fi

# Events CC Pulse listens to, and their matcher ("" = no matcher).
events='{
  "SessionStart": "", "UserPromptSubmit": "", "PreToolUse": "*", "PostToolUse": "*",
  "PermissionRequest": "*", "Notification": "", "Stop": "", "StopFailure": "",
  "SubagentStart": "", "SubagentStop": "", "TaskCreated": "", "TaskCompleted": "",
  "PreCompact": "", "SessionEnd": ""
}'

# Previous status line, unless it is already ours.
previous_status="$(print -r -- "$current" | jq -r '.statusLine.command // empty')"
if [[ "$previous_status" == *pulse-statusline.sh* ]]; then
  previous_status=""
fi

updated="$(print -r -- "$current" | jq --argjson events "$events" \
  --arg hook "$hook_cmd" --arg status "$status_cmd" '
  def ours: (.command // "") | test("pulse-(hook|statusline)\\.sh");
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
  [[ -n "$previous_status" ]] && print -u2 "cc-pulse: would chain previous status line: $previous_status"
  exit 0
fi

mkdir -p "$pulse_home/bin" "$pulse_home/spool" "$claude_dir"
cp "$repo/hooks/pulse-hook.sh" "$repo/hooks/pulse-statusline.sh" "$pulse_home/bin/"
chmod +x "$pulse_home/bin/"*.sh

if [[ -n "$previous_status" ]]; then
  print -r -- "$previous_status" > "$pulse_home/statusline-chain"
  print "cc-pulse: your previous status line will keep running (saved to $pulse_home/statusline-chain)"
fi

if [[ -f "$settings" ]]; then
  backup="$settings.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$settings" "$backup"
  print "cc-pulse: backed up settings to $backup"
fi

tmp="$settings.cc-pulse.tmp"
print -r -- "$updated" > "$tmp"
mv -f "$tmp" "$settings"

print "cc-pulse: hooks and status line installed. New Claude Code sessions will report to CC Pulse."
print "cc-pulse: already-running sessions pick it up after a restart."
