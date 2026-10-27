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
spool="$HOME/.cc-pulse/spool"

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
check "hooks are async" '[[ $(jq "[.hooks[][].hooks[] | select(.command | test(\"pulse-hook\")) | .async] | all" "$settings") == true ]]'
check "status line is ours" '[[ $(jq -r .statusLine.command "$settings") == *pulse-statusline.sh ]]'
check "status line padding kept" '[[ $(jq .statusLine.padding "$settings") == 0 ]]'
check "previous status line chained" '[[ $(<"$HOME/.cc-pulse/statusline-chain") == "echo mine" ]]'
check "settings backed up" '[[ -n $(print -l "$settings".bak-*(N)) ]]'

print "hook"
print -r '{"session_id":"s1","hook_event_name":"UserPromptSubmit"}' | TERM_PROGRAM='iTerm.app"; rm -rf /' "$HOME/.cc-pulse/bin/pulse-hook.sh"
check "exits 0 on empty stdin" 'print -n "" | "$HOME/.cc-pulse/bin/pulse-hook.sh"'
files=("$spool"/*.hook.json(N))
check "writes one file per event" '(( ${#files} == 2 ))'
check "envelope is valid JSON" 'jq -e "._pulse.ts and .payload.session_id == \"s1\"" "${files[1]}" >/dev/null'
check "timestamp fits in Int64 (µs)" '(( ${#$(jq -r ._pulse.ts "${files[1]}")} == 16 ))'
check "terminal name is sanitized" '[[ $(jq -r ._pulse.term "${files[1]}") == "iTerm.apprm-rf" ]]'
check "empty stdin becomes null payload" '[[ $(jq -r .payload "${files[2]}") == null ]]'
check "no temp files left" '[[ -z $(print -l "$spool"/.tmp*(N)) ]]'
check "exits 0 when spool is unwritable" 'chmod 000 "$spool"; print "{}" | CC_PULSE_HOME=/nonexistent/x "$HOME/.cc-pulse/bin/pulse-hook.sh"; r=$?; chmod 755 "$spool"; (( r == 0 ))'

print "status line"
input='{"session_id":"s1","model":{"display_name":"Opus 5"},"rate_limits":{"five_hour":{"used_percentage":38}},"context_window":{"used_percentage": 62.4}}'
check "chains previous status line" '[[ $(print -r -- "$input" | "$HOME/.cc-pulse/bin/pulse-statusline.sh") == mine ]]'
check "writes a status file" '[[ -n $(print -l "$spool"/*.status.json(N)) ]]'
mv "$HOME/.cc-pulse/statusline-chain" "$HOME/chain.bak"
check "default line uses context %, not rate limit %" '[[ $(print -r -- "$input" | "$HOME/.cc-pulse/bin/pulse-statusline.sh") == "Opus 5 · ctx 62%" ]]'
mv "$HOME/chain.bak" "$HOME/.cc-pulse/statusline-chain"

print "uninstall"
zsh "$repo/scripts/uninstall.sh" >/dev/null
check "removes our hooks, keeps user hooks" '[[ $(jq -c .hooks "$settings") == "{\"PreToolUse\":[{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"/usr/local/bin/guard.sh\"}]}]}" ]]'
check "restores previous status line" '[[ $(jq -r .statusLine.command "$settings") == "echo mine" ]]'

print "dry run"
cp "$settings" "$HOME/before.json"
zsh "$repo/scripts/install.sh" --dry-run >/dev/null 2>&1
check "dry run changes nothing" 'cmp -s "$settings" "$HOME/before.json"'

print
if (( failures )); then print "$failures failure(s)"; exit 1; fi
print "all passed"
