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

Tests use Swift Testing (`@Suite`, `@Test`, `#expect`), and `--filter <Suite>` selects a suite. Fakes live in `Tests/UsageCoreTests/Support` and JSON fixtures in `Tests/UsageCoreTests/Fixtures`, loaded with `fixture("name")`.

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
- `xcodebuild` also rewrites `Packages/UsageCore/Package.resolved`: it adds an unrelated Sparkle pin, or changes only the `originHash` line. When the diff is only that, `git checkout -- Packages/UsageCore/Package.resolved` restores the file. Its real pins are swift-subprocess, swift-system and Yams.
- `App/Info.plist` is generated from `project.yml` and tracked. CI runs `xcodegen generate` and fails when `App/Info.plist` then differs.

## Scripts

- CI lints with ShellCheck 0.11.0, and other versions report different warnings: `pipx run --spec shellcheck-py==0.11.0.1 shellcheck scripts/*.sh`.
- Each test script runs on its own, because `bash scripts/test-*.sh` would run only the first file: `(for t in scripts/test-*.sh; do bash "$t" || exit 1; done)`.
- `test-build-settings.sh` needs the generated project. `test-build-release.sh` and `test-make-appcast.sh` need macOS.

## Conventions

- UI follows `DESIGN.md`. Read it before changing a view.
- Every key in `App/Resources/Localizable.xcstrings` has a `vi` translation with state `translated`. English comes from the key, and `xcstringstool sync` manages any `en` entries. After a build, add new keys with the sync command in the README. Without a build, add each entry by hand in the shape of its neighbours.
- Credentials are only read, never written or logged. Codex and Grok are reached only through their CLIs, never their `auth.json`. The README's Privacy section is the contract.

## Real user files

Tests and checks run against a temporary home, never the real `~/.claude`, `~/.codex` or `~/.grok`.

- Integration tests that run the real `codex` pass a temporary `codexHome`.
- Tests reach `grok` only through fakes. A live `grok agent` deletes its `auth.json` when the token has expired and the refresh is rejected.
- `CFFIXED_USER_HOME` moves the app's own file paths but leaves `HOME` unchanged for the CLIs it spawns. To launch Agenty Dev on temporary files, quit it first, because a running app ignores `open --env`, then run:

  ```sh
  open --env CFFIXED_USER_HOME=<tmp> --env CODEX_HOME=<tmp>/.codex --env GROK_HOME=<tmp>/.grok "<app path>"
  ```

  `claude plugin list`, which the Config page runs, still uses the real home, and the Claude login still comes from the real Keychain.
- Each build gets a new ad-hoc signature, so launching it with Claude enabled can put a Keychain dialog on the user's screen.
