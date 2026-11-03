# LLMUsage

A small macOS menu-bar app that shows how much of your Claude and Codex subscription limits you have used (the 5-hour session, the weekly window and per-model windows) and when they reset.

<!-- screenshot: docs/images/popover.png — add after first manual run -->

## Features

- Menu-bar glyph in three styles (bars, rings, or one per provider) so you can see at a glance whether a limit is close.
- Popover with every window, its percentage and its reset time.
- Notifications at 80% and 95% (configurable) and when a limit resets.
- Launch at login and a configurable refresh interval.
- English and Vietnamese UI.

## Supported providers

| Provider | Status |
|---|---|
| Claude (Claude Code) | Supported |
| Codex (Codex CLI) | Supported |
| Grok (Grok CLI) | In progress, waiting on a captured real-world response fixture |

## Requirements

- macOS 27 on Apple Silicon (arm64 only)
- Signed in to the CLIs you want to track: `claude`, `codex` (and `grok` once supported)

## Warning: unofficial APIs

LLMUsage relies on endpoints and methods that are not public, documented APIs: `/api/oauth/usage` (Claude), `codex app-server` (Codex) and `_x.ai/billing` (Grok). They can change or break at any time without notice.

## Privacy

- Your tokens never leave your machine, except in the single request sent to `api.anthropic.com` to read your Claude usage.
- The app never refreshes tokens. Claude Code refreshes its own login; if it has expired, open Claude Code once.
- The app never reads `~/.codex/auth.json` or `~/.grok/auth.json`. Codex and Grok are queried only through their own CLIs, which manage their own credentials.
- The app never sends prompts to any model.
- Credentials are only read, never written or logged.

## First run: Keychain prompt

The first time LLMUsage reads Claude Code's credentials from the Keychain, macOS asks for permission. Choose **Always Allow** so it does not ask again.

## Install

Download the zip from the Releases page, unzip it and move `LLMUsage.app` to Applications. The app is ad-hoc signed, not notarized, so on first launch right-click it and choose Open.

## Build from source

```sh
brew install xcodegen && xcodegen generate && open LLMUsage.xcodeproj
```

Run the core tests with:

```sh
swift test --package-path Packages/UsageCore
```

Build a release zip with `scripts/build-release.sh <version>`; the result is in `build/`.

## License

MIT. See [LICENSE](LICENSE).
