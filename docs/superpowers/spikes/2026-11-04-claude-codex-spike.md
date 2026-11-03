# Spike §9.2 — Claude + Codex: xác nhận format thật

- **Ngày:** 2026-11-04
- **Máy:** MacBook Pro Apple Silicon, macOS 27.0, Claude Code 2.1.317, Codex CLI 0.162.1
- **Kết quả:** ✅ cả hai nguồn dùng được. Spec §5 đã được cập nhật theo các phát hiện dưới đây.
- Script thử nằm trong scratchpad và đã bỏ (không commit).

## Claude — `GET https://api.anthropic.com/api/oauth/usage`

**Request:** `Authorization: Bearer <accessToken>`, `anthropic-beta: oauth-2025-04-20`,
User-Agent bất kỳ. → **HTTP 200 trong 0,46 giây.** Không có header rate-limit hay `Retry-After`
trong response thành công.

### Phát hiện 1: file credential bị cũ, Keychain mới là nguồn đúng
| Nguồn | `expiresAt` | Ghi chú |
|---|---|---|
| `~/.claude/.credentials.json` | hết hạn ~28 ngày trước | token khác với Keychain |
| Keychain `Claude Code-credentials` | còn ~5 giờ | Claude Code đang refresh bản này |

Chiến lược trong spec ("đọc cả hai, lấy bản có `expiresAt` muộn hơn") vẫn đúng, nhưng thực tế
**Keychain là nguồn chính**, file chỉ là fallback. Đọc bằng `security find-generic-password -w`
không bật hộp thoại hỏi quyền. App LLMUsage là một binary khác, nên có thể vẫn bị hỏi một lần.

Metadata có ích trong credential: `subscriptionType = "max"`, `rateLimitTier = "default_claude_max_20x"`.

### Phát hiện 2: dùng mảng `limits[]`, không dùng các field cũ
Response có một mảng `limits` có cấu trúc. Schema trong Claude Code ghi:
*"The server's meter kind, e.g. 'session', 'weekly_all' or 'weekly_scoped'. Classify a row on this, never on a label."*

```json
{ "kind": "weekly_all", "group": "weekly", "percent": 13, "severity": "normal",
  "resets_at": "2026-11-04T20:00:00.652364+00:00", "scope": null, "is_active": true }
{ "kind": "weekly_scoped", "group": "weekly", "percent": 0, "severity": "normal",
  "resets_at": "2026-11-04T20:00:00+00:00",
  "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null }, "is_active": false }
```

- `kind`: `session` (5 giờ), `weekly_all`, `weekly_scoped` (theo model, tên lấy từ `scope.model.display_name`).
- **Lúc chạy spike không có row `session`**, và `five_hour` cũng `null`. App **không được giả định**
  luôn có cửa sổ 5 giờ.
- `is_active: false` thì meter chưa áp dụng. v1 ẩn các row này.
- Field cũ `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet` vẫn có (`{utilization, resets_at}`),
  dùng làm **fallback** khi không có `limits`.
- Response có rất nhiều key mang tên mã nội bộ (`iguana_necktie`, `tangelo`, `amber_*`…). **Bỏ qua.**
  Parser phải lỏng: không fail khi gặp key lạ.
- Để dành cho v2: `extra_usage`/`spend` (usage credits), `seven_day_breakdown` (tỷ lệ Claude Code / Chat / Cowork),
  `weekly_scoped_shares`.

Fixture: `fixtures/claude-oauth-usage.json` (không chứa id hay email).

## Codex — `codex app-server` → `account/rateLimits/read`

**Handshake chạy được:**
```
→ {"id":1,"method":"initialize","params":{"clientInfo":{"name":"…","title":"…","version":"…"}}}
← {"id":1,"result":{"userAgent":"…","codexHome":"/Users/vu/.codex","platformFamily":"unix","platformOs":"macos"}}
→ {"method":"initialized"}
→ {"id":2,"method":"account/rateLimits/read","params":{"excludeResetCreditDetails":true}}
← (notification) remoteControl/status/changed
← (notification) account/updated  {"authMode":"chatgpt","planType":"pro"}
← {"id":2,"result":{…}}
```
- **Tổng thời gian 1,27 giây** tính từ lúc spawn, process thoát sạch (exit 0) khi đóng stdin.
- **Không cần trường `"jsonrpc"`**. Mỗi message là một dòng JSON.
- **Server gửi notification xen giữa, trước response.** Client phải lọc theo `id` và bỏ qua mọi message có `method`.
- `excludeResetCreditDetails: true` là cờ dành cho "background usage polls" theo mô tả trong schema. App nên luôn bật cờ này.

**Kết quả** (tài khoản Pro): `rateLimits.primary = {usedPercent: 23, windowDurationMins: 10080, resetsAt: <unix s>}`,
`secondary = null`, `credits = {hasCredits: true, unlimited: false, balance: "61862.9684000000"}` (chuỗi thập phân),
`planType = "pro"`, `ordinaryUsageAllowed = true`, `rateLimitsByLimitId` chỉ có `codex`.
- Để dành cho v2: `rateLimitResetCredits.availableCount = 3` (số lần reset hạn mức còn lại), có method
  `account/rateLimitResetCredit/consume`.

Fixture: `fixtures/codex-rate-limits.json` (`accountId` đã được thay bằng `<redacted>`).
