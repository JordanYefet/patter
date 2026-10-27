#!/bin/zsh
# Remove CC Pulse's hooks and status line from Claude Code's user settings.
#
#   ./scripts/uninstall.sh            remove (restores your previous status line)
#   ./scripts/uninstall.sh --purge    also delete ~/.cc-pulse
#
# Only entries whose command is pulse-hook.sh / pulse-statusline.sh are touched.

set -euo pipefail

purge=false
[[ "${1:-}" == "--purge" ]] && purge=true

pulse_home="${CC_PULSE_HOME:-$HOME/.cc-pulse}"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$claude_dir/settings.json"
chain_file="$pulse_home/statusline-chain"

command -v jq >/dev/null 2>&1 || { print -u2 "cc-pulse: jq is required"; exit 1; }

if [[ -f "$settings" ]]; then
  previous=""
  [[ -s "$chain_file" ]] && previous="$(<"$chain_file")"

  updated="$(jq --arg previous "$previous" '
    def ours: (.command // "") | test("pulse-(hook|statusline)\\.sh");
    (if .hooks then
      .hooks |= (with_entries(
        .value |= (map(.hooks |= map(select(ours | not))) | map(select((.hooks | length) > 0))))
        | with_entries(select((.value | length) > 0)))
     else . end)
    | (if .hooks == {} then del(.hooks) else . end)
    | (if (.statusLine | ours) then
        (if $previous != "" then .statusLine.command = $previous else del(.statusLine) end)
       else . end)
  ' "$settings")"

  cp "$settings" "$settings.bak-$(date +%Y%m%d-%H%M%S)"
  print -r -- "$updated" > "$settings.cc-pulse.tmp"
  mv -f "$settings.cc-pulse.tmp" "$settings"
  print "cc-pulse: removed hooks and status line from $settings"
fi

if $purge; then
  rm -rf "$pulse_home"
  print "cc-pulse: deleted $pulse_home"
fi
