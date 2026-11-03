# LLMUsage — macOS menu bar app theo dõi hạn mức Claude / Codex / Grok

- **Ngày:** 2026-11-04
- **Trạng thái:** Draft — chờ duyệt
- **Tên tạm:** LLMUsage (có thể đổi trước khi public)

## 1. Mục tiêu

Một app menu bar macOS nhỏ, open-source, cho biết **ngay lập tức** mình còn dùng được bao nhiêu
hạn mức gói (subscription) của các coding agent: phần trăm đã dùng của từng cửa sổ (5 giờ,
tuần, theo model) và khi nào reset.

**Người dùng:** developer dùng Claude Code, Codex CLI, Grok CLI bằng tài khoản subscription
(Claude Pro/Max, ChatGPT Plus/Pro, SuperGrok) và đã đăng nhập các CLI trên máy.

**Thành công khi:**
- Nhìn menu bar trong 1 giây biết có provider nào sắp chạm giới hạn không.
- Mở popover thấy đủ mọi cửa sổ, % và thời điểm reset của từng provider.
- Được báo trước khi bị chặn (80% / 95%) và báo khi được reset.
- Không cần nhập token hay đăng nhập lại — dùng chính credential của các CLI.

## 2. Phạm vi

### Trong v1
- Provider: **Claude**, **Codex**.
- Menu bar với 3 kiểu hiển thị (chọn trong Settings).
- Popover chi tiết.
- Thông báo vượt ngưỡng + thông báo reset.
- Launch at login.
- Settings cơ bản.

### Ngoài v1 (để v2+)
- **Grok** — chờ spike (§9.1). Kiến trúc chừa sẵn chỗ (`UsageProvider`).
- Lịch sử / biểu đồ xu hướng.
- Widget.
- Nhiều tài khoản cho cùng một provider.
- Thống kê token / quy đổi chi phí.
- Developer ID signing, notarization, Sparkle auto-update.

## 3. Ràng buộc nền tảng

| Hạng mục | Giá trị |
|---|---|
| Deployment target | **macOS 27.0** |
| Kiến trúc | **arm64 only** (Apple Silicon), `ARCHS = arm64` |
| Toolchain | Xcode 27, Swift 6 language mode, strict concurrency |
| Sandbox | **Không** (cần đọc `~/.claude`, Keychain item của Claude Code, chạy `codex`) |
| Phân phối | GitHub (repo private lúc đầu, open-source sau) |
| Dependency ngoài | Chỉ `swiftlang/swift-subprocess` (1.x) |

API Apple dùng: SwiftUI `MenuBarExtra` (`.window` style), `Settings` scene + `SettingsLink`,
`@Observable` + macro `@State` mới của Xcode 27, Liquid Glass, `SMAppService.mainApp`,
`UNUserNotificationCenter`, `Security` (Keychain), `os.Logger`, String Catalog.

## 4. Kiến trúc

```
llm-usage/
├── LLMUsage.xcodeproj          (buildable folders)
├── App/                        target app, LSUIElement = YES
│   ├── LLMUsageApp.swift       MenuBarExtra + Settings scene
│   ├── Views/                  MenuBarLabel, UsagePopover, ProviderCard, SettingsView
│   └── System/                 Notifier, LoginItem
└── Packages/UsageCore/         Swift Package local, KHÔNG import SwiftUI
    ├── Sources/UsageCore/
    │   ├── Models/             ProviderID, UsageWindow, UsageSnapshot, UsageError, Credits
    │   ├── Providers/          ClaudeProvider, CodexProvider
    │   ├── Infrastructure/     HTTPClient, ProcessRunner, CLILocator, KeychainReader
    │   ├── Alerts/             UsageEvent, evaluate(old:new:thresholds:)
    │   └── UsageStore.swift
    └── Tests/UsageCoreTests/   Swift Testing + Fixtures/
```

### 4.1 Hợp đồng trung tâm

```swift
public enum ProviderID: String, Sendable, CaseIterable { case claude, codex, grok }

public enum WindowKind: Sendable, Hashable {
    case session5h
    case weekly
    case weeklyModel(String)        // ví dụ "opus"
    case other(minutes: Int)        // cửa sổ không nhận diện được
}

public struct UsageWindow: Sendable, Hashable {
    public var kind: WindowKind
    public var usedPercent: Double      // 0...100
    public var resetsAt: Date?
}

public struct Credits: Sendable, Hashable {
    public var balance: Decimal?
    public var unlimited: Bool
}

public struct UsageSnapshot: Sendable, Hashable {
    public var provider: ProviderID
    public var plan: String?            // "max", "pro", ...
    public var windows: [UsageWindow]
    public var credits: Credits?
    public var fetchedAt: Date
}

public enum UsageError: Error, Sendable, Equatable {
    case notLoggedIn
    case tokenExpired
    case cliNotFound
    case network(retryAfter: Duration?)
    case unexpectedFormat(String)       // mô tả ngắn, KHÔNG chứa body/token
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    func fetch() async throws(UsageError) -> UsageSnapshot
}
```

### 4.2 `UsageStore`

- `@Observable @MainActor final class UsageStore`.
- State mỗi provider:
  `enum ProviderState { case idle, loading(last: UsageSnapshot?), loaded(UsageSnapshot), failed(UsageError, last: UsageSnapshot?) }`.
- `refreshAll()` chạy các provider đang bật song song bằng `TaskGroup`. Nếu một lượt đang
  chạy thì không chạy chồng.
- Sau mỗi lượt, chuyển cặp (snapshot cũ, snapshot mới) cho `evaluate` để sinh
  `UsageEvent`, rồi giao cho `Notifier`.
- Giá trị dẫn xuất cho UI: `mostConstrainedWindow` (toàn cục và theo từng provider),
  `isStale`. **Cửa sổ căng nhất** là cửa sổ có `usedPercent` cao nhất. Nếu bằng nhau thì
  chọn cửa sổ có `resetsAt` xa hơn.

### 4.3 Luồng dữ liệu

```
Trigger (timer / mở popover / ⟳ / wake)
   → UsageStore.refreshAll()
       → TaskGroup { provider.fetch() }   (mỗi provider độc lập)
       → cập nhật ProviderState
       → evaluate(old, new, thresholds) → [UsageEvent] → Notifier
   → SwiftUI re-render (Observation)
```

## 5. Nguồn dữ liệu

> Cả hai nguồn đều **không phải API công khai có tài liệu**. README phải nói rõ điều này.

### 5.1 Claude — `ClaudeProvider`

**Credential (chỉ đọc, không bao giờ ghi):**
1. Keychain generic password, service `Claude Code-credentials`.
2. File `~/.claude/.credentials.json`.

Cả hai có dạng `{"claudeAiOauth": {accessToken, refreshToken, expiresAt, refreshTokenExpiresAt, scopes, subscriptionType, rateLimitTier}}`.
App đọc cả hai và dùng bản có `expiresAt` muộn hơn. Lần đầu đọc Keychain, macOS sẽ hỏi
quyền; người dùng chọn "Always Allow".

**Request:**
```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <accessToken>
anthropic-beta: oauth-2025-04-20
```

**Ánh xạ** (chốt chính xác sau spike §9.2):
dùng **allowlist** — `five_hour` → `.session5h`, `seven_day` → `.weekly`,
`seven_day_opus` → `.weeklyModel("opus")`, `seven_day_sonnet` (nếu có) → `.weeklyModel("sonnet")`.
Các key `seven_day_*` khác (ví dụ `seven_day_oauth_apps`, `seven_day_overage_included`,
`seven_day_cowork`) **không** phải model nên bị bỏ qua trong v1. Spike §9.2 sẽ xác định
nghĩa của chúng. Field `null` thì bỏ qua. `subscriptionType` → `plan`.

**Token hết hạn:** **app không tự refresh token.** Lý do: refresh token có thể bị xoay vòng
(rotation), app refresh có thể làm Claude Code bị đăng xuất.
- `expiresAt` đã qua hoặc HTTP 401 → `.tokenExpired`.
- Claude Code tự refresh khi chạy, nên lượt poll sau sẽ tự khỏi.

### 5.2 Codex — `CodexProvider`

**Cách lấy:** chạy `codex app-server` qua `swift-subprocess`, giao tiếp JSON-RPC (mỗi dòng
một JSON) trên stdio:
1. `initialize` (clientInfo: `LLMUsage`, version) → chờ response.
2. Gửi notification `initialized`.
3. `account/rateLimits/read` → `GetAccountRateLimitsResponse`.
4. Đóng stdin rồi terminate process. Timeout toàn bộ: **15 giây**.

Token do Codex tự quản lý và tự refresh. App không đọc `~/.codex/auth.json`.

**Response** (từ JSON schema `codex app-server generate-json-schema`):
- `rateLimits: RateLimitSnapshot { primary?, secondary?: RateLimitWindow, credits?, planType?, limitId?, ... }`
- `RateLimitWindow { usedPercent: Int, windowDurationMins: Int?, resetsAt: Int? (unix s) }`
- `rateLimitsByLimitId: { [id]: RateLimitSnapshot }?`

**Ánh xạ cửa sổ theo `windowDurationMins`, KHÔNG theo vị trí primary/secondary.**
300 → `.session5h`, 10080 → `.weekly`, giá trị khác → `.other(minutes:)`.
Ví dụ thật: tài khoản Pro hiện chỉ có cửa sổ tuần nằm ở `primary`, còn `secondary = null`.

v1 chỉ dùng `rateLimits`. `rateLimitsByLimitId` hiển thị thêm chỉ khi spike cho thấy có giá
trị khác ngoài `codex`.

### 5.3 Tìm file thực thi CLI — `CLILocator`

App GUI không thừa hưởng PATH của shell. Thứ tự tìm:
1. Đường dẫn người dùng tự chỉ định trong Settings.
2. Các thư mục quen thuộc: `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`.
3. `/bin/zsh -lc 'command -v <name>'`, chạy một lần mỗi phiên app rồi cache.

Không tìm thấy → `.cliNotFound`.

### 5.4 Grok

Không có trong v1. Xem spike §9.1.

## 6. UI

### 6.1 Menu bar
- `MenuBarExtra` với style `.window`.
- 3 kiểu label (Settings → Menu bar):
  - **C. Thanh mini (mặc định):** mỗi provider đang bật là một thanh dọc, độ cao bằng % của
    cửa sổ căng nhất của provider đó.
  - **A. Một con số:** vòng tròn kèm % của cửa sổ căng nhất trên toàn bộ provider.
  - **B. Mỗi provider một số:** biểu tượng provider kèm % cửa sổ căng nhất của nó.
- Màu: bình thường < ngưỡng 1 (80%) ≤ cam < ngưỡng 2 (95%) ≤ đỏ. Ngưỡng màu dùng chung với
  ngưỡng thông báo.
- Provider đang lỗi: phần của nó hiện mờ, dùng `last` snapshot nếu có. Icon thêm chấm cảnh báo.

### 6.2 Popover (bố cục A: thẻ + thanh ngang)
- Mỗi provider đang bật là một thẻ: logo, tên, badge gói. Mỗi cửa sổ một dòng
  `Tên · NN%` và thời gian reset, kèm thanh tiến độ có màu theo ngưỡng.
  - Reset trong vòng 24 giờ: dạng tương đối ("reset sau 2g 13p").
  - Xa hơn: dạng tuyệt đối ("reset T5 09:00").
- Codex có thêm dòng Credits nếu `credits` khác `nil` và không `unlimited`.
- Lỗi hiện ngay trong thẻ: một dòng mô tả kèm nút hành động (bảng §7.3).
- Footer: "Cập nhật HH:mm" (spinner khi đang refresh; màu cam nếu stale), ⟳, ⚙︎ (`SettingsLink`), ⏻ Quit.
- Mockup: `.superpowers/brainstorm/` (không commit).

### 6.3 Settings (một `Form`)
1. **Chung:** Launch at login (`SMAppService.mainApp`); chu kỳ refresh 1 / 2 / **5** / 10 / 15 phút.
2. **Menu bar:** kiểu hiển thị C / A / B.
3. **Providers:** bật/tắt Claude, Codex. Codex có ô đường dẫn CLI kèm trạng thái
   ("✓ Tìm thấy tại …" / "✗ Không tìm thấy").
4. **Thông báo:** bật/tắt; ngưỡng 1 (mặc định 80) và ngưỡng 2 (mặc định 95); bật/tắt báo reset.

Lưu bằng `@AppStorage` / `UserDefaults`.

### 6.4 Ngôn ngữ
Tiếng Anh làm gốc, thêm tiếng Việt qua String Catalog (`Localizable.xcstrings`).

## 7. Hành vi runtime

### 7.1 Refresh
- Trigger: timer (theo chu kỳ trong Settings); mở popover khi dữ liệu cũ hơn 60 giây; nút ⟳;
  `NSWorkspace.didWakeNotification`.
- Không chạy chồng: nếu một lượt đang chạy thì trigger mới bị bỏ qua.
- Backoff theo từng provider khi gặp `.network`: 1 → 2 → 4 … phút, tối đa bằng chu kỳ refresh.
  HTTP 429 thì dùng `Retry-After` nếu có.
- Stale: `now - fetchedAt > 3 × chu kỳ`.

### 7.2 Thông báo — `evaluate(old:new:thresholds:) -> [UsageEvent]` (hàm thuần)
- `UsageEvent`: `.crossed(provider, window, threshold)` và `.reset(provider, window)`.
- **Vượt ngưỡng:** mỗi cặp (provider, `WindowKind`) chỉ báo một lần cho mỗi ngưỡng, khi %
  đi từ dưới lên bằng hoặc trên ngưỡng. Mức cao nhất đã báo được lưu trong `UserDefaults`
  để khởi động lại app không bị báo trùng.
- **Reset:** một cửa sổ được coi là đã reset khi `resetsAt` cũ ≤ now và % mới < % cũ,
  **hoặc** % giảm ≥ 30 điểm. Khi đó app báo reset (nếu bật) và xoá mức đã báo của cửa sổ.
- Thông báo **mặc định bật**. App xin quyền `UNUserNotificationCenter` ở lần chạy đầu tiên.
  Nếu người dùng từ chối, toggle trong Settings hiện "Notifications disabled in System
  Settings" kèm nút mở System Settings.

### 7.3 Lỗi

| `UsageError` | Nguyên nhân | UI |
|---|---|---|
| `notLoggedIn` | không có credential / Codex báo chưa login | "Not signed in — run `claude` / `codex login`" |
| `tokenExpired` | `expiresAt` đã qua / HTTP 401 | "Session expired — open Claude Code once" |
| `cliNotFound` | `CLILocator` không tìm thấy | nút "Choose path…" (mở `NSOpenPanel`) |
| `network` | offline, timeout, 5xx, 429 | giữ `last`, footer stale màu cam |
| `unexpectedFormat` | schema thay đổi | "API format changed" kèm link mở GitHub issue |

### 7.4 Quyền riêng tư & logging
- Token chỉ nằm trong bộ nhớ trong lúc gọi request. Không cache, không ghi ra đĩa, không log.
- Request mạng duy nhất từ app đi tới `api.anthropic.com`. Dữ liệu Codex đi qua chính CLI
  của Codex.
- `os.Logger` (subsystem = bundle id): chỉ ghi tên provider, status code, thời lượng, và tên
  key khi parse lỗi. Không ghi body, không ghi token.

## 8. Testing

- **Swift Testing** (`import Testing`) trong `UsageCoreTests`, chạy bằng `swift test` ở
  `Packages/UsageCore`.
- Provider nhận dependency qua protocol để test có thể thay bằng bản giả:
  - `HTTPClient` (`func data(for: URLRequest) async throws -> (Data, HTTPURLResponse)`)
  - `ProcessRunner` (spawn, ghi stdin, đọc stdout từng dòng)
  - `CredentialSource` (Keychain / file)
  - `Clock` để test refresh, backoff và stale.
- Các test bắt buộc:
  - Parse fixture Claude và Codex (lấy từ spike §9.2, đã xoá dữ liệu cá nhân) ra
    `UsageSnapshot` đúng.
  - Ánh xạ `windowDurationMins` → `WindowKind`, gồm cả `primary = weekly, secondary = nil`.
  - Bảng lỗi: 401 → `tokenExpired`, `expiresAt` đã qua → `tokenExpired` (không gọi mạng),
    429 có `Retry-After`, JSON hỏng → `unexpectedFormat`.
  - `evaluate`: vượt 80 rồi 95, không báo lặp, reset theo `resetsAt`, reset theo % giảm,
    trường hợp không có `resetsAt`.
  - `CLILocator`: thứ tự ưu tiên, dùng filesystem giả.
  - JSON-RPC client của Codex chạy với `ProcessRunner` giả: thứ tự handshake, timeout,
    process thoát sớm.
  - `UsageStore`: lỗi của một provider không ảnh hưởng provider khác; không chạy chồng.
- **UI:** SwiftUI `#Preview` cho các trạng thái loaded / loading / error / stale, với cả 3
  kiểu label. v1 không có UI test tự động.

## 9. Spike (làm trước khi lập plan)

### 9.1 Grok — nguồn dữ liệu "Usage limit"
- **Câu hỏi:** có cách đọc hạn mức SuperGrok (giống tab Usage limit trong `/usage` của
  `grok` 1.0.x) một cách ổn định từ ngoài TUI không?
- **Thử theo thứ tự rẻ nhất:**
  1. Tìm trong `grok --help` và các subcommand một lệnh hoặc flag xuất JSON.
  2. Tìm trong agent mode (ACP JSON-RPC) một method hoặc `_meta` có thông tin usage.
  3. Quan sát request HTTPS mà `grok` gọi khi mở `/usage` (proxy cục bộ hoặc log debug của CLI).
- **Kết quả:** "được" kèm endpoint/method và format response, hoặc "không được" kèm lý do.
  Code thử thì bỏ.
- **Timebox:** 1–2 giờ.

### 9.2 Claude + Codex — xác nhận format thật
- Gọi `/api/oauth/usage` và `account/rateLimits/read` bằng script ngắn trên máy thật.
- Ghi lại response, xoá dữ liệu cá nhân (id, email, account id), lưu thành fixture JSON
  cho §8.
- Xác nhận: Keychain và file credential của Claude, bên nào mới hơn; Codex có yêu cầu
  params nào cho `initialize`.
- Cập nhật §5 nếu thực tế khác spec.

## 10. Repo & phát hành

- Repo GitHub **private** `vuxng/llm-usage` (chuyển public khi sẵn sàng open-source).
- `.gitignore`: `.superpowers/`, `xcuserdata/`, `build/`, `DerivedData/`, `.DS_Store`, `.build/`.
- License MIT. README (tiếng Anh) gồm: tính năng, ảnh chụp, yêu cầu (macOS 27, Apple
  Silicon, đã đăng nhập CLI), **cảnh báo endpoint không chính thức**, quyền riêng tư,
  build từ source.
- Bundle id: `io.github.vuxng.LLMUsage`.
- CI (GitHub Actions): `swift test` cho `UsageCore`; `xcodebuild build` khi runner có Xcode 27.
- Release v1: zip `.app` ký ad-hoc trên GitHub Releases. Developer ID và notarization để v2.

## 11. Rủi ro

| Rủi ro | Ảnh hưởng | Giảm thiểu |
|---|---|---|
| Endpoint Claude thay đổi hoặc bị chặn | Mất dữ liệu Claude | `unexpectedFormat` rõ ràng; parse lỏng (bỏ qua field lạ); fixture test |
| `codex app-server` (experimental) đổi protocol | Mất dữ liệu Codex | Pin theo schema đã sinh; fallback v2: đọc `rate_limits` trong session log |
| Keychain prompt gây phiền | UX lần đầu | Có fallback file; giải thích trong onboarding/README |
| Không có cách lấy dữ liệu Grok | Thiếu 1/3 provider | Spike §9.1; v1 không phụ thuộc Grok |
| Runner CI chưa có macOS 27 | CI chỉ chạy được một phần | `swift test` vẫn chạy nếu toolchain hỗ trợ; build app ở local |
