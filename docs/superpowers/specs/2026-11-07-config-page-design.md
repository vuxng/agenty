# Agenty — trang Config cho settings tầng user của Claude và Codex

- **Ngày:** 2026-11-07
- **Trạng thái:** Đã duyệt
- **Repo:** github.com/vuxng/agenty
- **Dựa trên:** `DESIGN.md`, `docs/superpowers/specs/2026-11-06-app-shell-instructions-design.md`
- **Phiên bản đã kiểm tra:** Claude Code 2.1.319, Codex CLI 0.162.1
- **Mockup:** `.superpowers/brainstorm/31071-1793989688/content/` (chỉ có trên máy, không commit), hướng A trong
  `concepts.html`, cấu trúc 1 trong `structure.html`

## 1. Mục tiêu

Agenty sửa được `CLAUDE.md` và `AGENTS.md`, nhưng muốn đổi model, quyền hay plugin thì vẫn phải nhớ tên key và
sửa tay file cấu hình. Spec này thêm trang **Config / Cấu hình** trên thanh giữa toolbar. Trang có control cho
các nhóm hay dùng, kèm chế độ xem và sửa toàn bộ file cho phần còn lại.

**Thành công khi:**
- Đổi một giá trị trong Agenty, bấm Lưu, thì phiên CLI mới nhận đúng giá trị đó, ở cả Claude và Codex.
- Sau khi lưu, mọi thứ Agenty không quản lý vẫn nguyên vẹn: key lạ, thứ tự key, comment trong TOML, `[desktop]`,
  MCP, hook. Ngoại lệ duy nhất là comment nằm ngay trước một key bị xoá, xem mục 4.2.
- Mỗi giá trị quyền đều có một câu nói agent làm được gì, không cần tra tài liệu.
- Không có đường nào làm mất nội dung âm thầm: không ghi đè thay đổi từ CLI hay editor khác, không mất bản nháp
  khi đóng cửa sổ.
- Thêm một nhóm sau này chỉ cần thêm một thẻ và các key của nó.

## 2. Phạm vi

### Trong phạm vi
- `~/.claude/settings.json` và `~/.codex/config.toml`.
- Control cho ba nhóm: Model, Quyền và sandbox, Plugin.
- Xem và sửa toàn bộ hai file trên, có kiểm tra trước khi ghi.
- Chuỗi en và vi trong `Localizable.xcstrings`, cập nhật `DESIGN.md` và README.

### Ngoài phạm vi
- Cấp project, local và managed: `.claude/settings.json`, `.claude/settings.local.json`, `.codex/config.toml`
  trong repo, `requirements.toml`, `managed-settings.json`. Giá trị managed chỉ được báo, không sửa được.
- `~/.claude.json`, `~/.codex/hooks.json`, profile của Codex.
- Control cho các nhóm khác: Memory và context, Thông báo, Giao diện CLI, Dữ liệu và cập nhật, Git, MCP, hook.
  Các nhóm này vẫn sửa được ở chế độ File.
- Mục lục bên lề. Khi có từ khoảng 8 nhóm trở lên thì xem lại, các thẻ giữ nguyên.
- Cài và gỡ plugin. Trang chỉ bật và tắt plugin đã cài.
- `permissions.allow/ask/deny`, `autoMode`, và các key con của `sandbox` ngoài `sandbox.enabled`.
- `CODEX_HOME` và `CLAUDE_CONFIG_DIR`, cùng lý do với spec trước: app chạy từ GUI chỉ dùng đường dẫn mặc định.
- Bump version và phát hành, làm riêng sau khi merge.

## 3. Thiết kế giao diện

### 3.1 Bố cục

Hero và thẻ theo kiểu trang Usage, chế độ File theo kiểu trang Instructions. Lưới hai cột cố định, cách nhau
16pt, lề trang 24pt, rộng tối đa 960pt, density Default. Cả trang cuộn, không cuộn lồng trong thẻ.

| Vùng | Thành phần | Ghi chú |
|---|---|---|
| Thanh giữa toolbar | Mục Config / Cấu hình | Sau Instructions |
| Hàng đầu | Bộ chọn provider bên trái, Điều khiển / File bên phải | Lớp glass. Hai trang dùng chung provider đang chọn |
| Hero | Nhãn Model, tên model 52pt, đường dẫn, Hiện trong Finder, "Áp dụng cho phiên mới" | Tên model là `Menu` |
| Cột trái | Thẻ Model, rồi các thẻ quyền | Mục 3.2 và 3.3 |
| Cột phải | Thẻ Plugin | Mục 3.4 |
| Chế độ File | Tên file 52pt, đường dẫn, editor rộng tối đa 720pt | Như trang Instructions, không tô màu Markdown |
| Đáy | Viên lưu | Chỉ hiện khi có việc cần làm |
| Nền | `AmbientField` của provider đang chọn, độ mạnh 0.45 | Như trang Instructions |

Không có breakpoint. Cửa sổ tối thiểu 860×580 vẫn giữ hai cột. Thẻ dùng `.thinMaterial`, bo góc 24pt, padding
24pt, không dùng `Form` kiểu Settings.

### 3.2 Nhóm Model

**Tên model (`Menu` ở hero):**

| | Claude, key `model` | Codex, key `model` |
|---|---|---|
| Danh sách | Mặc định, `best`, `fable`, `opus`, `sonnet`, `haiku`, `opus[1m]`, `sonnet[1m]`, `opusplan` | Từ `model/list`, hiện `displayName`, ghi `model` |
| Tuỳ ý | Có mục "Khác…" để nhập ID | Không có |

Mặc định nghĩa là không đặt key.

**Thẻ Model:**

- **Mức suy luận:** `Slider` có `SliderTick` (macOS 26 trở lên). Nấc đầu luôn là "Mặc định", tức xoá key.
  - **Claude:** nấc `low`, `medium`, `high`, `xhigh`. `max` không lưu được nên không có. Mỗi thanh ứng với đúng
    một key: một thanh cho mỗi mục trong `modelSettings` (`modelSettings.<model>.effortLevel`), và một thanh
    "Model khác" cho `effortLevel` chung. Lý do: giá trị theo model luôn thắng giá trị chung trong cùng file,
    nên một thanh duy nhất sẽ gây hiểu nhầm. `modelSettings` không có mục nào có `effortLevel` thì chỉ còn thanh
    chung, nhãn là "Mức suy luận".
  - **Codex:** một thanh cho `model_reasoning_effort`, nấc lấy từ `supportedReasoningEfforts` của model đang
    chọn. Đổi sang model không hỗ trợ mức hiện tại thì thanh về Mặc định và hiện một dòng báo.
- **Fast:** `Toggle`.
  - **Claude:** key `fastMode`.
  - **Codex:** bật ghi `service_tier = "priority"`, tắt thì xoá key. Mô tả lấy từ `serviceTiers` của model.
    Model không có tier thì ẩn. `service_tier` đang là `default` hoặc chưa đặt thì coi là tắt. Giá trị khác, như
    `flex`, hiện nguyên giá trị và khoá toggle, kèm lời nhắc sửa ở File.

### 3.3 Nhóm Quyền và sandbox

Dùng `Picker` kiểu `.radioGroup`, xếp từ chặt tới thoáng. Câu mô tả hiện dưới giá trị đang chọn, các giá trị
khác xem qua `.help`.

**Claude, thẻ Quyền, key `permissions.defaultMode`:**

| Nhãn | Giá trị | Mô tả |
|---|---|---|
| Don't ask | `dontAsk` | Chỉ chạy công cụ đã duyệt trước, còn lại từ chối |
| Plan | `plan` | Chỉ đọc và lập kế hoạch |
| Manual | không đặt key | Đọc tự do, hỏi trước khi sửa file hay chạy lệnh |
| Accept edits | `acceptEdits` | Tự sửa file, hỏi trước các lệnh khác |
| Auto | `auto` | Tự làm mọi việc, có kiểm tra an toàn chạy nền |
| Bypass | `bypassPermissions` | Bỏ qua mọi kiểm tra. Chỉ nên dùng trong container hoặc VM |

File đang ghi `default` hoặc `manual` thì cũng hiện là Manual và không bị đổi nếu người dùng không chọn lại.

**Claude, thẻ Sandbox, key `sandbox.enabled`:** Mặc định, Bật, Tắt.

**Codex, thẻ Sandbox, key `sandbox_mode`:**

| Nhãn | Mô tả |
|---|---|
| Chưa đặt | Codex dùng giá trị mặc định của nó |
| `read-only` | Chỉ đọc file |
| `workspace-write` | Ghi được trong thư mục làm việc |
| `danger-full-access` | Toàn quyền trên máy, không có sandbox |

**Codex, thẻ Phê duyệt, key `approval_policy`:**

| Nhãn | Mô tả |
|---|---|
| Chưa đặt | Codex dùng giá trị mặc định của nó |
| `untrusted` | Tự chạy lệnh an toàn đã biết, còn lại hỏi |
| `on-request` | Model tự quyết khi nào cần hỏi |
| `never` | Không bao giờ hỏi, lỗi trả thẳng cho model |

**Giá trị nguy hiểm** gồm `bypassPermissions`, `danger-full-access`, `never`. Khi chọn, câu mô tả chuyển màu cam
kèm icon cảnh báo. Khi bấm Lưu, nếu nháp có giá trị nguy hiểm mà trên đĩa chưa có, hộp xác nhận nêu rõ các giá
trị đó, nút mặc định là Huỷ. Sửa tay ở chế độ File thì không hỏi.

**Giá trị lạ:** giá trị trong file mà Agenty không biết, như `delegate` hay bảng `granular`, hiện thành một lựa
chọn thêm và không bị đổi khi lưu. Bảng `granular` hiện là "Tuỳ chỉnh", sửa ở chế độ File.

### 3.4 Nhóm Plugin

Thẻ có đếm số đang bật, ô tìm, 8 dòng đầu, rồi "Xem tất cả" mở rộng ngay trong thẻ. Mỗi dòng là tên và `Toggle`.

| | Claude | Codex |
|---|---|---|
| Danh sách | `claude plugin list --json` | `plugin/installed`, tên từ `interface.displayName`, không có thì dùng phần trước `@` của id |
| Key | `enabledPlugins."<id>"` | `plugins.<id>.enabled` |
| Chỉ xem | Plugin có `scope` khác `user`, ví dụ `synced`, hiện mờ kèm nhãn "đồng bộ", không có toggle | Không có |
| Thiếu CLI | Chỉ hiện các plugin trong `enabledPlugins`, kèm một dòng báo | Xem 3.5 |

Không dùng `plugin/list` vì trả về cả chợ plugin, khoảng 27 MB. `plugin/installed` khoảng 59 KB.

### 3.5 Hành vi và trạng thái

Control chỉ đổi bản nháp, ghi file chỉ xảy ra khi bấm Lưu.

| Tình huống | Hành vi |
|---|---|
| Đang tải | Vòng xoay trong các thẻ, giữ nguyên bố cục |
| Đổi control | Đổi bản nháp và hiện viên lưu: "Thay đổi chưa lưu", Hoàn nguyên, Lưu (⌘S). Mỗi provider có nháp riêng, nằm trong model nên đóng cửa sổ vẫn giữ |
| Chọn Mặc định hoặc Chưa đặt | Xoá key khỏi file |
| Lưu xong | Viên lưu biến mất, đọc lại file để lấy version mới |
| File đổi từ ngoài, chưa có nháp | Tự tải lại |
| File đổi từ ngoài, đang có nháp | Viên lưu: "Đã thay đổi bên ngoài Agenty", Giữ bản của tôi, Tải lại. Ở chế độ Điều khiển, Giữ bản của tôi chỉ áp lại đúng các key đã đổi lên file mới. Ở chế độ File, giữ như trang Instructions |
| Chuyển Điều khiển ↔ File khi có nháp | Hộp thoại Lưu, Bỏ, Huỷ |
| Lưu ở chế độ File | Kiểm tra trước khi ghi (mục 4.3). Nếu lỗi, viên lưu nêu lý do, kèm dòng khi có, giữ nháp, file không đổi |
| Lưu lỗi | Viên lưu nêu lý do, kèm Thử lại, giữ nháp |
| File chưa có | Control hiện Mặc định, lưu thì tạo file |
| File đang lỗi | Chế độ Điều khiển hiện lý do kèm nút sang File |
| Không tìm thấy CLI Codex | Chế độ Điều khiển hiện lỗi và nút Chọn đường dẫn như popover. File vẫn sửa được, kèm dòng báo chưa kiểm tra được |
| Codex cũ thiếu API | "Phiên bản Codex này chưa hỗ trợ", chỉ tắt control, chế độ File vẫn dùng được |
| Giá trị bị tổ chức ghi đè (`okOverridden`) | Dòng cam dưới đường dẫn file, nêu `message` của Codex. Phản hồi không cho biết key nào nên không đặt dưới từng control |
| Thoát app khi có nháp | Hộp thoại Save, Discard, Cancel hiện có, gộp cả nháp Config |

Làm mới khi trang xuất hiện, khi app được activate, khi đổi provider và ngay trước khi lưu. Nội dung file không
đổi thì không gọi lại `app-server`, trừ lúc vào trang. Danh sách plugin tải lại cùng lần đọc đó, vì trạng thái bật
của plugin nằm trong file.

## 4. Kiến trúc

Logic đặt trong `UsageCore` vì target app không có test, cùng lý do với spec trước.

### 4.1 Các unit

| Unit | Vị trí | Trách nhiệm |
|---|---|---|
| `TextFile` | `UsageCore/Infrastructure/` | Đọc, ghi an toàn, xử lý symlink, tách từ `InstructionsFile`. `InstructionsFile` chuyển sang dùng nó |
| `OrderedJSON` | `UsageCore/Config/` | Đọc JSON giữ thứ tự key và số nguyên văn, đặt hoặc xoá theo đường dẫn key, ghi ra thụt 2 dấu cách và xuống dòng ở cuối |
| `AgentConfig`, `ConfigEdit` | `UsageCore/Config/` | Dữ liệu thuần: model, mức suy luận, lựa chọn, plugin, thay đổi theo key (đặt hoặc xoá) |
| `ConfigBackend` | `UsageCore/Config/` | Protocol: `load`, `save(edits, version)`, `validate(text)`, `writeFile(text)` |
| `ClaudeConfigBackend` | `UsageCore/Config/` | Đọc, sửa `settings.json`, lấy plugin |
| `CodexConfigBackend` | `UsageCore/Config/` | Gọi `app-server`, kiểm tra bản nháp, ghi file ở chế độ File |
| `ConfigDocument` | `UsageCore/Config/` | `@Observable`: chế độ, nháp theo key, nháp text, xung đột, lỗi, nhận biết giá trị nguy hiểm. Chỉ phụ thuộc `ConfigBackend` |
| `ConfigPage` và các thẻ | `App/Views/Main/` | Giao diện |
| `ProviderSelector` | `App/Views/Main/` | Tách từ `InstructionsPage` để hai trang dùng chung |
| `SaveCapsule` | `App/Views/Main/` | Chuyển sang nhận một protocol, phục vụ cả hai trang |

`AppModel` giữ một `ConfigDocument` cho mỗi provider. `selectedInstructions` đổi thành provider đang chọn dùng
chung cho hai trang.

### 4.2 Codex

Mỗi thao tác mở một tiến trình `codex app-server` như `CodexProvider`, dùng `JSONRPCClient` và `CLILocator`.
Đo trên máy: khởi động 0,15 giây, `config/read` và `model/list` gần như tức thì, `plugin/installed` 0,8 giây.

- **Đọc:** `config/read` với `includeLayers: true`. Version là `version` của layer `user`.
- **Đọc giá trị:** lấy từ `config` của layer `user`, không lấy `config` đã gộp, vì trang chỉ quản lý tầng user.
- **Danh sách model:** `model/list` có phân trang, đọc tiếp theo `nextCursor`.
- **Dòng dài:** mỗi phản hồi nằm trên một dòng, `plugin/installed` đã 59 KB. `SubprocessRunner` phải nới giới hạn
  mặc định 128 KiB, nếu không người có nhiều plugin sẽ lỗi cả trang.
- **Ghi:** một `config/batchWrite` với `expectedVersion`. Xoá key bằng `value: null`. Đã thử trên file giả: chỉ
  đổi đúng các dòng cần đổi, comment, ghi chú cuối dòng, `[desktop]` và key lạ đều còn nguyên. Tạo mới file khi
  chưa có và ghi `enabled` cho plugin chưa có section đều chạy được.
- **Giới hạn đã biết:** khi xoá một key, Codex xoá luôn comment nằm ngay trước key đó, vì comment gắn với key.
  Lần đầu thêm section plugin mới, Codex có thể chèn một dòng `[plugins]` trống. Cả hai đều do Codex, không ảnh
  hưởng giá trị.
- **Key có dấu chấm:** đường dẫn key tách theo dấu chấm, nên phần nào chứa dấu chấm phải đặt trong ngoặc kép, ví
  dụ `plugins."x.y@c".enabled`. Đã thử: không có ngoặc kép thì ghi sai chỗ.
- **Lỗi:** `error.data.config_write_error_code` phân biệt `configVersionConflict` và `configValidationError`.
  `JSONRPCError.server` cần mang thêm `data`. Method không tồn tại trả về `-32600` với "unknown variant", không có
  `config_write_error_code`, đó là dấu hiệu Codex cũ.

### 4.3 Kiểm tra và ghi ở chế độ File

- **Claude:** đọc bằng `OrderedJSON`, lỗi thì không ghi. Không kiểm tra theo schema.
- **Codex:** ghi bản nháp vào thư mục tạm chỉ chủ tài khoản đọc được, chạy `app-server` với `CODEX_HOME` trỏ tới
  đó, gọi `config/read`, rồi xoá thư mục. Đã thử: lỗi cú pháp trả về `config.toml:2:9: unclosed table`, giá trị
  sai trả về tên key và các giá trị hợp lệ. Lỗi giá trị không kèm số dòng.
- Qua kiểm tra thì ghi bằng `TextFile`. Không tìm thấy CLI thì vẫn ghi được, kèm dòng báo.

### 4.4 Claude

`ClaudeConfigBackend` đọc file bằng `OrderedJSON`, áp các `ConfigEdit` rồi ghi bằng `TextFile`. Version là nội
dung file đã đọc, so sánh như `InstructionsDocument`. Đã thử: thụt 2 dấu cách và xuống dòng ở cuối cho ra đúng
từng byte `settings.json` hiện tại, nên lần lưu đầu không làm xáo trộn file. Không dùng `JSONValue` vì kiểu này
không giữ thứ tự key.

`ProcessRunner` chỉ đọc stdout, đủ cho `claude plugin list --json`, đọc hết các dòng rồi mới parse.

### 4.5 Thoát app

`applicationShouldTerminate` đang lưu đồng bộ, còn lưu Codex là bất đồng bộ. Khi có nháp Config, trả về
`.terminateLater` và gọi `reply(toApplicationShouldTerminate:)` sau khi lưu xong. Lưu lỗi thì huỷ thoát và mở
trang Config của provider đó, như Instructions đang làm.

### 4.6 Rủi ro

- **`app-server` còn gắn nhãn experimental.** Trang Usage đã phụ thuộc vào nó. Test tích hợp ở mục 5 báo sớm nếu
  bản Codex mới đổi hành vi.
- **Chưa thử trên file thật.** Các lần thử ghi chỉ chạy trên file giả với Codex 0.162.1.
- **Thư mục tạm chứa bản sao cấu hình.** Có thể có secret trong `mcp_servers.*.env`, nên phải giới hạn quyền và
  luôn xoá, kể cả khi lỗi.

## 5. Kiểm thử

Unit test trong `UsageCoreTests`, chạy cả trên CI:

- **`OrderedJSON`:** đọc rồi ghi lại giống hệt từng byte. Đặt và xoá key lồng nhau mà giữ thứ tự, key lạ, số và
  Unicode. JSON lỗi thì báo lỗi.
- **`TextFile`:** các test ghi file hiện có của Instructions vẫn pass: symlink, giữ quyền file.
- **`ClaudeConfigBackend`:** đọc đúng giá trị. Mức suy luận theo model và mức chung ghi đúng key. Chỉ key đã đổi
  bị thay đổi. Thiếu file, thiếu CLI, plugin `synced` chỉ xem.
- **`CodexConfigBackend`:** dùng fake channel với dữ liệu lấy từ giao thức thật. Tham số `config/batchWrite` đúng.
  Xung đột version, lỗi giá trị và Codex cũ thiếu API ra đúng lỗi.
- **`ConfigDocument`:** nháp, hoàn nguyên, xung đột. Giữ bản của tôi chỉ áp lại key đã đổi. Lưu lỗi vẫn giữ nháp.
  Nhận đúng giá trị nguy hiểm mới so với trên đĩa. Đổi model thì mức suy luận về Mặc định khi không còn hỗ trợ.
  Giá trị lạ không bị đổi khi lưu.
- **`JSONRPCClient`:** lỗi server mang theo `data`.

Một test tích hợp với `codex` thật, bỏ qua khi máy không có CLI: ghi vào `CODEX_HOME` tạm có comment, `[desktop]`
và key lạ, rồi kiểm tra các phần đó còn nguyên.

Không viết test tự động cho SwiftUI, có `#Preview` cho các trạng thái chính: Claude, Codex, đang tải, lỗi file,
thiếu CLI, cảnh báo cam.

Kiểm tra bằng mắt một lần trên bản Agenty Dev, với thư mục home tạm để không đụng cấu hình thật: đổi một giá trị
ở mỗi provider rồi xem diff file, thử một giá trị nguy hiểm, xem cửa sổ tối thiểu và cửa sổ rộng, light và dark.

## 6. Cập nhật `DESIGN.md`

- **Typography:** thêm vai trò "Tên model", 52pt, thin, rounded, dùng cho hero trang Config.
- **Components:** thêm Thẻ cấu hình, cùng chất liệu với thẻ provider. Thêm Trang Config vào nhóm Template. Viên lưu
  có thêm trạng thái lỗi kiểm tra.
- **Không có control tự viết.** `Slider`, `Picker`, `Toggle`, `Menu` đều là control hệ thống.
