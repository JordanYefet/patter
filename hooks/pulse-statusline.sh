#!/bin/zsh
# cc-pulse status line — feeds context-window and usage-limit data to CC Pulse.
#
# Claude Code only exposes context-window usage and the 5-hour / weekly rate
# limits to the status line command (not to hooks), so we register this script
# as the status line. It:
#   1. hands a copy of the status JSON to pulse-hook.sh (kind "status")
#   2. runs your previous status line command, if you had one, with the same
#      input, and prints its output — so your existing status line keeps working
#   3. otherwise prints a compact default line
#
# The installer saves your previous status line command to
# ~/.cc-pulse/statusline-chain.

here="${0:A:h}"
pulse_home="${CC_PULSE_HOME:-$HOME/.cc-pulse}"
chain_file="$pulse_home/statusline-chain"

input="$(cat)"

print -r -- "$input" | "$here/pulse-hook.sh" status

if [[ -s "$chain_file" ]]; then
  print -r -- "$input" | /bin/sh -c "$(<"$chain_file")"
  exit $?
fi

# Default line: model · context %. Kept dependency-free (no jq).
flat="${input//[[:space:]]/}"
model="Claude"
rest="${input#*\"display_name\":}"
if [[ "$rest" != "$input" ]]; then
  rest="${rest#"${rest%%[![:space:]]*}"}"   # trim leading whitespace
  rest="${rest#\"}"
  model="${rest%%\"*}"
fi
ctx="${flat#*\"context_window\":}"
pct=""
if [[ "$ctx" != "$flat" ]]; then
  pct="${${ctx#*\"used_percentage\":}%%[,\}]*}"
  [[ "$pct" == "$ctx" || "$pct" == null ]] && pct=""
fi
if [[ -n "$pct" ]]; then
  print -r -- "$model · ctx ${pct%%.*}%"
else
  print -r -- "$model"
fi
