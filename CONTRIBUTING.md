# Contributing

Thanks for helping. A few ground rules keep CC Pulse trustworthy enough to run on every tool call:

1. **The hook stays tiny.** `hooks/pulse-hook.sh` must stay dependency-free, never parse, never touch the network, and always exit 0. Logic belongs in `PulseCore`.
2. **Observer only.** CC Pulse never approves, denies or changes what Claude does. Features that need a blocking hook are out of scope.
3. **State changes go through `SessionStore` and come with a test.** It's pure on purpose: add a case to `Tests/PulseCoreTests/SessionStoreTests.swift` for any new event or transition, and update the table in `docs/architecture.md`.
4. **Parse loosely.** Claude Code adds fields often. Use `JSONObject` accessors, and treat every field as optional.

## Setup

```sh
swift build && swift test
./scripts/test-scripts.sh
swift run CCPulse
```

Pull requests run the same checks on a macOS runner (`.github/workflows/ci.yml`).

## Reporting a bug

Please include your macOS version, `claude --version`, which placement you use (menu bar, HUD or notch), and, if the state looks wrong, the spool files that caused it (`~/.cc-pulse/spool`). Quit the app first so they aren't deleted, and redact any commands or paths you don't want to share.
