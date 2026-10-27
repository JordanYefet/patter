# Patter

**A quick glimpse at your Claude Code sessions.** See what every session is doing without switching windows. Patter is a small native macOS app that shows your sessions in the menu bar, in a floating HUD, or around the MacBook notch. It shows which sessions are working, which are waiting on you, how far along their plans are, how full each context window is, and how much of your 5-hour and weekly limits you've used.

It's built entirely on Claude Code's official extension points, [hooks](https://code.claude.com/docs/en/hooks) and the [status line](https://code.claude.com/docs/en/statusline). It doesn't scrape terminals or read transcripts, and it makes no network calls.

> Unofficial community project, not affiliated with or endorsed by Anthropic.

## What you see

| Placement | Best for |
| --- | --- |
| **Menu bar** (always on) | The full picture: each session's project, branch, current action, task progress, context window, plus account usage at the top. The icon is Clawd, the Claude Code mascot: it walks while anything is working, stands still when done, gets a yellow badge with a count when sessions need you, and turns grey with a red "!" and a countdown when you've hit your 5-hour or weekly limit. |
| **Floating HUD** | A big single monitor. Always on top, never steals focus, drag it anywhere, collapse it to a pill. |
| **Notch** | Notched MacBooks. "Ears" grow out of the notch while sessions run, turn orange when one needs you, and the full list drops down on hover. |

Per session:

- **State**: *working*, *needs you* (permission prompt, question, or failure) or *idle*. "Needs you" always sorts first and always wins the icon.
- **What it's up to**, in the spirit of Claude Code's own spinner ("Pondering…", "Noodling…"), plus task progress and running subagents.
- **Progress** from Claude's own todo list, like 4/7 tasks. Claude doesn't know a percentage, so Patter doesn't invent one.
- **Context window** as a percentage. It turns orange at 80%, since auto-compaction is close.
- **Subagents** currently running.

Account-wide: **5-hour window** and **weekly** usage with reset times. These are only reported for Pro/Max subscriptions.

Notifications: when a session needs you, and when a turn longer than 30s (configurable) finishes. Clicking a session brings its terminal app to the front.

## Requirements

- macOS 14 Sonoma or later
- Claude Code with hooks support (any recent version)
- `jq` for the installer (bundled with macOS 15+; otherwise `brew install jq`)
- Swift 6 (Xcode 16+, or just the Command Line Tools: `xcode-select --install`). Tests use Swift Testing, so full Xcode is not required

## Install

```sh
git clone https://github.com/<you>/patter.git
cd patter

# 1. Register the hooks and status line in ~/.claude/settings.json (backed up first)
./scripts/install.sh            # or --dry-run to preview the change

# 2. Build and launch the app
./scripts/bundle.sh --install   # -> ~/Applications/Patter.app
```

Restart any running `claude` sessions so they pick up the new hooks.

If you already had a status line, it keeps working. The installer saves your command to `~/.patter/statusline-chain`, and Patter's status line script runs it with the same input and prints its output.

Upgrading from CC Pulse (Patter's old name)? Just run `./scripts/install.sh`. It replaces the old hooks, carries over your status line and removes `~/.cc-pulse`.

### Uninstall

```sh
./scripts/uninstall.sh          # removes only Patter's entries, restores your status line
./scripts/uninstall.sh --purge  # also deletes ~/.patter
rm -rf ~/Applications/"Patter.app"
```

## How it works

```
 Claude Code session(s)                        ~/.patter/spool/              Patter.app
 ┌──────────────────────┐   hook events        ┌──────────────────────┐      ┌────────────────────────┐
 │ UserPromptSubmit     │──► patter-hook.sh ──►│ 1793…795-4242.hook   │─────►│ SpoolReader (watch dir) │
 │ PreToolUse / Post…   │    (async, ~2 ms)    │ 1793…812-4243.status │      │ SessionStore (state     │
 │ PermissionRequest    │                      │ …one JSON per event  │      │   machine, pure Swift)  │
 │ Stop / SessionEnd …  │   status line        └──────────────────────┘      │ Menu bar · HUD · Notch  │
 │ status line refresh  │──► patter-statusline.sh ─┘  (files deleted         └────────────────────────┘
 └──────────────────────┘    (+ your old one)         once read)
```

1. **Hooks**: `patter-hook.sh` is registered as an `async` command hook for 14 events. It wraps the JSON payload from stdin in a small envelope (timestamp, Claude's PID, `$TERM_PROGRAM`) and writes it atomically into the spool. It doesn't parse anything, needs no dependencies, and always exits 0, so it can never block or break Claude.
2. **Status line**: context-window and rate-limit data is only given to the status line command, so `patter-statusline.sh` sends a copy to the spool and then runs your previous status line.
3. **App**: watches the spool folder, applies events in timestamp order to a pure state machine (`PatterCore`), deletes the files, and renders.

Why files and not a local HTTP server? Hooks keep working whether or not the app is running. When it starts, it catches up on the sessions that are already running. There's no port, no auth, and nothing listening on your machine.

The event-to-state table is in [docs/architecture.md](docs/architecture.md).

## Privacy and security

- **Local only.** No network access, no telemetry. Event data lives in `~/.patter/spool` for milliseconds while the app is running, and is deleted after it's read.
- **Read-only toward Claude.** The hooks are `async`, so they can't approve, deny or change anything. Patter deliberately doesn't offer remote approval of permission prompts.
- **What's stored:** hook payloads include tool inputs, such as commands and file paths. They're written only to your home directory and deleted on read. If the app isn't running they accumulate until it next starts. Delete them with `rm ~/.patter/spool/*`.
- **Review before installing.** `hooks/patter-hook.sh` is short and has no dependencies. Reading it is the best way to trust it.

## Development

```sh
swift build                 # app + core
./scripts/test.sh           # PatterCore unit tests (`swift test`, works without Xcode)
swift run Patter           # run without bundling (no notifications / launch-at-login)
./scripts/test-scripts.sh   # installer + hook script tests (needs zsh, jq)
```

Layout:

```
hooks/                  the two scripts Claude Code runs
scripts/                install / uninstall / bundle / app icon
Sources/PatterCore/     Foundation-only: event parsing, SessionStore, formatting
Sources/Patter/         SwiftUI/AppKit app: menu bar, HUD, notch, notifications
Tests/PatterCoreTests/  Swift Testing
docs/                   architecture and event mapping
```

To test without Claude, drop a file into the spool:

```sh
print -r '{"session_id":"demo","hook_event_name":"UserPromptSubmit","cwd":"'$PWD'"}' | hooks/patter-hook.sh
```

## Roadmap

- [ ] Focus the exact terminal tab or pane (iTerm2, Terminal, Ghostty via AppleScript) instead of just the app
- [ ] Show the first line of the last prompt per session
- [ ] Homebrew cask and signed, notarized releases
- [ ] Per-project colors and nicknames
- [ ] Sound per state
- [ ] Claude Code plugin packaging for one-step hook install

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT © 2026 Jordan Yefet
