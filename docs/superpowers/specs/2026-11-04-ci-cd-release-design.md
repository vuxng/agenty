# Agenty — CI/CD, mô hình nhánh stable/next, app icon và release v0.1.0

- **Ngày:** 2026-11-04
- **Trạng thái:** Draft — chờ duyệt
- **Repo:** github.com/vuxng/agenty

## 1. Mục tiêu

Có một luồng phát hành lặp lại được cho Agenty: làm việc trên `next`, release bằng cách merge vào
`stable`, và mỗi bản release là một file zip đã ký Developer ID, đã notarize, tải về là mở được.
Kèm theo app icon chính thức, rồi phát hành bản đầu tiên `v0.1.0`.

**Thành công khi:**
- Không còn nhánh `main`. `next` là nhánh mặc định. Ruleset đang bật cho cả `stable` và `next`.
- PR vào `stable` mà quên tăng version thì bị check `version-check` chặn.
- Có GitHub Release `v0.1.0` với `Agenty-0.1.0-arm64.zip` (đã notarize + staple) và file `.sha256`.
- Tải zip về, giải nén, mở được ngay: không cần `xattr`, không cần Open Anyway.
  `spctl --assess --type execute -vv` báo `accepted` và `source=Notarized Developer ID`.
- `Agenty.app` có icon mới (Icon Composer, có biến thể Dark và Mono).

## 2. Phạm vi

### Trong phạm vi
- Mô hình nhánh `stable`/`next`, ruleset, cài đặt repo.
- `ci.yml` (sửa), `release.yml` (mới).
- `scripts/build-release.sh` (sửa), `scripts/check-version.sh` (mới) và test của nó.
- Ký Developer ID + notarize trong CI, secrets trong GitHub Environment `release`.
- Wizard bash giúp người dùng tạo secrets.
- App icon dạng `App/AppIcon.icon` từ gói `agenty-handoff.zip`.
- Cập nhật README: icon, cách cài, ghi chú Keychain, mục "Branches & releases".
- Chuyển repo sang public.
- Release `v0.1.0`.

### Ngoài phạm vi
- Glyph thanh menu mới trong gói handoff. Giữ nguyên 3 kiểu glyph động hiện có.
- Bản pre-release tự động từ `next`.
- Sparkle auto-update, Homebrew cask, `CHANGELOG.md`, release-please.

## 3. Mô hình nhánh

| Nhánh | Vai trò | Nhận PR từ | Cách merge cho phép |
|---|---|---|---|
| `next` | Mặc định, nơi tích hợp | `feat/*`, `fix/*`, `ci/*`, … và PR merge ngược `stable → next` | Squash (feature), merge commit (merge ngược) |
| `stable` | Release: mỗi merge là một bản phát hành, có tag `vX.Y.Z` | Chỉ `next` hoặc `hotfix/*` | Chỉ merge commit |

`stable` cấm squash và rebase. Hai cách đó tạo commit mới khiến `next` và `stable` lệch lịch sử và
lần release sau bị conflict giả.

**Luồng thường:** `feat/x` → PR → `next` (squash). Khi muốn release: trên `next` tăng
`MARKETING_VERSION` trong `project.yml`, mở PR `next → stable`, merge bằng merge commit.

**Hotfix:** `hotfix/x` rẽ từ `stable` → PR vào `stable` (tăng bản patch) → release tự chạy →
mở PR `stable → next` (merge commit) để mang bản sửa về.

### Ruleset

Cả hai nhánh: cấm xoá, cấm force push, bắt buộc qua PR, 0 approval (một người làm), không có
bypass actor (khẩn cấp thì sửa ruleset).

| Ruleset | Required status checks | Allowed merge methods |
|---|---|---|
| `stable` | `build`, `scripts`, `version-check` | `merge` |
| `next` | `build`, `scripts` | `squash`, `merge` |

### Cài đặt repo
- Default branch: `next`.
- Automatically delete head branches: bật. `next` là nhánh mặc định nên không bị xoá; `stable` được
  rule "cấm xoá" bảo vệ khi là head của PR merge ngược (kiểm tra lại ở lần merge ngược đầu tiên).
- Tắt rebase merge ở mức repo. Squash và merge commit vẫn bật; ruleset giới hạn theo nhánh.

## 4. Pipelines

Workflow chỉ gọi script. Mọi logic build, ký, notarize, kiểm tra version nằm trong `scripts/` để
chạy y hệt ở local.

### 4.1 `.github/workflows/ci.yml` (sửa)

Trigger: `push` và `pull_request` vào `[next, stable]`.

| Job | Runner | Chạy khi | Làm gì |
|---|---|---|---|
| `build` | `xcode-27` | Mọi push/PR | `scripts/test-build-release.sh` và `scripts/test-make-appcast.sh` (toolchain giả, chỉ cần macOS), rồi như cũ: guard macOS 27 (bỏ qua nếu runner thấp hơn), chọn Xcode 27.2, `swift test` cho UsageCore, `xcodegen generate`, build Debug với `CODE_SIGNING_ALLOWED=NO` |
| `scripts` | `ubuntu-latest` | Mọi push/PR | `shellcheck scripts/*.sh`, `test-check-version.sh`, `test-publish-release.sh`, `test-setup-release-secrets.sh` |
| `version-check` | `ubuntu-latest` | Chỉ `pull_request` vào `stable` | Checkout `fetch-depth: 0`, chạy `scripts/check-version.sh` |

`version-check` nằm trong workflow riêng `.github/workflows/version-check.yml` (chỉ trigger `pull_request` vào `stable`).
Nếu để chung `ci.yml`, mỗi lần push vào `next` sẽ sinh một run `version-check` bị skip trên commit đó, và check bắt buộc của
`stable` có thể coi run skip ấy là pass. Job `scripts` dùng ShellCheck 0.11.0 cố định (`shellcheck-py==0.11.0.1`) cho khớp với local.
`ci.yml` chỉ có `permissions: contents: read`.

### 4.2 `.github/workflows/release.yml` (mới)

- Trigger: `push` vào `stable`, và `workflow_dispatch` để chạy lại khi lỗi tạm thời.
- Job chỉ chạy khi `github.ref == 'refs/heads/stable'`.
- `concurrency: { group: release, cancel-in-progress: false }`.
- `permissions: contents: write`.
- `environment: release`. Secrets nằm ở environment này, deployment branch policy chỉ cho `stable`.
- Runner `xcode-27`. Nếu runner không phải macOS 27 thì **báo lỗi** (khác CI là bỏ qua).
- `timeout-minutes: 90`; riêng notarize bị chặn 1 giờ (`notarytool --timeout 1h`).
- `REQUIRE_NOTARIZATION=1`: thiếu identity hoặc thông tin notarize thì `build-release.sh` dừng trước khi build.

Các bước:
1. Checkout `fetch-depth: 0`.
2. `scripts/check-version.sh` → lấy `version`. Nếu tag đã có thì dừng với thông báo rõ ràng.
3. Chọn Xcode 27.2, `swift test --package-path Packages/UsageCore`, cài XcodeGen.
4. Nạp chứng chỉ vào keychain tạm:
   - mật khẩu keychain sinh ngẫu nhiên (`openssl rand`);
   - `security create-keychain`, `set-keychain-settings -lut 21600`, `unlock-keychain`;
   - `security import` file `.p12` (giải mã base64 vào `$RUNNER_TEMP`), rồi
     `set-key-partition-list -S apple-tool:,apple:`;
   - thêm keychain tạm vào search list;
   - nạp chứng chỉ trung gian Developer ID G2 từ `https://www.apple.com/certificateauthority/`
     (curl có retry) nếu runner chưa có; nhận biết theo SHA-256 vì G1 trùng tên;
   - xoá file `.p12` ngay sau khi import.
5. Một bước riêng ghi API key `.p8` vào `$RUNNER_TEMP` và xuất `NOTARY_KEY_PATH`, nên nội dung key
   không nằm trong env của bước build. Rồi chạy `scripts/build-release.sh "$version"` với
   `SIGN_IDENTITY`, `TEAM_ID=8WJ6LC5Z59`, `NOTARY_KEY_PATH`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`.
6. Kiểm tra Gatekeeper độc lập: giải nén zip vào thư mục tạm, `spctl --assess --type execute -vv`
   phải có `source=Notarized Developer ID`; `xcrun stapler validate` phải pass.
7. Sinh release notes (`gh api …/releases/generate-notes` → `build/notes.md`), rồi `scripts/make-appcast.sh "$version"`
   (khoá Sparkle qua stdin, chỉ bước này thấy secret `SPARKLE_ED_PRIVATE_KEY`) → `build/appcast.xml`. Chi tiết ở
   `docs/superpowers/specs/2026-11-04-auto-update-design.md` §5.
8. `scripts/publish-release.sh "$version"`: `gh release create "v$version" <zip> <zip>.sha256 build/appcast.xml --target "$GITHUB_SHA" --title "Agenty $version" --notes-file build/notes.md`.
   **Tag chỉ được tạo ở bước này.** Bước nào trước đó lỗi thì không có tag, không có release,
   chạy lại an toàn. Nếu upload lỗi và còn sót bản draft thì script xoá draft đó; release đã
   publish thì không bao giờ bị xoá. Test: `scripts/test-publish-release.sh` (gh giả).
9. (`if: always()`) Xoá keychain tạm, file `.p8` và file tạm.

## 5. Scripts

### 5.1 `scripts/check-version.sh` (mới)

- Không tham số. Biến môi trường tuỳ chọn `PROJECT_YML` (mặc định `project.yml`) để test.
- Đọc dòng `MARKETING_VERSION:` trong `project.yml`, bỏ dấu nháy và khoảng trắng.
- Báo lỗi (exit 1, thông báo rõ) khi:
  - không tìm thấy hoặc không khớp `^[0-9]+\.[0-9]+\.[0-9]+$`;
  - tag `v<version>` đã tồn tại;
  - version không lớn hơn tag `v*` mới nhất (so bằng `sort -V`).
- Thành công: in `version=<version>` ra stdout, và ghi thêm vào `$GITHUB_OUTPUT` nếu biến này có.
- Phụ thuộc: các tag đã được fetch (caller checkout `fetch-depth: 0`).

`scripts/test-check-version.sh`: tạo repo git tạm trong `mktemp -d`, chạy các ca: chưa có tag
(pass), tag trùng (fail), version nhỏ hơn tag mới nhất (fail), version lớn hơn (pass), version sai
định dạng (fail), `GITHUB_OUTPUT` được ghi đúng.

### 5.2 `scripts/build-release.sh <version>` (sửa)

Một script cho cả local và CI. Kết quả: `build/Agenty-<version>-arm64.zip` và
`build/Agenty-<version>-arm64.zip.sha256`.

| Biến môi trường | Ý nghĩa |
|---|---|
| (không có `SIGN_IDENTITY`) | Ký ad-hoc như hiện tại (`codesign --force --deep --options runtime --sign -`) |
| `SIGN_IDENTITY` | Ký Developer ID. Cần thêm `TEAM_ID` |
| `NOTARY_KEYCHAIN_PROFILE` | Notarize bằng profile `notarytool store-credentials` (dùng ở local) |
| `NOTARY_KEY_PATH` + `NOTARY_KEY_ID` + `NOTARY_ISSUER_ID` | Notarize bằng App Store Connect API key (dùng trong CI) |
| `REQUIRE_NOTARIZATION=1` | Dừng trước khi build nếu thiếu `SIGN_IDENTITY`, thiếu thông tin notarize, hoặc file key rỗng (dùng trong CI) |
| `BUILD_NUMBER` | Mặc định `git rev-list --count HEAD` |

Luồng khi có `SIGN_IDENTITY`:
1. `xcodegen generate`.
2. `xcodebuild … -configuration Release build` với `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`,
   `CODE_SIGN_STYLE=Manual`, `CODE_SIGN_IDENTITY="$SIGN_IDENTITY"`, `DEVELOPMENT_TEAM="$TEAM_ID"`,
   `OTHER_CODE_SIGN_FLAGS=--timestamp`, `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`. Không dùng `--deep`.
3. `codesign --verify --strict --deep`; `codesign -dvv` phải có `Authority=Developer ID Application`,
   `TeamIdentifier=$TEAM_ID`, cờ `runtime` và `Timestamp=`.
4. `lipo -archs` phải đúng `arm64`.
5. Nếu có thông tin notarize: `ditto` ra zip → `xcrun notarytool submit --wait --timeout 1h --output-format json`
   → status phải là `Accepted`, nếu không thì in `notarytool log <id>` rồi exit 1 →
   `xcrun stapler staple` + `stapler validate` → zip lại → `spctl --assess` phải có
   `Notarized Developer ID`.
6. Ghi `shasum -a 256`.

Không notarize thì in `notice: skipping notarization (ad-hoc build)` hoặc `(no credentials)` tuỳ trường hợp.
Test: `scripts/test-build-release.sh` chạy script với toolchain giả (`xcodegen`, `xcodebuild`, `codesign`,
`xcrun`, …), không build hay ký thật.

## 6. Secrets và thiết lập do người dùng làm

Secrets trong environment `release`:

| Secret | Nguồn |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Chứng chỉ "Developer ID Application: Vu Nguyen (8WJ6LC5Z59)" kèm private key, xuất từ Keychain Access ra `.p12`, mã hoá base64 |
| `DEVELOPER_ID_P12_PASSWORD` | Mật khẩu đặt khi xuất `.p12` |
| `NOTARY_KEY_P8_BASE64` | App Store Connect API key (Users and Access › Integrations › Team Keys, quyền Developer), file `.p8` mã hoá base64 |
| `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | Key ID và Issuer ID của API key đó |

Không phải bí mật, ghi thẳng trong workflow: `TEAM_ID=8WJ6LC5Z59`,
`SIGN_IDENTITY="Developer ID Application: Vu Nguyen (8WJ6LC5Z59)"`.

`scripts/setup-release-secrets.sh` là wizard tương tác chỉ dùng một lần:
1. Hướng dẫn xuất `.p12` và tạo API key, chờ người dùng nhập đường dẫn file.
2. Tạo environment `release` với deployment branch policy chỉ `stable` (`gh api`).
3. Đẩy 5 secret bằng `gh secret set --env release`, đọc từ file hoặc nhập ẩn. Không in secret ra
   màn hình.
4. Chạy `xcrun notarytool store-credentials agenty-notary` để có profile notarize ở local.

Secret không bao giờ đi qua chat.

## 7. App icon

Nguồn: `/Users/vu/Downloads/agenty-handoff.zip` (giải nén vào scratchpad, không chạy gì trong đó).
Hình học đã chốt, không vẽ lại.

- Tạo `App/AppIcon.icon` (định dạng Icon Composer) theo phương án A trong `BRIEF.md`:
  - Fill: gradient dọc `#7C6BF2 → #4B35CF`.
  - Một group gồm 3 lớp `1-core.svg`, `2-ring-used.svg`, `3-ring-remaining.svg`; lớp remaining
    opacity 0.38.
  - Dark: nền `#2E2D33 → #151418`, mark `#A497FF`. Mono: mark `#FFFFFF`.
  - Liquid Glass, specular và shadow để mặc định.
- `project.yml`: thêm `AppIcon.icon` vào resources của target và
  `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.
- README: thêm icon 128 px ở đầu trang (`docs/images/icon.png`, lấy từ `png/agenty-256.png`).
- Không đưa `previews/*.png` vào app.

Kiểm tra:
- `ictool AppIcon.icon --export-image` cho các rendition Default, Dark, TintedDark, ClearLight
  (platform macOS) ra scratchpad, so bằng mắt với `previews/`.
- Sau khi build: `Agenty.app/Contents/Info.plist` có `CFBundleIconName = AppIcon`, và
  `Contents/Resources` có `Assets.car` cùng `AppIcon.icns`.

Phương án dự phòng: nếu `icon.json` viết tay không render đúng, người dùng mở Icon Composer và làm
theo bước A trong brief (khoảng 5 phút), lưu đè vào `App/AppIcon.icon`. Nếu XcodeGen 2.46 không
nhận loại file `.icon`, khai báo tường minh trong `sources` với `buildPhase: resources`.

## 8. Thứ tự thực hiện

Các bước có ⏸ cần người dùng xác nhận hoặc tự làm.

1. **Quét lịch sử git:** `gitleaks git` trên toàn bộ lịch sử (`--log-opts=--all`), đọc tay
   `docs/superpowers/spikes/fixtures/*.json`. Có phát hiện thì ⏸ dừng, báo người dùng; viết lại lịch
   sử là quyết định của người dùng.
2. ⏸ **Chuyển repo public:** người dùng xác nhận lần cuối, rồi
   `gh repo edit --visibility public --accept-visibility-change-consequences`.
3. **Đổi nhánh:** push `next` và `stable` từ `37e2fff` (commit này chưa có `release.yml`, nên tạo
   `stable` không kích hoạt release); đặt default `next`; bật auto-delete head branches; tắt rebase
   merge; xoá `main` ở remote và local; tạo hai ruleset ở §3.
4. **Nhánh `ci/stable-next-release`** (đã có ở local, cùng gốc `37e2fff` với `next`): spec này,
   scripts, workflows, icon, README. Kiểm tra local: `shellcheck`, `test-check-version.sh`, build
   ad-hoc `scripts/build-release.sh 0.1.0` có icon. Mở PR vào `next`; CI xanh thì Claude squash merge
   (người dùng đã duyệt bước này qua spec).
5. ⏸ **Người dùng chạy wizard** `scripts/setup-release-secrets.sh`.
6. **Thử ký và notarize ở local:**
   `SIGN_IDENTITY="Developer ID Application: Vu Nguyen (8WJ6LC5Z59)" TEAM_ID=8WJ6LC5Z59 NOTARY_KEYCHAIN_PROFILE=agenty-notary scripts/build-release.sh 0.1.0`
   → `spctl` báo `Notarized Developer ID`.
7. ⏸ **Release `v0.1.0`:** mở PR `next → stable` (version `0.1.0`, chưa có tag, nên `version-check`
   xanh). Người dùng bấm merge (merge commit). Theo dõi `release.yml`, rồi tải zip từ Release về
   (có quarantine), giải nén, kiểm tra `spctl` và mở app.

## 9. Xử lý lỗi

| Tình huống | Hành vi |
|---|---|
| Quên tăng version | `version-check` đỏ ở PR vào `stable`, ruleset chặn merge. `release.yml` cũng dừng ở bước 2 |
| Notarize bị từ chối | Script in `notarytool log`, job đỏ, không có tag. Sửa trên `next`, release lại |
| Apple/mạng lỗi tạm thời | Chạy lại bằng `workflow_dispatch` trên `stable` |
| Runner không phải macOS 27 | `release.yml` đỏ ngay (CI thì bỏ qua như hiện tại) |
| Đã release rồi mà chạy lại | `check-version.sh` thấy tag đã có, dừng với thông báo "already released" |
| Secret sai hoặc hết hạn | Bước import hoặc notarize đỏ, log nói rõ bước nào. Không có tag |

## 10. Rủi ro và lưu ý

- `xcode-27` là image preview; tên image hoặc đường dẫn Xcode có thể đổi. Mỗi workflow khai báo
  đường dẫn Xcode một lần trong `env:` ở đầu file, đổi thì sửa hai chỗ đó.
- Lần đầu chuyển từ ad-hoc sang Developer ID, quyền "Always Allow" trong Keychain cũ (gắn với chữ ký
  ad-hoc) mất hiệu lực, nên macOS hỏi lại **một lần**. Từ đó về sau chữ ký gắn với Team ID nên các
  bản cập nhật giữ được quyền. Cập nhật README cho đúng.
- Hardened runtime đã bật sẵn. App gọi tiến trình con (`claude`, `codex`) và đọc Keychain, những
  việc này không cần entitlement thêm. Nếu notarize báo thiếu thì xử lý theo log.
- Định dạng `icon.json` không có tài liệu công khai đầy đủ; đã có phương án dự phòng ở §7.
