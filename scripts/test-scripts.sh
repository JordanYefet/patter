#!/bin/zsh
# Tests for the hook, status line, installer and uninstaller.
# Runs in a throwaway $HOME; never touches your real settings. Needs zsh + jq.

set -uo pipefail

repo="${0:A:h:h}"
failures=0

pass() { print "  ok   $1" }
fail() { print "  FAIL $1"; (( failures++ )) }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi }

export HOME="$(mktemp -d)"
trap 'rm -rf "$HOME"' EXIT
mkdir -p "$HOME/.claude"
settings="$HOME/.claude/settings.json"
spool="$HOME/.patter/spool"

print "install"
cat > "$settings" <<'EOF'
{"model":"opus",
 "statusLine":{"type":"command","command":"echo mine","padding":0},
 "hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/guard.sh"}]}]}}
EOF
zsh "$repo/scripts/install.sh" >/dev/null
zsh "$repo/scripts/install.sh" >/dev/null   # idempotent

check "keeps unrelated settings" '[[ $(jq -r .model "$settings") == opus ]]'
check "keeps user hooks" '[[ $(jq "[.hooks.PreToolUse[].hooks[].command] | index(\"/usr/local/bin/guard.sh\")" "$settings") != null ]]'
check "registers 14 events" '[[ $(jq ".hooks | keys | length" "$settings") == 14 ]]'
check "no duplicate entries after re-install" '[[ $(jq "[.hooks.Stop[].hooks[]] | length" "$settings") == 1 ]]'
check "hooks are async" '[[ $(jq "[.hooks[][].hooks[] | select(.command | test(\"patter-hook\")) | .async] | all" "$settings") == true ]]'
check "status line is ours" '[[ $(jq -r .statusLine.command "$settings") == *patter-statusline.sh ]]'
check "status line padding kept" '[[ $(jq .statusLine.padding "$settings") == 0 ]]'
check "previous status line chained" '[[ $(<"$HOME/.patter/statusline-chain") == "echo mine" ]]'
check "settings backed up" '[[ -n $(print -l "$settings".bak-*(N)) ]]'

print "hook"
print -r '{"session_id":"s1","hook_event_name":"UserPromptSubmit"}' | TERM_PROGRAM='iTerm.app"; rm -rf /' "$HOME/.patter/bin/patter-hook.sh"
check "exits 0 on empty stdin" 'print -n "" | "$HOME/.patter/bin/patter-hook.sh"'
files=("$spool"/*.hook.json(N))
check "writes one file per event" '(( ${#files} == 2 ))'
check "envelope is valid JSON" 'jq -e "._patter.ts and .payload.session_id == \"s1\"" "${files[1]}" >/dev/null'
check "timestamp fits in Int64 (µs)" '(( ${#$(jq -r ._patter.ts "${files[1]}")} == 16 ))'
check "terminal name is sanitized" '[[ $(jq -r ._patter.term "${files[1]}") == "iTerm.apprm-rf" ]]'
check "empty stdin becomes null payload" '[[ $(jq -r .payload "${files[2]}") == null ]]'
check "no temp files left" '[[ -z $(print -l "$spool"/.tmp*(N)) ]]'
check "exits 0 when spool is unwritable" 'chmod 000 "$spool"; print "{}" | PATTER_HOME=/nonexistent/x "$HOME/.patter/bin/patter-hook.sh"; r=$?; chmod 755 "$spool"; (( r == 0 ))'

print "status line"
input='{"session_id":"s1","model":{"display_name":"Opus 5"},"rate_limits":{"five_hour":{"used_percentage":38}},"context_window":{"used_percentage": 62.4}}'
check "chains previous status line" '[[ $(print -r -- "$input" | "$HOME/.patter/bin/patter-statusline.sh") == mine ]]'
check "writes a status file" '[[ -n $(print -l "$spool"/*.status.json(N)) ]]'
mv "$HOME/.patter/statusline-chain" "$HOME/chain.bak"
check "default line uses context %, not rate limit %" '[[ $(print -r -- "$input" | "$HOME/.patter/bin/patter-statusline.sh") == "Opus 5 · ctx 62%" ]]'
mv "$HOME/chain.bak" "$HOME/.patter/statusline-chain"

print "uninstall"
zsh "$repo/scripts/uninstall.sh" >/dev/null
check "removes our hooks, keeps user hooks" '[[ $(jq -c .hooks "$settings") == "{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"/usr/local/bin/guard.sh\"}]}]}" ]]'
check "restores previous status line" '[[ $(jq -r .statusLine.command "$settings") == "echo mine" ]]'

print "dry run"
cp "$settings" "$HOME/before.json"
zsh "$repo/scripts/install.sh" --dry-run >/dev/null 2>&1
check "dry run changes nothing" 'cmp -s "$settings" "$HOME/before.json"'

# An install from when Patter was called CC Pulse, in its own throwaway HOME:
# old hooks and status line in settings.json, and a ~/.cc-pulse directory.
legacy_install() {
  local home="$1"
  mkdir -p "$home/.claude" "$home/.cc-pulse/bin" "$home/.cc-pulse/spool"
  print -r -- "echo mine" > "$home/.cc-pulse/statusline-chain"
  print -r -- '{}' > "$home/.cc-pulse/spool/1-1.hook.json"
  cat > "$home/.claude/settings.json" <<EOF
{"model":"opus",
 "statusLine":{"type":"command","command":"$home/.cc-pulse/bin/pulse-statusline.sh"},
 "hooks":{
  "PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/guard.sh"}]},
                {"matcher":"*","hooks":[{"type":"command","command":"$home/.cc-pulse/bin/pulse-hook.sh","async":true,"timeout":10}]}],
  "Stop":[{"hooks":[{"type":"command","command":"$home/.cc-pulse/bin/pulse-hook.sh","async":true,"timeout":10}]}]}}
EOF
}

print "migrate from CC Pulse"
old_home="$HOME/legacy"
old_settings="$old_home/.claude/settings.json"
legacy_install "$old_home"
cp "$old_settings" "$HOME/legacy-before.json"
HOME="$old_home" zsh "$repo/scripts/install.sh" --dry-run >/dev/null 2>&1
check "dry run leaves settings alone" 'cmp -s "$old_settings" "$HOME/legacy-before.json"'
check "dry run keeps ~/.cc-pulse" '[[ -s "$old_home/.cc-pulse/statusline-chain" ]]'
check "dry run creates no ~/.patter" '[[ ! -e "$old_home/.patter" ]]'
HOME="$old_home" zsh "$repo/scripts/install.sh" >/dev/null
HOME="$old_home" zsh "$repo/scripts/install.sh" >/dev/null   # idempotent after migrating
check "no CC Pulse entries left" '[[ $(jq "[.. | .command? // empty | select(test(\"pulse-\"))] | length" "$old_settings") == 0 ]]'
check "old entries replaced, not duplicated" '[[ $(jq "[.hooks.Stop[].hooks[]] | length" "$old_settings") == 1 && $(jq "[.hooks.PreToolUse[].hooks[] | select(.command | test(\"patter-hook\"))] | length" "$old_settings") == 1 ]]'
check "keeps user hooks when migrating" '[[ $(jq "[.hooks.PreToolUse[].hooks[].command] | index(\"/usr/local/bin/guard.sh\")" "$old_settings") != null ]]'
check "status line moves to Patter" '[[ $(jq -r .statusLine.command "$old_settings") == "$old_home/.patter/bin/patter-statusline.sh" ]]'
check "chained status line carried over" '[[ $(<"$old_home/.patter/statusline-chain") == "echo mine" ]]'
check "chained status line still runs" '[[ $(print -r -- "$input" | HOME="$old_home" "$old_home/.patter/bin/patter-statusline.sh") == mine ]]'
check "removes ~/.cc-pulse" '[[ ! -e "$old_home/.cc-pulse" ]]'

print "uninstall a CC Pulse install"
old_home="$HOME/legacy-uninstall"
old_settings="$old_home/.claude/settings.json"
legacy_install "$old_home"
HOME="$old_home" zsh "$repo/scripts/uninstall.sh" >/dev/null
check "removes CC Pulse hooks, keeps user hooks" '[[ $(jq -c .hooks "$old_settings") == "{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"/usr/local/bin/guard.sh\"}]}]}" ]]'
check "restores status line from the CC Pulse chain" '[[ $(jq -r .statusLine.command "$old_settings") == "echo mine" ]]'
check "removes ~/.cc-pulse on uninstall" '[[ ! -e "$old_home/.cc-pulse" ]]'

print
if (( failures )); then print "$failures failure(s)"; exit 1; fi
print "all passed"
