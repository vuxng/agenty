# Agenty

A macOS 27 menu bar app with a main window: SwiftUI, Swift 6 with complete strict concurrency, arm64 only. `README.md` covers features, privacy, and the branch and release flow. `DESIGN.md` is the design language.

## Layout

- `Packages/UsageCore`: all logic and all tests (providers, config backends, the store). It builds and tests with SwiftPM alone.
- `App/`: the SwiftUI app. It compiles only through `Agenty.xcodeproj`, which XcodeGen generates from `project.yml` and git ignores.
- `scripts/`: release scripts and their `test-*.sh` tests.
- `docs/superpowers/`: one spec and one plan per feature, plus spikes, mostly in Vietnamese.

## Test

```sh
swift test --package-path Packages/UsageCore
```

Tests use Swift Testing (`@Suite`, `@Test`, `#expect`). Fakes live in `Tests/UsageCoreTests/Support` and JSON fixtures in `Tests/UsageCoreTests/Fixtures`, loaded with `fixture("name")`. Write the test first and watch it fail. Iterate with `--filter <Suite>`, then finish with one full run.

Inside a sandbox, plain `swift test` fails on `~/.cache/clang/ModuleCache`. Run it from `Packages/UsageCore` with local caches:

```sh
B="$PWD/.build/job-cache"; mkdir -p "$B"
CLANG_MODULE_CACHE_PATH="$B/clang" SWIFTPM_MODULECACHE_OVERRIDE="$B/swiftpm" XDG_CACHE_HOME="$B/xdg" \
  swift test --disable-sandbox --cache-path "$B/cache" --config-path "$B/config" \
  --security-path "$B/security" --manifest-cache local
```

Parallel runs can stall inside a sandbox, and `--no-parallel` avoids that.

## Build

```sh
xcodegen generate
xcodebuild -project Agenty.xcodeproj -scheme Agenty -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build
```

A good build prints `** BUILD SUCCEEDED **`. Debug builds are Agenty Dev (`io.github.vuxng.Agenty.dev`), at `build/DerivedData/Build/Products/Debug/Agenty Dev.app`, and run beside an installed Agenty.

- `xcodebuild` cannot resolve packages inside the Codex sandbox, so `App/` code compiles only outside it.
- Every `xcodebuild` writes an unrelated Sparkle pin, or only a new `originHash` line, into `Packages/UsageCore/Package.resolved`. Run `git checkout -- Packages/UsageCore/Package.resolved` before committing.
- `App/Info.plist` is generated from `project.yml` but committed. After changing `info` in `project.yml`, run `xcodegen generate` and commit both files, because CI fails when they drift.
- Scripts pass ShellCheck 0.11 (`shellcheck scripts/*.sh`) and their `bash scripts/test-*.sh`.

## Conventions

- UI follows `DESIGN.md`. Read it before changing a view.
- Every user-facing string has an `en` and a `vi` entry, state `translated`, in `App/Resources/Localizable.xcstrings`. After a build, sync new keys with the `xcstringstool` command in the README. Without a build, add each entry by hand in the shape of its neighbours.
- Credentials are only read, never written or logged. Codex and Grok are reached only through their CLIs, never their `auth.json`. The README's Privacy section is the contract.

## Real user files

Tests and checks run against a temporary home, never the real `~/.claude`, `~/.codex` or `~/.grok`.

- Integration tests that run the real `codex` pass a temporary `codexHome`.
- Tests reach `grok` only through fakes. A live `grok agent` deletes `~/.grok/auth.json` when its token has expired and the refresh is rejected.
- `CFFIXED_USER_HOME` leaves `HOME` unchanged for child processes. To launch Agenty Dev on temporary files, quit it first, because a running app ignores `open --env`, then run `open --env CFFIXED_USER_HOME=<tmp> --env CODEX_HOME=<tmp>/.codex "<app path>"`.
- Each build gets a new ad-hoc signature, so launching it with Claude enabled can put a Keychain dialog on the user's screen.
