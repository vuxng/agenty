# Agenty — tự cập nhật bằng Sparkle, release v0.2.0

- **Ngày:** 2026-11-04
- **Trạng thái:** Draft — chờ duyệt
- **Repo:** github.com/vuxng/agenty
- **Dựa trên:** `docs/superpowers/specs/2026-11-04-ci-cd-release-design.md` (luồng `next`/`stable`, `release.yml`)

## 1. Mục tiêu

Hiện Agenty không có cơ chế cập nhật: người dùng phải tự vào GitHub Releases tải bản mới và thay app.
Từ bản 0.2.0, Agenty tự kiểm tra bản mới mỗi ngày bằng Sparkle 2. Khi có bản mới, app hỏi người dùng
rồi tự tải, kiểm tra chữ ký, thay app và mở lại.

**Thành công khi:**
- Một bản Agenty cũ hơn (cùng Developer ID) bấm "Check for Updates…" thì Sparkle đề nghị bản mới nhất.
  Bấm Install thì app được thay và mở lại thành bản mới, Keychain không hỏi lại quyền.
- Kiểm tra định kỳ thấy bản mới khi app đang chạy nền thì không bật cửa sổ chen ngang. Popover hiện
  dòng nhắc, bấm vào mới mở hộp thoại Sparkle.
- Mỗi GitHub Release có thêm `appcast.xml`, và `https://github.com/vuxng/agenty/releases/latest/download/appcast.xml`
  trả về item của bản mới nhất với chữ ký EdDSA đúng.
- Secret EdDSA trên CI không khớp với khoá công khai trong app thì workflow dừng trước khi publish.
- Release `v0.2.0` được phát hành qua luồng hiện có (merge `next → stable`).

## 2. Phạm vi

### Trong phạm vi
- Sparkle 2.10.1 qua SPM, chỉ cho target app.
- `App/System/Updater.swift` (mới), section Updates trong Settings, dòng nhắc trong popover.
- `scripts/build-release.sh`: ký lại Sparkle bằng Developer ID.
- `scripts/make-appcast.sh` và `scripts/verify-ed-signature.swift` (mới), `scripts/publish-release.sh` (sửa), cùng test.
- `release.yml`: release notes, appcast, upload appcast.
- Tạo khoá EdDSA, secret `SPARKLE_ED_PRIVATE_KEY`.
- README: cách cập nhật, việc phải tự cài 0.2.0 một lần, chuyện mất khoá.
- Release `v0.2.0`.

### Ngoài phạm vi
- Delta update, appcast nhiều phiên bản, GitHub Pages.
- Tự cài lặng lẽ (`SUAutomaticallyUpdate`), kênh beta.
- Thông báo hệ thống (User Notification) cho bản mới.
- Homebrew cask.
- Thêm stage Sparkle vào wizard `setup-release-secrets.sh`.

## 3. Quyết định đã chốt

| Câu hỏi | Chọn |
|---|---|
| Mức cập nhật | Tự cài bằng Sparkle |
| Cách cập nhật | Tự kiểm tra mỗi ngày, hỏi trước khi cài. Bật sẵn, tắt được trong Settings |
| Nơi đặt appcast | Asset của chính GitHub Release, đọc qua `releases/latest/download/appcast.xml` |

## 4. Phía app

### 4.1 Dependency và Info.plist

`project.yml`:
- `packages: Sparkle: { url: https://github.com/sparkle-project/Sparkle, exactVersion: 2.10.1 }` (bản mới nhất, phát hành 2026-10-25;
  release notes dạng markdown cần từ 2.9 trở lên).
  `Agenty.xcodeproj` bị gitignore nên `Package.resolved` không được commit; `exactVersion` là chỗ ghim.
- Target `Agenty` thêm dependency `package: Sparkle`. `UsageCore` không đổi.
- `info.properties`:
  - `SUFeedURL`: `https://github.com/vuxng/agenty/releases/latest/download/appcast.xml`
  - `SUPublicEDKey`: khoá công khai (mục 6)
  - `SUEnableAutomaticChecks`: `true`. Bật sẵn, không hiện hộp thoại xin phép của Sparkle.
  - Không đặt `SUScheduledCheckInterval` (mặc định 86400 giây) và `SUAutomaticallyUpdate` (mặc định tắt).

### 4.2 `App/System/Updater.swift` (mới)

`@Observable @MainActor final class Updater: NSObject`, do `AppModel` giữ (`let updater: Updater`).

- Bọc `SPUStandardUpdaterController`. Chính `Updater` là `SPUUpdaterDelegate` và
  `SPUStandardUserDriverDelegate`.
- `#if DEBUG`: không khởi động updater (`startingUpdater: false`). Bản Debug có `CFBundleVersion = 1`,
  nên nếu chạy thì lúc nào cũng thấy "có bản mới".
- Cung cấp cho UI:
  - `isEnabled: Bool`: `false` ở bản Debug.
  - `canCheckForUpdates: Bool`: theo `SPUUpdater.canCheckForUpdates` (KVO).
  - `automaticallyChecksForUpdates: Bool`: get/set thẳng vào `SPUUpdater`, Sparkle tự lưu.
  - `availableVersion: String?`: phiên bản mà lời nhắc nhẹ đang báo, `nil` khi không có.
  - `checkForUpdates()`: đưa app lên trước (`NSApp.activate()`), rồi gọi `updaterController.checkForUpdates(nil)`.
- Lời nhắc nhẹ (gentle reminders):
  - `supportsGentleScheduledUpdateReminders` trả `true`.
  - `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)` trả `immediateFocus`.
    Vừa mở app thì Sparkle hiện hộp thoại luôn; lúc khác app tự lo.
  - `standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)`: nếu Sparkle không tự hiện
    (`handleShowingUpdate == false`) thì gán `availableVersion = update.displayVersionString`.
    Nếu Sparkle tự hiện thì đưa app lên trước để hộp thoại không bị che.
  - `standardUserDriverWillFinishUpdateSession()`: gán `availableVersion = nil`.

### 4.3 Giao diện

Chuỗi tiếng Anh dưới đây là key trong `Localizable.xcstrings`; mỗi chuỗi có bản dịch `vi`, như 62 chuỗi hiện có.
Hộp thoại của Sparkle dùng bản địa hoá của Sparkle.

**Settings**, section mới `Updates`, đặt cuối form:
- `Toggle("Check for updates automatically")`, gắn với `automaticallyChecksForUpdates`.
- `Button("Check for Updates…")`, disabled khi `!canCheckForUpdates`.
- `Text("Version \(short) (\(build))")`, chữ caption, màu secondary.
- Bản Debug: toggle và nút bị disabled, thêm caption `Updates are off in debug builds`.

**Popover**: khi `availableVersion != nil`, phía trên footer hiện một hàng gồm
`Text("Agenty \(version) is available")` và `Button("Install…")`, nút gọi `checkForUpdates()`.

### 4.4 Keychain

Bản cập nhật được ký cùng Developer ID và cùng designated requirement. Quyền "Always Allow" đã cấp cho
Keychain vẫn còn sau khi cập nhật.

## 5. Build, ký và phát hành

### 5.1 `scripts/build-release.sh` (sửa)

Nhánh Developer ID, ngay sau `xcodebuild`, ký lại từ trong ra ngoài. `F` là
`Agenty.app/Contents/Frameworks/Sparkle.framework`. Mọi lần ký dùng
`codesign -f -s "$SIGN_IDENTITY" -o runtime --timestamp` (thêm `--keychain "$SIGN_KEYCHAIN"` nếu có), và
**không dùng `--deep`**:

1. `$F/Versions/B/XPCServices/Installer.xpc`
2. `$F/Versions/B/XPCServices/Downloader.xpc`, thêm `--preserve-metadata=entitlements`
3. `$F/Versions/B/Autoupdate`
4. `$F/Versions/B/Updater.app`
5. `$F`
6. `Agenty.app`, thêm `--preserve-metadata=entitlements` (sửa phần lồng bên trong làm hỏng chữ ký cũ của app)

Kiểm tra: vòng `codesign -dvv` hiện có (`Authority=Developer ID Application`, `TeamIdentifier=$TEAM_ID`,
`(runtime)`, `Timestamp=`) chạy cho app và cả 5 thành phần trên, rồi `codesign --verify --strict --deep`.
Thiếu một điều kiện thì exit 1 **trước** khi notarize, và thông báo lỗi nêu rõ thành phần nào thiếu gì.

Bản ad-hoc không đổi: `codesign --force --deep --sign -` đã ký cả các helper.

Kết quả vẫn là zip và `.sha256`. Script không sinh appcast.

### 5.2 `scripts/make-appcast.sh <version>` (mới)

- **Đầu vào:**
  - `build/Agenty-<version>-arm64.zip`;
  - `build/notes.md`;
  - khoá bí mật EdDSA qua **stdin**.
  - Biến tuỳ chọn `SPARKLE_BIN`, mặc định `build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin`, để test.
- **Các bước:**
  1. stdin rỗng thì exit 1, báo `Sparkle private key is missing`.
  2. Giải nén zip vào thư mục tạm. Đọc `CFBundleVersion`, `CFBundleShortVersionString`, `SUPublicEDKey`
     và `LSMinimumSystemVersion` từ `Info.plist` của app trong zip.
  3. Ký zip bằng `"$SPARKLE_BIN/sign_update" --ed-key-file - <zip>`, với khoá đưa vào qua stdin, không bao giờ
     qua đối số. Lấy `sparkle:edSignature` và `length` từ output.
  4. Kiểm tra chữ ký vừa tạo bằng `SUPublicEDKey` đọc ở bước 2:
     `swift scripts/verify-ed-signature.swift <zip> <signature> <SUPublicEDKey>`. Script này dùng CryptoKit
     (`Curve25519.Signing.PublicKey`), tức Ed25519 chuẩn như Sparkle. Không khớp thì exit 1, báo
     `the Sparkle key does not match SUPublicEDKey`.
     Lý do không dùng `sign_update --verify` (đã đọc mã nguồn bản 2.10.1): lệnh đó kiểm tra theo khoá công khai
     suy ra từ chính khoá bí mật được đưa vào, nên không phát hiện được secret lệch với khoá trong app.
  5. Ghi `build/appcast.xml`: RSS 2.0 với namespace `sparkle`, có một `<item>` duy nhất:
     - `title`: `Agenty <short>`
     - `pubDate`: theo RFC 822, lúc chạy
     - `sparkle:version`: `CFBundleVersion`; `sparkle:shortVersionString`: `CFBundleShortVersionString`
     - `sparkle:minimumSystemVersion`: `LSMinimumSystemVersion`
     - `description sparkle:format="markdown"`: nội dung `notes.md` trong CDATA, trong đó `]]>` được tách
       thành `]]]]><![CDATA[>`
     - `enclosure`: `url="https://github.com/vuxng/agenty/releases/download/v<version>/Agenty-<version>-arm64.zip"`,
       `length`, `type="application/octet-stream"`, `sparkle:edSignature`
  6. `xmllint --noout build/appcast.xml` phải pass.
- `<version>` khác `CFBundleShortVersionString` trong zip thì exit 1.

### 5.3 `scripts/publish-release.sh` (sửa)

Upload thêm `build/appcast.xml`. Dùng `--notes-file build/notes.md` thay cho `--generate-notes`.
Phần dọn draft khi lỗi giữ nguyên.

### 5.4 `release.yml` (sửa)

Thêm các bước sau vào giữa Verify Gatekeeper và Publish release:

1. **Generate release notes:** `gh api repos/vuxng/agenty/releases/generate-notes -f tag_name="v$VERSION" -f target_commitish="$GITHUB_SHA" --jq .body > build/notes.md`.
2. **Make appcast:** chỉ bước này nhận `SPARKLE_ED_PRIVATE_KEY`, và đưa nó vào
   `scripts/make-appcast.sh "$VERSION"` qua stdin. Thiếu secret thì script dừng (mục 5.2, bước 1).

Release là draft cho tới khi upload xong rồi mới được publish một lần, nên `releases/latest/download/appcast.xml`
chỉ chuyển sang bản mới khi zip đã có.

## 6. Khoá EdDSA (làm một lần trên máy người dùng)

1. Sau lần build đầu có Sparkle, chạy `generate_keys` trong thư mục `bin` của Sparkle. Khoá bí mật được lưu
   vào login Keychain; macOS có thể hỏi quyền. Lệnh in ra khoá công khai.
2. Khoá công khai đưa vào `SUPublicEDKey` trong `project.yml`.
3. `generate_keys -x <file tạm>` xuất khoá bí mật. Chuyển nó vào `gh secret set SPARKLE_ED_PRIVATE_KEY --env release --repo vuxng/agenty`
   qua stdin, rồi xoá file tạm. Không in khoá ra màn hình hay log.
4. Người dùng tự cất một bản sao vào trình quản lý mật khẩu.

**Mất khoá bí mật** thì không ký được bản cập nhật cho các bản đã cài. Phải tạo khoá mới và phát hành một bản
có `SUPublicEDKey` mới, rồi người dùng tự tải bản đó một lần. README ghi rõ điều này.

## 7. Test và kiểm chứng

### 7.1 Test script (chạy trong CI)

- `test-build-release.sh` (mở rộng):
  - Stub `xcodebuild` dựng thêm `Sparkle.framework` giả; stub `codesign` ghi log từng lần gọi.
  - Assert ký đúng thứ tự 1→6 ở mục 5.1, không lần nào có `--deep`, có `--timestamp`, và có `--keychain` khi được đặt.
  - Assert dừng trước khi notarize khi một helper thiếu `Developer ID Application` hoặc `Timestamp=`.
  - Assert bản ad-hoc không ký lại từng helper.
- `test-make-appcast.sh` (mới), dùng `sign_update` giả qua `SPARKLE_BIN`, trên macOS (cần `plutil`, `xmllint`, `swift`).
  `sign_update` giả ký thật bằng Ed25519 với một cặp khoá chỉ dùng cho test, sinh lúc chạy, để bước 4 kiểm tra
  chữ ký thật chứ không phải chữ ký giả. Các trường hợp:
  - Item có version, build, URL, length và chữ ký đúng.
  - Notes chứa `]]>` vẫn cho XML hợp lệ.
  - Thiếu khoá: fail.
  - Khoá không khớp `SUPublicEDKey`: fail.
  - Version khác version trong zip: fail.
  - Khoá không bao giờ xuất hiện trong đối số của `sign_update`.
- `test-publish-release.sh` (sửa): kiểm tra có asset `appcast.xml` và có `--notes-file`.

### 7.2 Kiểm chứng trên máy thật

- Ở local: build Developer ID kèm notarize, rồi `spctl` báo `source=Notarized Developer ID`. Đây là bằng chứng
  các helper của Sparkle đã được ký đúng.
- Sau khi workflow 0.2.0 xanh:
  - Tải `releases/latest/download/appcast.xml`, kiểm tra item 0.2.0 và chữ ký so với khoá công khai.
  - Tải zip về, kiểm tra như ở bản 0.1.1.
- **Thử cập nhật thật, không cần đợi 0.2.1:**
  1. Build một bản Release với `MARKETING_VERSION` 0.1.9 và `BUILD_NUMBER=1`, ký Developer ID cùng team, không notarize.
  2. Tắt Agenty đang chạy, mở bản giả này, bấm Check for Updates….
  3. Sparkle phải đề nghị 0.2.0; Install phải tải, thay và mở lại thành 0.2.0, Keychain không hỏi lại.
- Thử lời nhắc nhẹ ở popover, vẫn dùng bản giả 0.1.9:
  1. Đặt `defaults write io.github.vuxng.Agenty SULastCheckTime -date` thành thời điểm "bây giờ trừ 1 ngày cộng 5 phút",
     để lần kiểm tra định kỳ rơi vào khoảng 5 phút sau khi mở app, không còn là lúc vừa mở.
  2. Mở app và chờ. Không có cửa sổ nào bật lên; mở popover phải thấy `Agenty 0.2.0 is available`; bấm Install… thì
     hộp thoại Sparkle hiện ra.

## 8. Thứ tự thực hiện

1. Thêm Sparkle vào `project.yml`. Build một lần để có công cụ của Sparkle, rồi tạo khoá (mục 6, có hộp thoại
   Keychain cho người dùng bấm).
2. App: `Updater`, Settings, popover, bản dịch `vi`.
3. `build-release.sh` (ký Sparkle) cùng test. Build Developer ID kèm notarize ở local để chứng minh.
4. `make-appcast.sh`, `publish-release.sh`, `release.yml` cùng test.
5. README. Tăng `MARKETING_VERSION` lên `0.2.0`.
6. PR vào `next` (squash), CI xanh.
7. Release: PR `next → stable`, merge, theo dõi workflow, rồi kiểm chứng như mục 7.2.

## 9. Rủi ro và lưu ý

- **Mất khoá EdDSA hoặc secret sai:** đã có bước kiểm tra khớp khoá (mục 5.2, bước 4) và bản sao trong trình quản lý mật khẩu.
- **Người dùng 0.1.x phải tự cài 0.2.0 một lần:** ghi trong README và trong release notes của 0.2.0.
- **`releases/latest` chuyển hướng sang `objects.githubusercontent.com`:** Sparkle tự đi theo chuyển hướng HTTPS.
  Bước kiểm chứng ở mục 7.2 kiểm tra điều này trên đúng URL đó.
- **`CFBundleVersion` phải luôn tăng:** đang lấy theo số commit của `stable`, và nhánh này chỉ tiến lên
  (merge commit, cấm force push).
- **XPC services:** app không sandbox nên không thật sự cần chúng. Vẫn giữ và ký lại theo hướng dẫn chính thức
  thay vì tự xoá khỏi framework.
- **Sparkle trên macOS 27:** tài liệu Sparkle chưa nói gì riêng về macOS 27. Bước 7.2 là nơi phát hiện vấn đề.
