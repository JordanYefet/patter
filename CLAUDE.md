# CC Pulse — notes for Claude Code

macOS menu bar / HUD / notch app that shows Claude Code session status, fed by async hooks.

## Commands

- `swift build` / `swift test`: build everything, test `PulseCore`
- `./tests/scripts/test_scripts.sh`: installer + hook script tests (zsh, jq)
- `./scripts/bundle.sh --install`: build `CC Pulse.app` and open it
- `./scripts/install.sh --dry-run`: preview the settings.json change

## Rules

- `PulseCore` is Foundation-only (no AppKit/SwiftUI) and must stay pure: every state transition lives in `SessionStore.apply` and gets a unit test.
- The hook script must stay dependency-free and always `exit 0`. It must never block Claude.
- Parse payloads with `JSONObject` accessors and treat every field as optional.
- When you add or change an event mapping, update the table in `docs/architecture.md`.
- Colors come from `Theme.swift` only.
