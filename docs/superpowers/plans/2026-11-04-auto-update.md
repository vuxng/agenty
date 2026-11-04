# Agenty Auto-Update (Sparkle) + v0.2.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agenty checks for updates daily with Sparkle 2 and installs them after asking. Release it as v0.2.0.

**Architecture:**
- **App:** a thin `Updater` wraps `SPUStandardUpdaterController` and implements gentle reminders. Settings and the popover read from it.
- **Signing:** `build-release.sh` re-signs Sparkle's helpers with Developer ID, inside out.
- **Release:** the workflow writes the notes, signs a one-item `appcast.xml` (checked against `SUPublicEDKey` with CryptoKit), and attaches it to the GitHub Release. The app reads it from `releases/latest/download/appcast.xml`.

**Tech Stack:** Swift 6 / SwiftUI (macOS 27), Sparkle 2.10.1 via SPM (XcodeGen), bash scripts tested against stub toolchains, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-04-auto-update-design.md`

## Global Constraints

**Platform and dependencies**
- macOS 27 only, arm64 only, `SWIFT_STRICT_CONCURRENCY: complete`, hardened runtime, no sandbox.
- Sparkle `exactVersion: 2.10.1`. It is linked into the `Agenty` target only; `UsageCore` is unchanged.

**Feed and keys**
- Feed URL: `https://github.com/vuxng/agenty/releases/latest/download/appcast.xml`.
- Enclosure URL: `https://github.com/vuxng/agenty/releases/download/v<version>/Agenty-<version>-arm64.zip`.
- Keychain account for the EdDSA key: `io.github.vuxng.Agenty`. GitHub secret: `SPARKLE_ED_PRIVATE_KEY`, in environment `release`.
- The private key travels only through stdin. Never put it in arguments, stdout, logs or the chat, and never use `set -x` near it.

**Signing**
- Developer ID signing never uses `--deep`.
- Every helper is signed with `-o runtime --timestamp`, plus `--keychain "$SIGN_KEYCHAIN"` when it is set.

**Code and copy**
- Every new UI string goes into `App/Resources/Localizable.xcstrings` with a `vi` translation (all 62 existing keys have one).
- Scripts pass ShellCheck 0.11.0 and workflows pass `actionlint`.

**Git**
- Work on branch `feat/auto-update`; PRs go into `next` (squash).
- No `Co-Authored-By: Claude` in commits and no Claude Code footer in PR bodies.
- Merging `next → stable` publishes a release.

## Review Focus

1. **A helper Sparkle adds or moves in a later version is left ad-hoc.** Notarization would reject the build. Task 3 lists the helpers explicitly and checks each one with `codesign -dvv`, but a new helper would not be on the list. The reviewer should compare the list with the real framework layout from Task 1, Step 2.
2. **The CI secret and `SUPublicEDKey` differ.** Every update would fail its signature check on users' Macs. `test-make-appcast.sh` pins `mismatched_key_fails`, and Task 4, Step 6 checks that Sparkle's real `sign_update` output passes the CryptoKit check.
3. **Release notes contain `]]>`, `&` or `<`.** They must not break the appcast. `test-make-appcast.sh` pins `notes_with_cdata_end_stay_valid`.
4. **A Debug build starts the updater** and would always be offered an "update". The `#if DEBUG` guard in `Updater.init` handles this; Task 2, Step 4 checks it by hand.
5. **`releases/latest/download/appcast.xml` redirects to `objects.githubusercontent.com`.** Sparkle must follow the redirect. Task 7 checks the real URL with `curl -L` and with a real in-app update.

---

### Task 1: Sparkle dependency and EdDSA key

**Files:**
- Modify: `project.yml` (`packages`, `targets.Agenty.dependencies`, `targets.Agenty.info.properties`)

**Interfaces:**
- Produces:
  - `SPARKLE_BIN="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"`, which holds `sign_update` and `generate_keys`. Tasks 4 and 7 use it.
  - The framework layout under `Agenty.app/Contents/Frameworks/Sparkle.framework/Versions/B/`. Task 3 uses it.
  - `SUPublicEDKey`, a base64 32-byte Ed25519 public key.
  - Secret `SPARKLE_ED_PRIVATE_KEY`, the base64 32-byte seed.

- [ ] **Step 1: Add Sparkle and the feed to `project.yml`**

```yaml
packages:
  UsageCore:
    path: Packages/UsageCore
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    exactVersion: 2.10.1
```

- Add `- package: Sparkle` under `targets.Agenty.dependencies`.
- Add these under `info.properties`:
  - `SUFeedURL: https://github.com/vuxng/agenty/releases/latest/download/appcast.xml`
  - `SUEnableAutomaticChecks: true`

- [ ] **Step 2: Build ad-hoc and record the real layout**

Run: `scripts/build-release.sh 0.1.1 && ls build/DerivedData/Build/Products/Release/Agenty.app/Contents/Frameworks/Sparkle.framework/Versions/B build/DerivedData/Build/Products/Release/Agenty.app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin`

Expected:
- `notice: skipping notarization (ad-hoc build)`.
- `Versions/B` contains `Autoupdate`, `Updater.app` and `XPCServices`.
- `XPCServices` contains `Installer.xpc` and `Downloader.xpc`.
- `bin` contains `sign_update` and `generate_keys`.

If any path differs, write a Ruling and use the real paths in Tasks 3 and 4.

- [ ] **Step 3: Generate the key (Keychain may prompt)**

Run: `build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account io.github.vuxng.Agenty`

Expected: it prints a base64 public key. If it reports an existing key for this account, reuse it (Ruling).

Then set `SUPublicEDKey: <that key>` under `info.properties` in `project.yml`.

- [ ] **Step 4: Upload the private key — STOP: tell the user first**

macOS asks for the login Keychain password, because the item is marked sensitive. The user types it.

```bash
umask 077; f="$(mktemp)"
"$SPARKLE_BIN/generate_keys" --account io.github.vuxng.Agenty -x "$f"
gh secret set SPARKLE_ED_PRIVATE_KEY --env release --repo vuxng/agenty < "$f"
rm -P "$f"
```

Run: `gh secret list --env release --repo vuxng/agenty`

Expected: the list contains `SPARKLE_ED_PRIVATE_KEY`. Nothing secret was printed. Remind the user to store the key (exported with `-x`) in their password manager.

- [ ] **Step 5: Commit**

```bash
git add project.yml
git commit -m "build: add Sparkle 2.10.1 and the update feed"
```

---

### Task 2: Updater, Settings section, popover reminder

**Files:**
- Create: `App/System/Updater.swift`
- Create: `App/Views/Popover/UpdateBanner.swift`
- Modify: `App/AppModel.swift`, `App/AgentyApp.swift`, `App/Views/Popover/UsagePopover.swift`, `App/Views/Settings/SettingsView.swift`, `App/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: Sparkle (Task 1).
- Produces: `@Observable @MainActor final class Updater: NSObject` with:
  - `init()`: starts the updater unless the build is `DEBUG`.
  - `let isEnabled: Bool`: `false` in `DEBUG`.
  - `private(set) var canCheckForUpdates: Bool`: kept in sync with `SPUUpdater.canCheckForUpdates` via KVO (`.initial, .new`).
  - `var automaticallyChecksForUpdates: Bool`: a stored mirror that is initialised from `SPUUpdater`, with a `didSet` that writes back.
  - `private(set) var availableVersion: String?`
  - `func checkForUpdates()`: calls `NSApp.activate()`, then `controller.checkForUpdates(nil)`.

There is no app test target, and the spec (§7.1) asks only for script tests. This task is verified by building it and checking it by hand. Task 7 is the end-to-end proof.

- [ ] **Step 1: Write `Updater.swift`**

- `SPUStandardUpdaterController(startingUpdater: isEnabled, updaterDelegate: self, userDriverDelegate: self)`.
- The `SPUStandardUserDriverDelegate` methods follow spec §4.2:
  - `supportsGentleScheduledUpdateReminders` returns `true`.
  - `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)` returns `immediateFocus`.
  - `standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)`: when Sparkle does not show the update itself, set `availableVersion = update.displayVersionString`; otherwise call `NSApp.activate()`.
  - `standardUserDriverWillFinishUpdateSession()` sets `availableVersion = nil`.
- If Sparkle's protocols are not main-actor isolated, declare the conformances with `@preconcurrency`. Do not mark the class `nonisolated`.

- [ ] **Step 2: Wire it up**

- `AppModel`: add `let updater = Updater()`.
- `AgentyApp`: `UsagePopover(store:onRetryKeychain:updater: model.updater)`.
- `SettingsView`: `SettingsForm(…, updater: model.updater)`.
- `UsagePopover`: gets `var updater: Updater? = nil`. When `updater?.availableVersion` is set, show `UpdateBanner(version:install:)` above `PopoverFooter`.
- `UpdateBanner`: `Text("Agenty \(version) is available")` and `Button("Install…")`, styled like the rest of the popover. Add one `#Preview`.
- `SettingsForm`: gets `var updater: Updater? = nil` (the preview passes nothing). Add a last `Section("Updates")` with:
  - `Toggle("Check for updates automatically")` bound to `automaticallyChecksForUpdates`;
  - `Button("Check for Updates…")`, disabled when `!canCheckForUpdates`;
  - a caption `Text("Version \(short) (\(build))")`;
  - a caption `Text("Updates are off in debug builds")`, shown when `!isEnabled`. The toggle and the button are disabled in that case.

- [ ] **Step 3: Add the strings with Vietnamese**

| Key | vi |
|---|---|
| `Updates` | `Cập nhật` |
| `Check for updates automatically` | `Tự động kiểm tra bản cập nhật` |
| `Check for Updates…` | `Kiểm tra bản cập nhật…` |
| `Version %@ (%@)` | `Phiên bản %1$@ (%2$@)` |
| `Updates are off in debug builds` | `Bản debug không kiểm tra cập nhật` |
| `Agenty %@ is available` | `Đã có Agenty %@` |
| `Install…` | `Cài đặt…` |

Use the existing entry format: `en` has state `new`, `vi` has state `translated`, and multi-argument values use `%1$@ %2$@`.

- [ ] **Step 4: Build both configurations and check them**

Run: `xcodegen generate && xcodebuild -project Agenty.xcodeproj -scheme Agenty -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'warning:|error:|BUILD' | sort -u`

Expected: `** BUILD SUCCEEDED **`, and no warning or error mentions `Updater.swift`, `UpdateBanner.swift` or the settings view.

Run: `scripts/build-release.sh 0.1.1 && plutil -p build/DerivedData/Build/Products/Release/Agenty.app/Contents/Info.plist | grep -E '"SU'`

Expected: `SUFeedURL`, `SUPublicEDKey` and `SUEnableAutomaticChecks => true`.

Run a check script that asserts each of the 7 keys has a `vi` value in `Localizable.xcstrings`. Expected: all 7 are present.

Then check by hand:
- Open the ad-hoc Release app and go to Settings. The Updates section shows the toggle and an enabled button.
- Run the Debug build. The section shows the "off in debug builds" caption.

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "feat(app): check for updates with Sparkle, with a gentle reminder in the popover"
```

---

### Task 3: Sign Sparkle's helpers in `build-release.sh`

**Files:**
- Modify: `scripts/build-release.sh`, `scripts/test-build-release.sh`

**Interfaces:**
- Consumes: the layout from Task 1, Step 2.
- Produces: a Developer ID build whose Sparkle components all carry Developer ID, runtime and a timestamp.

- [ ] **Step 1: Extend the test**

**Stubs**
- The `xcodebuild` stub also creates `…/Agenty.app/Contents/Frameworks/Sparkle.framework/Versions/B/{Autoupdate,Updater.app,XPCServices/Installer.xpc,XPCServices/Downloader.xpc}`.
- The `codesign` stub appends `"$*"` to `log/codesign` on every call.
- The `codesign -dvv` stub omits `Timestamp=` for any path that contains `$FAKE_NO_TIMESTAMP`.

**New cases**
- `devid_signs_sparkle_inside_out`: the paths of the `-f -s` calls appear in this order: `Installer.xpc`, `Downloader.xpc`, `Autoupdate`, `Updater.app`, `Sparkle.framework`, `Agenty.app`.
- `devid_signing_never_uses_deep`: no `-f -s` line contains `--deep`.
- `devid_signing_uses_runtime_and_timestamp`: every `-f -s` line contains `-o runtime` and `--timestamp`.
- `devid_signing_uses_keychain_when_set`: with `SIGN_KEYCHAIN=k.keychain-db`, every `-f -s` line contains `--keychain k.keychain-db`.
- `downloader_keeps_its_entitlements`: the `Downloader.xpc` line contains `--preserve-metadata=entitlements`.
- `helper_without_timestamp_fails_before_notarizing`: with `FAKE_NO_TIMESTAMP=Autoupdate` and notary credentials set, the exit code is 1, the output mentions `Autoupdate` and `Timestamp=`, and `log/notarytool-submit.args` does not exist.
- `adhoc_does_not_sign_helpers_one_by_one`: an ad-hoc run has no `-f -s` line for `Installer.xpc`.

- [ ] **Step 2: Run it**

Run: `bash scripts/test-build-release.sh`

Expected: the new cases FAIL, because nothing re-signs the helpers yet. The 8 existing cases pass.

- [ ] **Step 3: Implement it in `build-release.sh`**

- Add a `codesign_args` array: `-f -s "$SIGN_IDENTITY" -o runtime --timestamp`, plus `--keychain "$SIGN_KEYCHAIN"` when it is set.
- Add an `F` path and an ordered list of components, following spec §5.1:
  1. `$F/Versions/B/XPCServices/Installer.xpc`
  2. `$F/Versions/B/XPCServices/Downloader.xpc`, with `--preserve-metadata=entitlements`
  3. `$F/Versions/B/Autoupdate`
  4. `$F/Versions/B/Updater.app`
  5. `$F`
  6. `$APP`, with `--preserve-metadata=entitlements`
- In the Developer ID branch, after `xcodebuild`, sign the list in order. Then run the existing `-dvv` check over every component. On failure, print `error: codesign -dvv output for <component> is missing: <field>`. Then run `codesign --verify --strict --deep "$APP"`.

- [ ] **Step 4: Run the tests and lint**

Run: `bash scripts/test-build-release.sh && shellcheck scripts/*.sh`

Expected: `15 passed, 0 failed`, and ShellCheck prints nothing.

- [ ] **Step 5: Notarize for real, locally**

Run: `SIGN_IDENTITY="Developer ID Application: Vu Nguyen (8WJ6LC5Z59)" TEAM_ID=8WJ6LC5Z59 NOTARY_KEYCHAIN_PROFILE=agenty-notary scripts/build-release.sh 0.1.1`

Expected: `Notarization status: Accepted`, `source=Notarized Developer ID` and `Created build/Agenty-0.1.1-arm64.zip`.

- [ ] **Step 6: Commit**

```bash
git add scripts/build-release.sh scripts/test-build-release.sh
git commit -m "fix(release): sign Sparkle's helpers with Developer ID, inside out"
```

---

### Task 4: Signed appcast

**Files:**
- Create: `scripts/verify-ed-signature.swift`, `scripts/make-appcast.sh`, `scripts/test-make-appcast.sh`

**Interfaces:**
- Consumes: `SPARKLE_BIN` (Task 1); `build/Agenty-<v>-arm64.zip` from `build-release.sh`.
- Produces:
  - `swift scripts/verify-ed-signature.swift <file> <signature-base64> <public-key-base64>`. It exits 0 for a valid signature, 1 for an invalid one, and 2 for a usage or base64 error.
  - `scripts/make-appcast.sh <version>`. It reads the private key from stdin and `build/notes.md`, and writes `build/appcast.xml`. Env `SPARKLE_BIN` defaults to the SPM path.

- [ ] **Step 1: Write `test-make-appcast.sh`**

**Setup**
- Each case copies `make-appcast.sh` and `verify-ed-signature.swift` into a temp root.
- A test-only `ed25519.swift`, written into the temp dir and never into `scripts/`, uses CryptoKit for two commands:
  - `keygen` prints `<seed-b64> <pub-b64>`;
  - `sign <file>` reads the seed from stdin and prints the signature in base64.
- The fake `bin/sign_update`:
  - appends `"$*"` to `log/sign_update.args`;
  - signs its last argument with the seed from stdin;
  - prints `sparkle:edSignature="<sig>" length="<bytes>"`.
- The test zip (made with `ditto -c -k --keepParent`) holds an `Agenty.app` whose `Info.plist` has `CFBundleShortVersionString` 0.2.0, `CFBundleVersion` 45, `LSMinimumSystemVersion` 27.0 and `SUPublicEDKey` = the test public key.
- `build/notes.md` holds the release notes.

**Cases**
- `writes_one_signed_item`: exit 0. `xmllint --xpath` finds exactly one `item` with:
  - `sparkle:version` 45 and `sparkle:shortVersionString` 0.2.0;
  - `sparkle:minimumSystemVersion` 27.0;
  - `enclosure/@url` = `https://github.com/vuxng/agenty/releases/download/v0.2.0/Agenty-0.2.0-arm64.zip`;
  - `@length` = the zip's byte count;
  - an `@sparkle:edSignature` that `verify-ed-signature.swift` accepts with the test public key;
  - `description/@sparkle:format` = `markdown`.
- `notes_with_cdata_end_stay_valid`: notes contain `a ]]> b & <c>`. `xmllint --noout` passes, and the description text equals the notes exactly.
- `missing_key_fails`: empty stdin gives exit 1 and `Sparkle private key is missing`.
- `mismatched_key_fails`: signing with a second key pair gives exit 1, `the Sparkle key does not match SUPublicEDKey`, and no `build/appcast.xml`.
- `version_mismatch_fails`: running with `0.2.1` against the 0.2.0 zip gives exit 1.
- `key_never_in_arguments`: `log/sign_update.args` does not contain the seed.

- [ ] **Step 2: Run it**

Run: `bash scripts/test-make-appcast.sh`

Expected: FAIL, because `scripts/make-appcast.sh` does not exist yet.

- [ ] **Step 3: Write `verify-ed-signature.swift`**

It uses `Curve25519.Signing.PublicKey(rawRepresentation:)` and `isValidSignature(_:for:)`, and reads the file with `Data(contentsOf:options: .mappedIfSafe)`.

- [ ] **Step 4: Write `make-appcast.sh`**

Follow spec §5.2, steps 1–6:
- The key comes from `key="$(cat)"` and is passed to `sign_update --ed-key-file -` through `printf '%s' "$key" |`.
- The values are read with `plutil -extract … raw`.
- `pubDate` is `LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000'`.
- The notes go into CDATA after replacing `]]>` with `]]]]><![CDATA[>`.
- Write the appcast to a temp file and move it into place only after the check passes. That way a failed run leaves no `build/appcast.xml`.

- [ ] **Step 5: Run the tests and lint**

Run: `bash scripts/test-make-appcast.sh && shellcheck scripts/*.sh`

Expected: `6 passed, 0 failed`, and ShellCheck prints nothing.

- [ ] **Step 6: Check with the real Sparkle tool (Keychain may prompt)**

Sign with the real key in the Keychain:
`"$SPARKLE_BIN/sign_update" --account io.github.vuxng.Agenty -p build/Agenty-0.1.1-arm64.zip`

Verify it:
`swift scripts/verify-ed-signature.swift build/Agenty-0.1.1-arm64.zip "$sig" "$(plutil -extract SUPublicEDKey raw -o - build/DerivedData/Build/Products/Release/Agenty.app/Contents/Info.plist)"`

Then run the same check against a copy of the zip with one extra byte appended.

Expected: exit 0 for the real zip and exit 1 for the modified copy. This proves CryptoKit accepts Sparkle's signatures.

- [ ] **Step 7: Commit**

```bash
git add scripts/verify-ed-signature.swift scripts/make-appcast.sh scripts/test-make-appcast.sh
git commit -m "feat(release): make-appcast.sh writes a signed appcast and checks it against SUPublicEDKey"
```

---

### Task 5: Release workflow

**Files:**
- Modify: `scripts/publish-release.sh`, `scripts/test-publish-release.sh`, `.github/workflows/release.yml`, `.github/workflows/ci.yml`, `docs/superpowers/specs/2026-11-04-ci-cd-release-design.md` (§4.1 and §4.2 only)

**Interfaces:**
- Consumes: `scripts/make-appcast.sh <version>` (Task 4).
- Produces: releases with three assets: the zip, its `.sha256`, and `appcast.xml`.

- [ ] **Step 1: Update the test**

`publishes_both_assets_at_the_commit` becomes `publishes_zip_checksum_and_appcast`. It expects this exact line:

`release create v0.2.0 build/Agenty-0.2.0-arm64.zip build/Agenty-0.2.0-arm64.zip.sha256 build/appcast.xml --target abc123 --title Agenty 0.2.0 --notes-file build/notes.md`

The setup also creates `build/appcast.xml` and `build/notes.md`.

- [ ] **Step 2: Run it**

Run: `bash scripts/test-publish-release.sh`

Expected: `FAIL publishes_zip_checksum_and_appcast`; the other 3 cases pass.

- [ ] **Step 3: Update `publish-release.sh`**

Add `build/appcast.xml` as an asset, and use `--notes-file build/notes.md` in place of `--generate-notes`.

- [ ] **Step 4: Update the workflows**

- `release.yml`: between "Verify Gatekeeper" and "Publish release", add two steps:
  - "Generate release notes": `GH_TOKEN`, `VERSION`, and the `gh api …/generate-notes` call from spec §5.4, written to `build/notes.md`.
  - "Make appcast": env `SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}` and `VERSION`; run `printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | scripts/make-appcast.sh "$VERSION"`.
- `ci.yml`: in the `build` job, after "Test build-release", add the step `Test make-appcast` → `bash scripts/test-make-appcast.sh`. It needs macOS for `plutil`, `xmllint` and CryptoKit.
- The CI/CD spec: list the new steps and the new test.

- [ ] **Step 5: Run the tests and lint**

Run: `for t in scripts/test-*.sh; do bash "$t" | tail -1; done; shellcheck scripts/*.sh; actionlint`

Expected: every suite reports `0 failed`, and both linters print nothing.

- [ ] **Step 6: Commit**

```bash
git add scripts/publish-release.sh scripts/test-publish-release.sh .github/workflows docs/superpowers/specs/2026-11-04-ci-cd-release-design.md
git commit -m "ci(release): generate notes and a signed appcast, attach it to the release"
```

---

### Task 6: README, version 0.2.0, PR into `next`

**Files:**
- Modify: `README.md` ("Install" and "Branches & releases"), `project.yml` (`MARKETING_VERSION`)

- [ ] **Step 1: Update the README**

"Install" gains three points:
- Agenty checks for updates once a day and asks before installing.
- The setting lives in Settings › Updates.
- People on 0.1.x must download 0.2.0 by hand once.

"Branches & releases" gains two points:
- Each release attaches `appcast.xml`, signed with the EdDSA key from secret `SPARKLE_ED_PRIVATE_KEY`.
- If that key is lost, existing installs cannot be updated. Ship a new `SUPublicEDKey`, and users must download that release by hand.

- [ ] **Step 2: Bump the version**

Set `MARKETING_VERSION: 0.2.0`.

Run: `scripts/check-version.sh`

Expected: `version=0.2.0`.

- [ ] **Step 3: Commit, push and open the PR**

```bash
git add README.md project.yml
git commit -m "docs: explain updates; bump version to 0.2.0"
git push -u origin feat/auto-update
```

Open a PR into `next`, with a body in the `mattpocock-skills:pr` format and no Claude footer.

Expected: the `build` and `scripts` checks pass.

- [ ] **Step 4: Squash-merge into `next`**

Expected: the PR is merged and local `next` matches `origin/next`.

---

### Task 7: Release v0.2.0 and prove the update path

- [ ] **Step 1: Release**

Open the PR `next → stable` titled "Release 0.2.0". Its body notes that 0.1.x users must install 0.2.0 by hand.

Expected: `build`, `scripts` and `version-check` pass.

Merge it with a merge commit; this publishes the release. Watch the Release run.

Expected: every step succeeds, including "Make appcast".

- [ ] **Step 2: Check what was published**

Download `https://github.com/vuxng/agenty/releases/latest/download/appcast.xml` with `curl -fsSL`. Check it with `xmllint --noout`, and read `sparkle:shortVersionString`, the enclosure URL, the length and the signature.

Download the release zip, then run `shasum -c`, `spctl` and `stapler validate`. Verify the appcast's signature over the zip with `verify-ed-signature.swift` and the `SUPublicEDKey` from the downloaded app.

Expected:
- The appcast shows version 0.2.0, the enclosure URL from the Global Constraints, and a length equal to the zip's size.
- The signature check exits 0.
- `spctl` reports `source=Notarized Developer ID`.

Then add the manual-install note to the GitHub release notes (spec §9). Generated notes list only PR titles. Read the current body with `gh release view v0.2.0 --json body --jq .body`. Prepend `**Agenty now updates itself.** If you are on 0.1.x, download this release and replace the app by hand once; later versions arrive through Settings › Updates.`, then write it back with `gh release edit v0.2.0 --notes-file <file>`. The appcast keeps its notes; 0.1.x installs never read it.

Expected: `gh release view v0.2.0 --json body --jq .body | head -1` prints that line.

- [ ] **Step 3: Update from an older build, end to end (the user clicks)**

1. Build the fake older version: `BUILD_NUMBER=1 SIGN_IDENTITY="Developer ID Application: Vu Nguyen (8WJ6LC5Z59)" TEAM_ID=8WJ6LC5Z59 scripts/build-release.sh 0.1.9`. It is not notarized: expect `notice: skipping notarization (no credentials)`.
2. Copy `Agenty.app` to a scratchpad folder.
3. Quit the running Agenty and `open` the copy.
4. The user clicks Settings › Check for Updates…, then Install.

Expected:
- Sparkle offers 0.2.0 with the release notes.
- After Install, the app relaunches from the same path.
- `plutil` on that bundle shows `0.2.0` with the release's build number.
- No Keychain prompt appears on the next refresh.

- [ ] **Step 4: Gentle reminder (the user looks)**

1. Rebuild and copy the 0.1.9 app as in Step 3.
2. Run `defaults write io.github.vuxng.Agenty SUHasLaunchedBefore -bool true` and `defaults write io.github.vuxng.Agenty SULastCheckTime -date "<now − 1 day + 5 min, UTC>"`.
3. Open the app and wait 6 minutes.

Expected:
- No window pops up.
- The popover shows `Agenty 0.2.0 is available`.
- Install… opens Sparkle's dialog.

If nothing appears after 10 minutes, check the Sparkle lines in `log show --predicate 'process == "Agenty"' --last 15m` and write a Ruling.

- [ ] **Step 5: Clean up**

Quit the test copy and start `/Applications/Agenty.app` again. Tell the user to install 0.2.0 into `/Applications` by hand.

Update the memory file `agenty-status.md`.
