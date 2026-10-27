# Architecture

CC Pulse has three parts with one-way data flow:

```
hooks/pulse-hook.sh, hooks/pulse-statusline.sh   (run by Claude Code)
        │  one JSON file per event
        ▼
~/.cc-pulse/spool/<µs-timestamp>-<pid>.<hook|status>.json
        │  DispatchSource directory watch + 2 s fallback tick
        ▼
PulseCore.SpoolReader → SessionStore.apply(event) → [PulseEffect]
        │                         │
        ▼                         ▼
   AppModel (@Published)     Notifier (UserNotifications)
        │
        ▼
 MenuBarExtra · HUD panel · Notch panel
```

## Spool file format

Written by `pulse-hook.sh`:

```json
{
  "_pulse": { "v": 1, "ts": 1793106794106795, "pid": 4242, "kind": "hook", "term": "iTerm.app" },
  "payload": { "session_id": "…", "hook_event_name": "PreToolUse", "cwd": "…", "tool_name": "Bash", "tool_input": { … } }
}
```

| Field | Meaning |
| --- | --- |
| `ts` | Microseconds since the epoch, taken when the hook started. Used for ordering and as the event time. |
| `pid` | Claude Code's process ID (parent, or grandparent if the hook ran via a shell). Used to drop sessions that crashed without `SessionEnd`. |
| `kind` | `hook` for hook events, `status` for status line snapshots. |
| `term` | `$TERM_PROGRAM`, sanitized. Used to bring the right terminal app forward. |
| `payload` | Claude Code's stdin JSON, untouched. |

Files are written to a dotfile first and then `mv`'d, so the reader never sees a partial file. The reader skips dotfiles.

## Event → state

| Event | Effect on the session | Notification |
| --- | --- | --- |
| `SessionStart` | Created as **idle**. `source: clear` resets tasks and context. | |
| `UserPromptSubmit` | → **working**, starts the turn timer, activity "Thinking…", clears attention. Finished task lists are cleared. | |
| `PreToolUse` | → **working** (unless waiting on you), activity from the tool, e.g. "Editing values.yaml". `TodoWrite` updates progress. | |
| `PermissionRequest` | → **needs you**: "Allow Bash" + the command or path. | ✅ needs you |
| `Notification` (`permission_prompt`) | → **needs you**, unless `PermissionRequest` already did it. | ✅ (once) |
| `Notification` (`elicitation_dialog`, `agent_needs_input`, …) | → **needs you** with Claude's message. | ✅ |
| `PostToolUse` / `PostToolUseFailure` | → **working**. A pending permission was answered. | |
| `SubagentStart` / `SubagentStop` | Subagent count ±1. | |
| `TaskCreated` / `TaskCompleted` | Task progress total / done +1. | |
| `PreCompact` | Activity "Compacting context…". | |
| `Stop` | → **idle**, records the turn duration, resets subagents, re-reads the git branch. | ✅ finished, if the turn ran ≥ 30 s |
| `StopFailure` | → **needs you**: "Stopped: rate limit" etc. | ✅ |
| `SessionEnd` | Removed. | |
| status line snapshot | Context window (%, tokens, size), model. Account-wide 5-hour / weekly limits, newest snapshot wins. | |

Sessions are also removed when their Claude Code PID is gone and they've been silent for 2 minutes, or after 12 hours of silence.

## Why these choices

- **Async hooks.** Hooks are on the hot path of every tool call. `async: true` means Claude never waits on CC Pulse, and async hooks can't block or approve anything. CC Pulse is an observer by construction.
- **No parsing in the hook.** Parsing would need `jq` (or Python) at runtime and makes every tool call slower. The Swift side parses loosely (`JSONObject`), so new or missing fields from future Claude Code versions don't break it.
- **Files over a socket.** The app can be stopped, restarted or crash without losing state from running sessions, and hooks never fail on "connection refused".
- **Pure core.** `SessionStore` has no timers or I/O except an injectable git lookup, so the whole state machine is covered by unit tests that run on any platform with Swift.
- **No percentage bar.** Claude doesn't know how long a task will take. Todo-list progress (done/total) is the only honest progress signal.
