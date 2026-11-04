# Agenty

A small macOS menu-bar app that shows how much of your Claude and Codex subscription limits you have used (the 5-hour session, the weekly window and per-model windows) and when they reset.

<!-- screenshot: docs/images/popover.png — add after first manual run -->

## Features

- Menu-bar glyph in three styles (bars, a single ring, or one per provider) so you can see at a glance whether a limit is close.
- Popover with every window, its percentage and its reset time.
- Notifications at 80% and 95% (configurable) and when a limit resets.
- Launch at login and a configurable refresh interval.
- English and Vietnamese UI.

## Supported providers

| Provider | Status |
|---|---|
| Claude (Claude Code) | Supported |
| Codex (Codex CLI) | Supported |

## Requirements

- macOS 27 on Apple Silicon (arm64 only)
- Signed in to the CLIs you want to track: `claude` and `codex`

## Warning: unofficial APIs

Agenty relies on endpoints and methods that are not public, documented APIs: `/api/oauth/usage` (Claude) and `codex app-server` (Codex). They can change or break at any time without notice.

## Privacy

- Your tokens never leave your machine, except in the single request sent to `api.anthropic.com` to read your Claude usage.
- The app never refreshes tokens. Claude Code refreshes its own login; if it has expired, open Claude Code once.
- The app never reads `~/.codex/auth.json`. Codex is queried only through its own CLI, which manages its own credentials.
- The app never sends prompts to any model.
- Credentials are only read, never written or logged.

## First run: Keychain prompt

The first time Agenty reads Claude Code's credentials from the Keychain, macOS asks for permission. Choose **Always Allow** so it does not ask again.

"Always Allow" is remembered per app signature. Every new release build is ad-hoc signed, so macOS may ask again after you update. If you click **Deny**, the app stops asking and shows "Keychain access denied" in the popover until you press **Retry** or relaunch the app.

## Install

Download the zip from the Releases page, unzip it and move `Agenty.app` to Applications. The app is ad-hoc signed, not notarized, so macOS Gatekeeper blocks the first launch. On macOS 15 and later, right-click → Open no longer bypasses it. Instead, try to open the app once, then go to System Settings › Privacy & Security and click **Open Anyway**. Or remove the quarantine flag from a terminal:

```sh
xattr -dr com.apple.quarantine /path/to/Agenty.app
```

## Build from source

```sh
brew install xcodegen && xcodegen generate && open Agenty.xcodeproj
```

Run the core tests with:

```sh
swift test --package-path Packages/UsageCore
```

After changing UI strings, regenerate the String Catalog entries and add a Vietnamese (`vi`) translation, state `translated`, for every new key. Build first, then sync from the build's `.stringsdata` files:

```sh
xcrun xcstringstool sync App/Resources/Localizable.xcstrings \
  --stringsdata build/DerivedData/Build/Intermediates.noindex/Agenty.build/Debug/Agenty.build/Objects-normal/arm64/*.stringsdata
```

Build a release zip with `scripts/build-release.sh <version>`; the result is in `build/`.

## License

MIT. See [LICENSE](LICENSE).
