#!/bin/zsh
# Remove Patter's hooks and status line from Claude Code's user settings.
#
#   ./scripts/uninstall.sh            remove (restores your previous status line)
#   ./scripts/uninstall.sh --purge    also delete ~/.patter
#
# Only entries whose command is patter-hook.sh / patter-statusline.sh, or
# pulse-hook.sh / pulse-statusline.sh from when Patter was called CC Pulse,
# are touched. A leftover ~/.cc-pulse is always removed.

set -euo pipefail

purge=false
[[ "${1:-}" == "--purge" ]] && purge=true

patter_home="${PATTER_HOME:-$HOME/.patter}"
legacy_home="${CC_PULSE_HOME:-$HOME/.cc-pulse}"
claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$claude_dir/settings.json"

command -v jq >/dev/null 2>&1 || { print -u2 "patter: jq is required"; exit 1; }

if [[ -f "$settings" ]]; then
  # The status line to restore, from whichever install chained it.
  previous=""
  for chain_file in "$patter_home/statusline-chain" "$legacy_home/statusline-chain"; do
    if [[ -s "$chain_file" ]]; then previous="$(<"$chain_file")"; break; fi
  done

  updated="$(jq --arg previous "$previous" '
    def ours: (.command // "") | test("(patter|pulse)-(hook|statusline)\\.sh");
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
  print -r -- "$updated" > "$settings.patter.tmp"
  mv -f "$settings.patter.tmp" "$settings"
  print "patter: removed hooks and status line from $settings"
fi

if [[ -d "$legacy_home" && "${legacy_home:A}" != "${patter_home:A}" ]]; then
  rm -rf "$legacy_home"
  print "patter: deleted the old CC Pulse directory $legacy_home"
fi

if $purge; then
  rm -rf "$patter_home"
  print "patter: deleted $patter_home"
fi
