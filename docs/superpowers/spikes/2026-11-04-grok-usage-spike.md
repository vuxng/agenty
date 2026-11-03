# Spike §9.1 — Nguồn dữ liệu "Usage limit" của Grok

- **Ngày:** 2026-11-04
- **Phiên bản kiểm tra:** `grok` 1.0.46, sau đó tự cập nhật lên 1.0.70 trong lúc spike
- **Kết luận: ĐƯỢC, nhưng chưa xác nhận bằng response thật.** Đã tìm ra cơ chế và tên field
  (nguồn: binary và JSON-RPC thật). Chưa lấy được response vì credential Grok trên máy đã
  hết hạn từ trước (xem §5).

## 1. Cơ chế

TUI `/usage` lấy tab "Usage limit" qua một **ACP extension method** của chính agent:

| | |
|---|---|
| Process | `grok agent --no-leader stdio` (ACP JSON-RPC, mỗi dòng một JSON, qua stdio) |
| Handshake | `initialize` `{"protocolVersion": 1, "clientCapabilities": {}}`. Không cần `session/new`, không gửi prompt nào |
| Method | **`_x.ai/billing`** (có dấu `_` ở đầu; gọi `x.ai/billing` sẽ ra `-32601 Method not found`) |
| Params | `{}` |
| Upstream | Agent gọi `GET {cli_chat_proxy_base_url}/billing?format=credits`, với base mặc định là `https://cli-chat-proxy.grok.com/v1` (implement trong `xai-grok-shell/src/extensions/billing.rs`) |
| Auth | Do agent tự quản lý (`AuthManager`, file `~/.grok/auth.json`, mode OIDC). App **không cần** đọc token |
| Method liên quan | `_x.ai/auto-topup-rule` (quy tắc tự nạp credit). `/user?include=subscription` cung cấp `subscription_tier` (dùng cho paywall check, không lộ qua ACP) |

Đã kiểm chứng trực tiếp: `initialize` trả về trong khoảng 0,3–0,9 giây. `_x.ai/billing` có
tồn tại; khi chưa có credential hợp lệ, nó trả về
`{"code": -32000, "message": "Authentication required", "data": "Authentication required to fetch billing data"}`.

## 2. Dạng response (suy ra từ binary, CHƯA xác nhận)

Các field của `BillingConfigResponse` / `BillingPeriodUsage` / `BillingCycle` thấy được
trong cả bản 1.0.46 lẫn 1.0.70:

```
creditUsagePercent      ← % đã dùng: con số chính để hiển thị
currentPeriod           ← BillingPeriodUsage (struct 4 field)
monthlyLimit
includedUsed, totalUsed
onDemandEnabled, onDemandCap, onDemandUsed
prepaidBalance
isUnifiedBillingUser
billingPeriodStart, billingPeriodEnd   ← thời điểm reset = billingPeriodEnd
billingCycle            ← BillingCycle (có "month" / "end")
history                 ← [BillingPeriodUsage]
```

Hệ quả cho thiết kế: hạn mức của SuperGrok tính theo **credit trong một kỳ thanh toán
(tháng)**, không chia cửa sổ 5 giờ hay tuần như Claude và Codex. Cần thêm một
`WindowKind` mới (ví dụ `.billingPeriod`) với `usedPercent = creditUsagePercent` và
`resetsAt = billingPeriodEnd`. Có thể thêm `Credits` từ `prepaidBalance` hoặc on-demand.

Kiểu dữ liệu (số hay chuỗi, timestamp hay ISO-8601) và việc lồng nhau chính xác ra sao
**chưa biết**. Phải lấy response thật trước khi viết parser.

## 3. Độ ổn định

- **Tốt hơn dự kiến:** method nằm trong ACP mà Grok dùng cho chính TUI và IDE của họ. Tên
  method và toàn bộ field không đổi giữa 1.0.46 và 1.0.70 (24 bản phát hành). Docs có ghi
  rõ "`x.ai/*` có thể mở rộng qua các bản", nhưng không cam kết giữ ổn định.
- **Rủi ro:**
  1. Đây là method nội bộ, không có tài liệu (docs chỉ liệt kê nhóm `x.ai/fs`, `git`,
     `auth`…). Có thể bị đổi tên hoặc gỡ.
  2. Khi spawn, `grok` có thể **tự cập nhật binary** (đã xảy ra trong spike: 1.0.46 → 1.0.70)
     và in thông báo update ra stderr.
  3. **Khi token đã hết hạn và refresh bị từ chối, `grok` tự xoá `~/.grok/auth.json`**
     (`auth: cleared credentials after permanent refresh failure`, `RefreshTokenRejected`).
     Đây là hành vi của chính `grok` và xảy ra ở mọi lần chạy, không riêng app. Nhưng app
     poll định kỳ sẽ là thứ "chạm" vào trước người dùng, nên cần báo `notLoggedIn` rõ ràng.

## 4. Đề xuất cho `GrokProvider`

Làm giống `CodexProvider` (spawn CLI, JSON-RPC qua stdio, CLI tự lo auth):

1. Tìm `grok` bằng `CLILocator`. Thêm `~/.grok/bin` vào danh sách thư mục quen thuộc.
2. Spawn `grok agent --no-leader stdio`. Dùng `--no-leader` để không dính vào leader dùng
   chung của người dùng. Gửi `initialize`, rồi `_x.ai/billing` `{}`, rồi đóng stdin. Timeout 15 giây.
3. Ánh xạ: `-32000 "Authentication required"` → `.notLoggedIn` ("Run `grok login`");
   `-32601` → `.unexpectedFormat("billing method missing")`; response →
   `UsageWindow(kind: .billingPeriod, usedPercent: creditUsagePercent, resetsAt: billingPeriodEnd)`.
4. Chu kỳ poll của Grok nên ≥ 5 phút, vì dữ liệu là credit theo tháng và không thay đổi nhanh.
5. **Không** gọi trực tiếp `cli-chat-proxy.grok.com/v1/billing` bằng token đọc từ
   `auth.json`. Token hết hạn sau khoảng 7 ngày, và tự refresh bên ngoài `grok` có rủi ro
   xoay vòng refresh token, giống trường hợp của Claude. Đây chỉ là phương án dự phòng nếu
   ACP bị gỡ. Header cần dùng (theo README của Grok): `Authorization: Bearer <key>`,
   `X-XAI-Token-Auth: xai-grok-cli`.

**Bước tiếp theo (bắt buộc trước khi implement):** người dùng chạy `grok login`, sau đó
chạy lại `scratchpad/grok-spike/acp_billing.py _x.ai/billing` để lấy response thật, xoá dữ
liệu cá nhân, rồi lưu vào `docs/superpowers/spikes/fixtures/grok-usage.json`.

## 5. Sự cố trong spike: credential Grok bị xoá

- Lần cuối dùng Grok trên máy: 2026-10-06. Access token đã hết hạn (`is_expired: true`) và
  refresh token cũng không còn hợp lệ ở phía server.
- Lúc 2026-11-04 04:20:53 (+07), lần chạy đầu tiên của spike (`grok agent --no-leader stdio`,
  chỉ gửi `initialize` và `_x.ai/billing`) khiến `grok` thử refresh. Server trả về
  `RefreshTokenRejected` và `grok` xoá `~/.grok/auth.json`.
- Hệ quả: **cần chạy `grok login` lại**. Không mất session hay config nào khác.
  `auth.json.lock` vẫn còn (đây là hành vi bình thường).
- Ngoài ra, `grok` tự cập nhật lên 1.0.70 (symlink `~/.grok/bin/grok` → `downloads/grok-1.0.70-macos-aarch64`).

## 6. Các hướng đã thử nhưng không dùng

| Thử | Kết quả |
|---|---|
| `grok --help`, các subcommand | Không có lệnh account/limit. `grok usage <session>` chỉ cho token và chi phí **của một session** đã lưu, không phải hạn mức tài khoản |
| Docs `~/.grok/docs` | Chỉ mô tả UI `/usage` (04-slash-commands, 23-dashboard). `24-monitoring-usage` là OTEL, không liên quan |
| ACP `x.ai/billing` (không có `_`) | `-32601 Method not found` |
| `session/new` trước khi gọi billing | Không cần, và không có tác dụng khi chưa có credential |
| PTY scrape TUI `/usage` | Không làm, vì đã tìm được cơ chế ACP sạch hơn |
| Gọi HTTP trực tiếp `/billing?format=credits` | Không làm, vì không có credential hợp lệ và hướng này không được khuyến nghị (§4.5) |
