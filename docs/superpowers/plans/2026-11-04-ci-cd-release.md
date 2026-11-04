# Agenty CI/CD + v0.1.0 Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bỏ `main`, chuyển sang `stable`/`next`, thêm CI/CD ký Developer ID và notarize, gắn app icon, rồi phát hành `v0.1.0`.

**Architecture:** Logic nằm trong các script bash ở `scripts/` (kiểm tra version, build/ký/notarize, wizard secrets). Hai workflow mỏng gọi các script đó: `ci.yml` (push/PR vào `next`, `stable`) và `release.yml` (push vào `stable`). Các thao tác GitHub (public, nhánh, ruleset, environment) làm bằng `gh` theo đúng thứ tự trong spec §8.

**Tech Stack:** bash, GitHub Actions (`xcode-27`, `ubuntu-latest`), Xcode 27.2 (`xcodebuild`, `codesign`, `notarytool`, `stapler`, `ictool`), XcodeGen 2.46, `gh`, shellcheck, actionlint, gitleaks.

**Spec:** `docs/superpowers/specs/2026-11-04-ci-cd-release-design.md`

## Global Constraints

- Nhánh: `stable` (release, chỉ merge commit), `next` (mặc định; squash hoặc merge commit). Tag `vX.Y.Z`.
- Artifact: `build/Agenty-<version>-arm64.zip` và `build/Agenty-<version>-arm64.zip.sha256` (nội dung do `shasum -a 256` sinh, tên file tương đối để `shasum -c` dùng được).
- `TEAM_ID=8WJ6LC5Z59`; `SIGN_IDENTITY="Developer ID Application: Vu Nguyen (8WJ6LC5Z59)"`.
- Runner `xcode-27`; Xcode tại `/Applications/Xcode_27.2.app`, khai báo một lần trong `env: XCODE_APP` ở đầu mỗi workflow.
- Environment `release`, deployment branch policy chỉ `stable`. Secrets: `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`.
- Tên check bắt buộc: `build`, `scripts`, `version-check` (job id trong `ci.yml`, workflow `CI`).
- Profile notarize ở local: `agenty-notary`.
- Script: `#!/bin/bash`, `set -euo pipefail`, sạch shellcheck. Không `set -x` và không `echo` giá trị secret ở bất kỳ đâu.
- Secret không bao giờ đi qua chat. Bước nào cần secret thì người dùng tự làm.
- Không đổi glyph thanh menu. Không đưa `previews/*.png` từ gói handoff vào repo.
- App vẫn là macOS 27, arm64-only, hardened runtime (giữ nguyên `project.yml`, chỉ thêm `ASSETCATALOG_COMPILER_APPICON_NAME`).
- Commit theo conventional commits. **Không** thêm `Co-Authored-By` Claude vào commit, **không** thêm footer Claude Code vào PR.
- Các task 1–6 chỉ làm ở local trên nhánh `ci/stable-next-release`. Không push gì trước Task 8.

**Lệnh chuẩn:**
- Cài công cụ: `brew install shellcheck actionlint gitleaks` (chạy một lần).
- Lint: `shellcheck scripts/*.sh` không in gì; `actionlint` không in gì.
- Build Debug: `xcodegen generate && xcodebuild -project Agenty.xcodeproj -scheme Agenty -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO`, thành công khi thấy `** BUILD SUCCEEDED **`. Cảnh báo `CoreSimulator is out of date` là vô hại.
- `ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"`.
- `SCRATCH`: thư mục scratchpad của phiên. Dùng cho file tạm như ảnh render, body PR, bản release tải về. Không ghi các file đó vào repo.

## Review Focus

1. **Chạy lại release sau khi đã release xong.** `check-version.sh` phải exit 1 với thông báo chứa `already released`, không được build lại hay đè Release. Test ở Task 1: `tag_exists_fails`.
2. **`MARKETING_VERSION` viết có nháy, không nháy hoặc có khoảng trắng thừa** (`"0.2.0"`, `0.2.0`, `0.2.0  `). Cả ba phải đọc ra `0.2.0`. Test ở Task 1: `quoted_version_parses`, `trailing_space_parses`.
3. **So sánh version theo nghĩa semver, không theo chữ:** `0.10.0` lớn hơn `v0.9.0`. Test ở Task 1: `semver_not_lexical`.
4. **Có tag không phải `vX.Y.Z`** (`v1.0.0-beta.1`, `next`). Các tag này bị bỏ qua khi tìm tag mới nhất, không làm script lỗi. Test ở Task 1: `non_release_tags_ignored`.
5. **Merge PR release `next → stable` khi đã bật "auto-delete head branches".** `next` phải còn nguyên. Kiểm tra ở Task 11, Step 7.

---

### Task 1: `scripts/check-version.sh` và test

**Files:**
- Create: `scripts/check-version.sh`
- Test: `scripts/test-check-version.sh`

**Interfaces:**
- Produces: `scripts/check-version.sh` (không tham số; env tuỳ chọn `PROJECT_YML`, mặc định `project.yml`; đọc tag từ repo git ở cwd).
  - Thành công: exit 0; in `version=<X.Y.Z>` ra stdout; nếu có `$GITHUB_OUTPUT` thì ghi thêm `version=<X.Y.Z>` vào file đó.
  - Thất bại: exit 1, in ra stderr một trong các thông báo sau:
    - `error: MARKETING_VERSION not found in <file>.`
    - `error: MARKETING_VERSION "<raw>" in <file> is not X.Y.Z.`
    - `error: v<version> is already released (tag exists). Bump MARKETING_VERSION in project.yml.`
    - `error: <version> must be greater than the latest release <tag>.`

- [ ] **Step 1: Cài công cụ**

Run: `brew install shellcheck actionlint gitleaks`
Expected: cả ba lệnh `shellcheck --version`, `actionlint --version`, `gitleaks version` đều chạy được.

- [ ] **Step 2: Viết test `scripts/test-check-version.sh`**

Mỗi ca tạo một repo tạm bằng `mktemp -d`, `git init -q`, ghi `project.yml` có một dòng `    MARKETING_VERSION: <giá trị>`, tạo một commit (`git -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init`), gắn tag theo ca rồi chạy `(cd "$tmp" && PROJECT_YML="$tmp/project.yml" GITHUB_OUTPUT="$tmp/out" "$SCRIPT")`. `SCRIPT` là đường dẫn tuyệt đối tới `scripts/check-version.sh`. Cuối cùng in `N passed, M failed` và exit 1 nếu `M > 0`.

| Ca | `MARKETING_VERSION` | Tag có sẵn | Kỳ vọng |
|---|---|---|---|
| `no_tags_passes` | `0.1.0` | (không) | exit 0, stdout `version=0.1.0`, file `out` chứa `version=0.1.0` |
| `quoted_version_parses` | `"0.2.0"` | `v0.1.0` | exit 0, stdout `version=0.2.0` |
| `trailing_space_parses` | `0.2.0  ` | `v0.1.0` | exit 0, stdout `version=0.2.0` |
| `tag_exists_fails` | `0.1.0` | `v0.1.0` | exit 1, stderr chứa `already released` |
| `older_than_latest_fails` | `0.1.0` | `v0.2.0` | exit 1, stderr chứa `must be greater than the latest release v0.2.0` |
| `semver_not_lexical` | `0.10.0` | `v0.9.0` | exit 0 |
| `non_release_tags_ignored` | `0.2.0` | `v0.1.0`, `v1.0.0-beta.1`, `next` | exit 0 |
| `bad_format_fails` | `0.2` | (không) | exit 1, stderr chứa `is not X.Y.Z` |
| `missing_key_fails` | (không có dòng) | (không) | exit 1, stderr chứa `not found` |

- [ ] **Step 3: Chạy test, thấy fail**

Run: `bash scripts/test-check-version.sh`
Expected: các ca fail vì chưa có `scripts/check-version.sh`; dòng cuối là `0 passed, 9 failed`.

- [ ] **Step 4: Viết `scripts/check-version.sh`**

- Lấy dòng `MARKETING_VERSION:` đầu tiên bằng `grep -m1`, bỏ khoá, nháy và khoảng trắng, rồi kiểm tra với `^[0-9]+\.[0-9]+\.[0-9]+$`.
- Tag mới nhất: `git tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1`.
- "Lớn hơn": `printf '%s\n%s\n' "$latest_ver" "$version" | sort -V | tail -1` phải là `$version`, và hai giá trị khác nhau.
- `chmod +x`.

- [ ] **Step 5: Chạy test, thấy pass, lint sạch**

Run: `bash scripts/test-check-version.sh && shellcheck scripts/check-version.sh scripts/test-check-version.sh`
Expected: `9 passed, 0 failed`; shellcheck không in gì.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-version.sh scripts/test-check-version.sh
git commit -m "ci: add check-version script with tests"
```

---

### Task 2: `scripts/build-release.sh` hỗ trợ Developer ID và notarize

**Files:**
- Modify: `scripts/build-release.sh` (viết lại toàn bộ)

**Interfaces:**
- Produces: `scripts/build-release.sh <version>`. Exit 1 nếu thiếu tham số. Biến môi trường:
  - `SIGN_IDENTITY`: không đặt thì ký ad-hoc như cũ (`codesign --force --deep --options runtime --sign -`).
  - `TEAM_ID`: bắt buộc khi có `SIGN_IDENTITY`.
  - `SIGN_KEYCHAIN`: tuỳ chọn; nếu có thì thêm `--keychain <path>` vào `OTHER_CODE_SIGN_FLAGS`.
  - Notarize: `NOTARY_KEYCHAIN_PROFILE`, hoặc bộ ba `NOTARY_KEY_PATH` + `NOTARY_KEY_ID` + `NOTARY_ISSUER_ID`. Thiếu cả hai thì in `notice: skipping notarization (no credentials)` và bỏ qua.
  - `BUILD_NUMBER`: mặc định `git rev-list --count HEAD`.
  - Kết quả: `build/Agenty-<version>-arm64.zip` và `.sha256`. Dòng cuối in `Created build/Agenty-<version>-arm64.zip`.

- [ ] **Step 1: Viết lại script**

Luồng chung:
1. `xcodegen generate`.
2. `xcodebuild -project Agenty.xcodeproj -scheme Agenty -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build`.
3. Ký và kiểm tra (xem bảng bên dưới).
4. `lipo -archs` phải đúng `arm64`.
5. Nén bằng `ditto -c -k --keepParent`.
6. Notarize (nếu có thông tin).
7. Ghi `.sha256`: `(cd build && shasum -a 256 "Agenty-$VERSION-arm64.zip" > "Agenty-$VERSION-arm64.zip.sha256")`.

| Bước | Ad-hoc | Developer ID |
|---|---|---|
| Thêm vào `xcodebuild` | (không) | `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" OTHER_CODE_SIGN_FLAGS="--timestamp[ --keychain $SIGN_KEYCHAIN]" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` |
| Ký lại sau build | `codesign --force --deep --options runtime --sign -` | Không ký lại, không dùng `--deep` |
| Kiểm tra | `codesign --verify --strict` | `codesign --verify --strict --deep`; output `codesign -dvv "$APP" 2>&1` phải chứa `Authority=Developer ID Application`, `TeamIdentifier=$TEAM_ID`, `(runtime)`, `Timestamp=`. Thiếu dòng nào thì exit 1 và in dòng đó |

Notarize, áp dụng khi có `SIGN_IDENTITY` và có thông tin notarize:
1. `xcrun notarytool submit "$ZIP" --wait --output-format json <auth> > build/notary.json || true`.
2. Đọc `status` và `id` bằng `plutil -extract <key> raw -o - build/notary.json`.
3. Nếu `status` khác `Accepted`: chạy `xcrun notarytool log "$id" <auth>` rồi exit 1.
4. Nếu `Accepted`: `xcrun stapler staple "$APP"` → `xcrun stapler validate "$APP"` → `rm -f "$ZIP"` và nén lại → `spctl --assess --type execute -vv "$APP" 2>&1` phải chứa `source=Notarized Developer ID`.

- [ ] **Step 2: Lint**

Run: `shellcheck scripts/build-release.sh`
Expected: không in gì.

- [ ] **Step 3: Kiểm tra nhánh ad-hoc**

Run: `scripts/build-release.sh 0.1.0 && (cd build && shasum -a 256 -c Agenty-0.1.0-arm64.zip.sha256) && /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' -c 'Print :CFBundleVersion' build/DerivedData/Build/Products/Release/Agenty.app/Contents/Info.plist`
Expected: `** BUILD SUCCEEDED **`, `Created build/Agenty-0.1.0-arm64.zip`, `Agenty-0.1.0-arm64.zip: OK`, rồi `0.1.0` và một số đúng bằng `git rev-list --count HEAD`.

- [ ] **Step 4: Kiểm tra ký Developer ID ở local, chưa notarize**

Run: `SIGN_IDENTITY="Developer ID Application: Vu Nguyen (8WJ6LC5Z59)" TEAM_ID=8WJ6LC5Z59 scripts/build-release.sh 0.1.0`
Expected: có dòng `notice: skipping notarization (no credentials)` và `Created build/Agenty-0.1.0-arm64.zip`; các kiểm tra `codesign -dvv` đều pass. Nếu macOS hiện hộp thoại "codesign wants to access key", người dùng bấm **Always Allow** (⏸ báo người dùng trước khi chạy).

- [ ] **Step 5: Commit**

```bash
git add scripts/build-release.sh
git commit -m "build: sign with Developer ID and notarize in build-release"
```

---

### Task 3: App icon

**Files:**
- Create: `App/AppIcon.icon/icon.json`, `App/AppIcon.icon/Assets/1-core.svg`, `2-ring-used.svg`, `3-ring-remaining.svg`
- Create: `docs/images/icon.png`
- Modify: `project.yml` (`settings.base`), `README.md` (đầu file)

**Interfaces:**
- Consumes: gói `/Users/vu/Downloads/agenty-handoff.zip`. Giải nén vào thư mục mới trong scratchpad; chỉ copy file, không chạy gì trong đó.
- Produces: app được build ra có `CFBundleIconName = AppIcon`, kèm `Contents/Resources/AppIcon.icns` và `Contents/Resources/Assets.car`.

- [ ] **Step 1: Copy asset**

Copy `agenty-handoff/icon-composer-layers/{1-core,2-ring-used,3-ring-remaining}.svg` vào `App/AppIcon.icon/Assets/`. Copy `agenty-handoff/png/agenty-256.png` thành `docs/images/icon.png`.

- [ ] **Step 2: Viết `App/AppIcon.icon/icon.json`**

Nội dung dưới đây đã được thử render bằng `ictool` vào ngày 2026-11-04. Màu lấy từ `BRIEF.md`.

```json
{
  "fill" : { "linear-gradient" : [ "srgb:0.48627,0.41961,0.94902,1.00000", "srgb:0.29412,0.20784,0.81176,1.00000" ] },
  "fill-specializations" : [
    { "appearance" : "dark", "value" : { "linear-gradient" : [ "srgb:0.18039,0.17647,0.20000,1.00000", "srgb:0.08235,0.07843,0.09412,1.00000" ] } }
  ],
  "groups" : [
    {
      "layers" : [
        { "image-name" : "3-ring-remaining.svg", "name" : "3-ring-remaining", "opacity" : 0.38,
          "fill-specializations" : [ { "appearance" : "dark", "value" : { "solid" : "srgb:0.64314,0.59216,1.00000,1.00000" } } ] },
        { "image-name" : "2-ring-used.svg", "name" : "2-ring-used",
          "fill-specializations" : [ { "appearance" : "dark", "value" : { "solid" : "srgb:0.64314,0.59216,1.00000,1.00000" } } ] },
        { "image-name" : "1-core.svg", "name" : "1-core",
          "fill-specializations" : [ { "appearance" : "dark", "value" : { "solid" : "srgb:0.64314,0.59216,1.00000,1.00000" } } ] }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : true, "value" : 0.5 }
    }
  ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
```

- [ ] **Step 3: Render để kiểm tra**

Run: với mỗi `r` trong `Default Dark TintedDark ClearLight`, chạy `"$ICTOOL" App/AppIcon.icon --export-image --output-file "$SCRATCH/icon-$r.png" --platform macOS --rendition $r --width 512 --height 512 --scale 1`, rồi mở từng ảnh xem bằng mắt.
Expected:
- Default: nền tím, sáng ở trên và đậm dần xuống dưới; mark trắng; cung remaining mờ hơn rõ rệt.
- Dark: nền gần đen, mark `#A497FF`.
- Bố cục khớp với `previews/agenty-default-liquid-glass-approx.png`.

Nếu render sai mà sửa `icon.json` vẫn không được: ⏸ nhờ người dùng mở Icon Composer, làm theo bước A trong `BRIEF.md` rồi lưu đè `App/AppIcon.icon` (spec §7).

- [ ] **Step 4: Sửa `project.yml` và README**

Trong `project.yml`, thêm `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` vào `targets.Agenty.settings.base`. XcodeGen 2.46 tự nhận `App/AppIcon.icon` là `wrapper.icon` và đưa vào phase Resources, không cần `fileTypes`. Trong `README.md`, thêm `<img src="docs/images/icon.png" width="128" alt="Agenty icon">` ngay trên dòng `# Agenty`.

- [ ] **Step 5: Build, kiểm tra icon có trong app**

Run: lệnh Build Debug chuẩn, rồi `/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' build/DerivedData/Build/Products/Debug/Agenty.app/Contents/Info.plist && ls build/DerivedData/Build/Products/Debug/Agenty.app/Contents/Resources`
Expected: `** BUILD SUCCEEDED **`, `AppIcon`, và danh sách có cả `AppIcon.icns` lẫn `Assets.car`.

- [ ] **Step 6: Commit**

```bash
git add App/AppIcon.icon project.yml docs/images/icon.png README.md
git commit -m "feat(app): add the Agenty app icon"
```

---

### Task 4: `ci.yml` và ruleset

**Files:**
- Modify: `.github/workflows/ci.yml`
- Create: `.github/rulesets/stable.json`, `.github/rulesets/next.json`

**Interfaces:**
- Consumes: `scripts/check-version.sh`, `scripts/test-check-version.sh` (Task 1).
- Produces: check `build`, `scripts`, `version-check`; file JSON ruleset để Task 8 gửi lên `POST /repos/vuxng/agenty/rulesets`.

- [ ] **Step 1: Sửa `ci.yml`**

- Trigger: `push` và `pull_request` vào `branches: [next, stable]`.
- Khai báo `env: XCODE_APP: /Applications/Xcode_27.2.app` ở cấp workflow.
- Job `build`: giữ nguyên, chỉ thay `sudo xcode-select -s /Applications/Xcode_27.2.app` bằng `sudo xcode-select -s "$XCODE_APP"`.
- Job mới `scripts` (`ubuntu-latest`): checkout → `shellcheck scripts/*.sh` (có sẵn trên image) → `bash scripts/test-check-version.sh`.
- Job mới `version-check` (`ubuntu-latest`, `if: github.event_name == 'pull_request' && github.base_ref == 'stable'`): `actions/checkout@v7` với `fetch-depth: 0` → `scripts/check-version.sh`.

- [ ] **Step 2: Viết hai file ruleset**

Định dạng theo REST API rulesets. Chung cho cả hai file: `"target": "branch"`, `"enforcement": "active"`, `"bypass_actors": []`, rule `deletion`, rule `non_fast_forward`, rule `pull_request` với `required_approving_review_count: 0` (các cờ review còn lại để `false`), và rule `required_status_checks` với `strict_required_status_checks_policy: false`.

| File | `name` | `conditions.ref_name.include` | `allowed_merge_methods` | `required_status_checks[].context` |
|---|---|---|---|---|
| `stable.json` | `stable` | `["refs/heads/stable"]` | `["merge"]` | `build`, `scripts`, `version-check` |
| `next.json` | `next` | `["refs/heads/next"]` | `["squash", "merge"]` | `build`, `scripts` |

- [ ] **Step 3: Lint và kiểm tra JSON**

Run: `actionlint .github/workflows/ci.yml && python3 -m json.tool .github/rulesets/stable.json >/dev/null && python3 -m json.tool .github/rulesets/next.json >/dev/null && bash scripts/test-check-version.sh`
Expected: không lỗi; dòng cuối `9 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml .github/rulesets
git commit -m "ci: run on next and stable, add scripts and version-check jobs and rulesets"
```

---

### Task 5: `release.yml`

**Files:**
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `scripts/check-version.sh` (output `version`), `scripts/build-release.sh` (Task 2), 5 secret của environment `release`.
- Produces: tag `v<version>` và GitHub Release đính kèm zip cùng file `.sha256`.

- [ ] **Step 1: Viết workflow**

- `name: Release`; `on: push: branches: [stable]` và `workflow_dispatch:`.
- `concurrency: { group: release, cancel-in-progress: false }`; `permissions: contents: write`.
- `env: XCODE_APP: /Applications/Xcode_27.2.app`, `TEAM_ID: 8WJ6LC5Z59`, `SIGN_IDENTITY: "Developer ID Application: Vu Nguyen (8WJ6LC5Z59)"`.
- Job `release`: `runs-on: xcode-27`, `environment: release`, `if: github.ref == 'refs/heads/stable'`.

Các step, đúng thứ tự:
1. `actions/checkout@v7`, `fetch-depth: 0`.
2. **Require macOS 27**: nếu `sw_vers -productVersion` có major nhỏ hơn 27 thì `::error::` rồi exit 1.
3. **Check version** (`id: version`): `scripts/check-version.sh`.
4. **Select Xcode**: `sudo xcode-select -s "$XCODE_APP"`. **Test core**: `swift test --package-path Packages/UsageCore`. **Install XcodeGen**: `brew install xcodegen`.
5. **Import signing certificate**, với env từ `secrets.DEVELOPER_ID_P12_BASE64` và `secrets.DEVELOPER_ID_P12_PASSWORD`:
   ```bash
   KEYCHAIN="$RUNNER_TEMP/agenty-signing.keychain-db"
   KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
   printf '%s' "$P12_BASE64" | base64 --decode > "$RUNNER_TEMP/cert.p12"
   security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
   security set-keychain-settings -lut 21600 "$KEYCHAIN"
   security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
   security import "$RUNNER_TEMP/cert.p12" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
   rm -f "$RUNNER_TEMP/cert.p12"
   curl -fsSL -o "$RUNNER_TEMP/DeveloperIDG2CA.cer" https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
   security import "$RUNNER_TEMP/DeveloperIDG2CA.cer" -k "$KEYCHAIN" || true
   security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
   # shellcheck disable=SC2046  # intentional word splitting of the existing keychain list
   security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
   echo "SIGN_KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"
   ```
6. **Build, sign, notarize**: giải mã `secrets.NOTARY_KEY_P8_BASE64` thành `$RUNNER_TEMP/AuthKey.p8`, rồi chạy `scripts/build-release.sh "${{ steps.version.outputs.version }}"` với env `NOTARY_KEY_PATH`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` (`SIGN_IDENTITY`, `TEAM_ID`, `SIGN_KEYCHAIN` đã có sẵn trong env).
7. **Verify Gatekeeper**: `ditto -x -k` zip vào `$RUNNER_TEMP/verify`, `spctl --assess --type execute -vv` output phải chứa `source=Notarized Developer ID`, và `xcrun stapler validate` phải pass.
8. **Publish release** (env `GH_TOKEN: ${{ github.token }}`): `gh release create "v$V" "build/Agenty-$V-arm64.zip" "build/Agenty-$V-arm64.zip.sha256" --target "$GITHUB_SHA" --title "Agenty $V" --generate-notes`.
9. **Cleanup** (`if: always()`): `security delete-keychain "$SIGN_KEYCHAIN" || true` và `rm -f "$RUNNER_TEMP/AuthKey.p8"`.

- [ ] **Step 2: Lint**

Run: `actionlint .github/workflows/release.yml`
Expected: không in gì.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow that signs, notarizes and publishes on stable"
```

---

### Task 6: Wizard secrets và README

**Files:**
- Create: `scripts/setup-release-secrets.sh`
- Modify: `README.md` (mục Install, First run: Keychain prompt, Build from source; thêm mục Branches & releases)

**Interfaces:**
- Consumes: tên secret, environment và profile trong Global Constraints.
- Produces: environment `release` với policy `stable`, 5 secret, và profile `agenty-notary` ở local. Task 10 kiểm tra các kết quả này.

- [ ] **Step 1: Viết wizard**

REQUIRED SUB-SKILL: dùng `mattpocock-skills:wizard` để định hình luồng tương tác. Thứ tự các bước:
1. Kiểm tra `gh auth status` và `security find-identity -v -p codesigning` có `Developer ID Application: Vu Nguyen (8WJ6LC5Z59)`.
2. Hướng dẫn xuất `.p12` từ Keychain Access (chọn chứng chỉ kèm private key → Export → `.p12`, đặt mật khẩu). Hỏi đường dẫn file; hỏi mật khẩu bằng `read -rs`; kiểm tra bằng `/usr/bin/openssl pkcs12 -in "$p12" -noout -passin "pass:$pw"`.
3. Hướng dẫn tạo App Store Connect API key (Users and Access › Integrations › Team Keys, quyền Developer, tải `.p8`). Hỏi đường dẫn `.p8`, Key ID và Issuer ID.
4. `gh api --method PUT repos/vuxng/agenty/environments/release` với `deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}`. Sau đó `gh api --method POST repos/vuxng/agenty/environments/release/deployment-branch-policies -f name=stable -f type=branch`; lỗi 422 (đã tồn tại) coi như thành công.
5. Đẩy secret, giá trị chỉ đi qua stdin:
   - `base64 -i "$p12" | gh secret set DEVELOPER_ID_P12_BASE64 --env release --repo vuxng/agenty`;
   - `printf '%s' "$pw" | gh secret set DEVELOPER_ID_P12_PASSWORD …`;
   - làm tương tự cho `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`.
6. `xcrun notarytool store-credentials agenty-notary --key "$p8" --key-id "$key_id" --issuer "$issuer"`.
7. In tóm tắt chỉ gồm tên các secret đã đặt, và nhắc người dùng xoá file `.p12` cùng `.p8` khỏi Downloads.

- [ ] **Step 2: Sửa README**

- **Install:** thay đoạn Gatekeeper và `xattr` bằng: app được ký Developer ID và notarize nên mở được bình thường; kiểm tra file tải về bằng `shasum -a 256 -c Agenty-<version>-arm64.zip.sha256`.
- **First run: Keychain prompt:** thay câu "Every new release build is ad-hoc signed…" bằng: các bản release ký cùng một Developer ID nên "Always Allow" được giữ khi cập nhật; bản tự build từ source ký ad-hoc nên sẽ hỏi lại sau mỗi lần build.
- **Branches & releases** (mục mới, đặt trước License):
  - `next` là nhánh mặc định, mở PR vào đó.
  - `stable` chỉ chứa code đã release.
  - Cách release: tăng `MARKETING_VERSION` trên `next`, mở PR `next → stable`, merge bằng merge commit; CI sẽ ký, notarize và đăng Release `vX.Y.Z`.
  - Hotfix: rẽ từ `stable`, merge xong thì mở PR `stable → next`.
- **Build from source:** giữ dòng `scripts/build-release.sh <version>`, ghi thêm rằng đặt `SIGN_IDENTITY`/`TEAM_ID` thì ký Developer ID, đặt `NOTARY_KEYCHAIN_PROFILE` thì notarize.

- [ ] **Step 3: Lint**

Run: `shellcheck scripts/*.sh && bash -n scripts/setup-release-secrets.sh && grep -nE 'set -x|echo .*\$(pw|p12_password|key_id|issuer)' scripts/setup-release-secrets.sh`
Expected: shellcheck không in gì; `grep` không khớp dòng nào (exit 1).

- [ ] **Step 4: Commit**

```bash
git add scripts/setup-release-secrets.sh README.md
git commit -m "docs: document stable/next releases and add the release secrets wizard"
```

---

### Task 7: Quét trước khi public

**Files:** không sửa file nào (nếu có phát hiện thì ⏸ dừng lại).

- [ ] **Step 1: gitleaks trên toàn bộ ref ở local**

Run: `gitleaks git --log-opts="--all" --redact -v .`
Expected: `no leaks found`.

- [ ] **Step 2: Đọc tay fixture và email trong commit**

Run: `grep -nEi 'sk-|eyJ|token|@|account|org|uuid' docs/superpowers/spikes/fixtures/*.json; git log --all --format='%ae%n%ce' | sort -u`
Expected:
- Fixture chỉ chứa số liệu usage, không có token, email hay ID tài khoản thật.
- Email trong commit chỉ là dạng `…@users.noreply.github.com`.

- [ ] **Step 3: ⏸ Nếu có phát hiện**

Dừng lại, báo người dùng chính xác file, commit và dòng. Viết lại lịch sử là quyết định của người dùng; không làm Task 8 khi chưa có quyết định.

---

### Task 8: Public, đổi nhánh, ruleset

**Files:** không sửa file nào (thao tác trên GitHub).

**Interfaces:**
- Consumes: `.github/rulesets/*.json` (Task 4) ở working tree local.
- Produces: repo public; `next` là mặc định; có `stable`; không còn `main`; 2 ruleset đang `active`.

- [ ] **Step 1: ⏸ Xác nhận public**

Hỏi người dùng lần cuối (AskUserQuestion), kèm kết quả Task 7. Chỉ tiếp tục khi người dùng trả lời "có".

- [ ] **Step 2: Public**

Run: `gh repo edit vuxng/agenty --visibility public --accept-visibility-change-consequences && gh repo view vuxng/agenty --json visibility --jq .visibility`
Expected: `PUBLIC`.

- [ ] **Step 3: Tạo nhánh và cài đặt repo**

Run: `git push origin 37e2fff:refs/heads/next 37e2fff:refs/heads/stable && gh repo edit vuxng/agenty --default-branch next --enable-rebase-merge=false --delete-branch-on-merge`
Expected: push được hai nhánh mới; `gh run list -L 3` không có run mới nào cho `next` hoặc `stable` (ở `37e2fff`, `ci.yml` chỉ trigger cho `main`).

- [ ] **Step 4: Xoá `main`**

Run: `gh pr list --repo vuxng/agenty --base main --state open` (phải rỗng) → `git push origin --delete main` → `git branch -d main` → `git fetch --prune && git remote set-head origin -a`
Expected: `origin/HEAD set to next`; `git branch -a` không còn `main`.

- [ ] **Step 5: Tạo ruleset**

Run: `gh api --method POST repos/vuxng/agenty/rulesets --input .github/rulesets/stable.json && gh api --method POST repos/vuxng/agenty/rulesets --input .github/rulesets/next.json && gh api repos/vuxng/agenty/rules/branches/stable --jq '[.[].type] | sort'`
Expected: `["deletion","non_fast_forward","pull_request","required_status_checks"]`.

---

### Task 9: PR CI/CD vào `next`

- [ ] **Step 1: Push và mở PR**

Viết body bằng skill `mattpocock-skills:pr`, không có footer Claude Code.
Run: `git push -u origin ci/stable-next-release && gh pr create --repo vuxng/agenty --base next --head ci/stable-next-release --title "ci: stable/next releases with Developer ID signing, notarization and app icon" --body-file "$SCRATCH/pr-body.md"`
Expected: in ra URL của PR.

- [ ] **Step 2: Chờ CI**

Run: `gh pr checks --watch`
Expected: `build` và `scripts` pass; `version-check` skipped.

- [ ] **Step 3: Squash merge và dọn local**

Run: `gh pr merge --squash --delete-branch && git switch next && git pull --ff-only && git branch -D ci/stable-next-release`
Expected: merge thành công; `git log -1 --oneline` là commit squash.

---

### Task 10: ⏸ Secrets và notarize ở local

- [ ] **Step 1: ⏸ Người dùng chạy wizard**

Nhắn người dùng chạy `scripts/setup-release-secrets.sh` trong một terminal riêng (wizard cần nhập ẩn). Chờ người dùng báo xong.

- [ ] **Step 2: Kiểm tra kết quả wizard**

Run: `gh secret list --env release --repo vuxng/agenty --json name --jq '[.[].name] | sort' && gh api repos/vuxng/agenty/environments/release/deployment-branch-policies --jq '[.branch_policies[].name]' && xcrun notarytool history --keychain-profile agenty-notary >/dev/null && echo profile-ok`
Expected: `["DEVELOPER_ID_P12_BASE64","DEVELOPER_ID_P12_PASSWORD","NOTARY_ISSUER_ID","NOTARY_KEY_ID","NOTARY_KEY_P8_BASE64"]`, rồi `["stable"]`, rồi `profile-ok`.

- [ ] **Step 3: Build ký và notarize ở local**

Run: `SIGN_IDENTITY="Developer ID Application: Vu Nguyen (8WJ6LC5Z59)" TEAM_ID=8WJ6LC5Z59 NOTARY_KEYCHAIN_PROFILE=agenty-notary scripts/build-release.sh 0.1.0`
Expected: notarytool báo `Accepted`; có dòng `The validate action worked!`; spctl báo `source=Notarized Developer ID`; dòng cuối `Created build/Agenty-0.1.0-arm64.zip`. Nếu bị từ chối, sửa theo `notarytool log` trên một nhánh `fix/*` → PR vào `next`, rồi chạy lại bước này.

---

### Task 11: ⏸ Release `v0.1.0`

- [ ] **Step 1: Mở PR release**

Run: `gh pr create --repo vuxng/agenty --base stable --head next --title "Release 0.1.0" --body "First release: Claude and Codex usage in the menu bar, Developer ID signed and notarized."`
Expected: in ra URL của PR.

- [ ] **Step 2: Chờ check**

Run: `gh pr checks --watch`
Expected: `build`, `scripts`, `version-check` đều pass.

- [ ] **Step 3: ⏸ Người dùng merge**

Người dùng bấm **Create a merge commit** trên GitHub, hoặc đồng ý cho chạy `gh pr merge --merge`.

- [ ] **Step 4: Theo dõi release**

Run: `gh run watch "$(gh run list --repo vuxng/agenty --workflow Release -L 1 --json databaseId --jq '.[0].databaseId')" --exit-status`
Expected: mọi step đều xanh.

- [ ] **Step 5: Kiểm tra Release**

Run: `gh release view v0.1.0 --repo vuxng/agenty --json tagName,assets --jq '{tag: .tagName, assets: [.assets[].name]}'`
Expected: `{"tag":"v0.1.0","assets":["Agenty-0.1.0-arm64.zip","Agenty-0.1.0-arm64.zip.sha256"]}`.

- [ ] **Step 6: Kiểm tra bản tải về**

Run: `D="$SCRATCH/release-check" && mkdir -p "$D" && gh release download v0.1.0 --repo vuxng/agenty -D "$D" && cd "$D" && shasum -a 256 -c Agenty-0.1.0-arm64.zip.sha256 && ditto -x -k Agenty-0.1.0-arm64.zip . && spctl --assess --type execute -vv Agenty.app && syspolicy_check distribution Agenty.app`
Expected: `OK`; `accepted` cùng `source=Notarized Developer ID`; `App passed all pre-distribution checks`. Sau đó ⏸ người dùng tải zip bằng trình duyệt từ trang Releases rồi mở app: không bị Gatekeeper chặn, Keychain hỏi đúng một lần.

- [ ] **Step 7: `next` vẫn còn, dọn local**

Run: `gh api repos/vuxng/agenty/branches/next --jq .name && git fetch --tags --prune && git switch next && git pull --ff-only`
Expected: `next`; trong `git tag` có `v0.1.0`.
