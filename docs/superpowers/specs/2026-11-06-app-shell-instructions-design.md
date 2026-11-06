# Agenty — cửa sổ chính Ambient và trình sửa instructions toàn cục

- **Ngày:** 2026-11-06
- **Trạng thái:** Đã duyệt
- **Repo:** github.com/vuxng/agenty
- **Dựa trên:** `DESIGN.md`
- **Bản thử tham khảo:** `docs/superpowers/spikes/2026-11-06-ambient-prototype.swift` (đồ thử, không dùng lại nguyên văn)

## 1. Mục tiêu

Agenty hiện chỉ có popover trên menu bar và cửa sổ Settings, nên không có chỗ cho các tính năng lớn hơn.
Spec này thêm một cửa sổ chính có cá tính riêng, mỗi tính năng là một mục trên thanh điều hướng:

- **Usage:** xem usage của từng provider ở dạng số lớn.
- **Instructions:** xem và sửa file áp dụng cho mọi session trên máy, gồm `~/.claude/CLAUDE.md` và
  `~/.codex/AGENTS.md`.

Hướng dài hạn (giả định, chưa chốt danh sách): Agenty là trung tâm quản lý Claude/Codex trên máy.

**Thành công khi:**
- Từ popover mở được cửa sổ chính. Icon Dock hiện khi cửa sổ mở và biến mất khi cửa sổ đóng.
- Trang Usage hiện đúng các mục Agenty hỗ trợ, với đúng tên và định dạng như popover.
- Sửa `CLAUDE.md` trong Agenty, bấm Save, thì session Claude Code mới nhận nội dung đó. Với Codex và
  `AGENTS.md` cũng vậy.
- Gõ tiếng Việt bằng bộ gõ trong editor không bị lỗi ký tự.
- Không có đường nào làm mất nội dung âm thầm: không ghi đè thay đổi từ editor khác, không mất bản nháp
  khi đóng cửa sổ, không phá symlink.
- Thêm một tính năng sau này chỉ cần thêm một case vào `AppPage` và view của nó.

## 2. Phạm vi

### Trong phạm vi
- Cửa sổ chính, trang Usage, trang Instructions và các trạng thái của chúng.
- Đổi activation policy để hiện và ẩn icon Dock.
- Nút mở cửa sổ chính trong footer popover.
- Lệnh trong menu bar cho các action trên toolbar và trang (Refresh, Save), theo HIG.
- Chuỗi en và vi trong `Localizable.xcstrings`, cập nhật README.

### Ngoài phạm vi
- Instructions của project, `config.toml`, `settings.json`, hook, MCP, skill.
- Render Markdown thành văn bản, lịch sử phiên bản. Editor chỉ tô màu trên chính text nguồn.
- `CODEX_HOME` và `CLAUDE_CONFIG_DIR`: app chạy từ GUI không thấy biến môi trường của shell, nên chỉ dùng
  đường dẫn mặc định. Đường dẫn luôn hiện trên giao diện.
- Đổi giao diện popover và Settings, trừ nút mở cửa sổ chính.
- Bump version và phát hành, làm riêng sau khi merge.

## 3. Thiết kế giao diện

### 3.1 Khung cửa sổ

`Window` một instance, id `main`, không tự mở khi khởi động app (`.defaultLaunchBehavior(.suppressed)`).
Dùng `.windowStyle(.hiddenTitleBar)`, `.windowToolbarStyle(.unified)`, bỏ tiêu đề toolbar và nền toolbar.
Cửa sổ tối thiểu 860×580.

| Vùng | Thành phần | Ghi chú |
|---|---|---|
| Nền | `MeshGradient` trên `windowBackgroundColor`, tràn cửa sổ | Usage: Claude từ góc trên trái, Codex từ góc dưới phải. Instructions: chỉ màu provider đang chọn, độ mạnh 0.45 |
| Toolbar giữa | Các mục `AppPage` | Hệ thống canh traffic light thẳng hàng với thanh này |
| Toolbar phải | `Updated` và nút Refresh | Chỉ ở trang Usage |
| Settings | Giữ cửa sổ `Settings` hiện tại (⌘,) | Không đưa vào thanh điều hướng |
| Popover | Giữ nguyên, thêm nút mở cửa sổ chính | Đang mở thì đưa lên trước |

Mục đang chọn lưu trong `AppStorage`. Lần đầu mở vào Usage.

**Giới hạn đã biết:** thanh giữa toolbar chỉ hợp với số mục ít. Khi tính năng nhiều lên phải xem lại cách
điều hướng.

### 3.2 Dock

Giữ `LSUIElement: true`. Khi cửa sổ chính xuất hiện, gọi `NSApp.setActivationPolicy(.regular)` rồi activate.
Khi cửa sổ đóng, trả về `.accessory`. Cửa sổ Settings không đổi hành vi.

### 3.3 Trang Usage

Mỗi provider đang bật là một thẻ, các thẻ cạnh nhau, rộng tối đa 960pt, canh giữa cả chiều ngang và dọc.
Nội dung giữ cỡ cố định khi cửa sổ to ra.

Thẻ đọc từ trên xuống: logo và tên, gói (bên phải), tên giới hạn, số lớn, thời gian reset, đường kẻ, các dòng phụ.

- **Số lớn** là `UsageWindow.mostConstrained(in:)` của provider đó. Tên giới hạn lấy từ `Formatting.title`.
- **Dòng phụ** là các cửa sổ còn lại theo thứ tự API, rồi đến Credits nếu `Formatting.credits` có giá trị.
- **Thời gian reset** lấy từ `Formatting.reset`. Dòng phụ ẩn thời gian khi trùng với dòng trước, giống popover.
- **Email tài khoản** hiện dưới tên khi bật `showAccountEmail`.

| Trạng thái | Cách hiển thị |
|---|---|
| Mức warning | Số lớn màu cam, icon cảnh báo cạnh tên giới hạn |
| Mức critical | Số lớn màu đỏ, icon khác cạnh tên giới hạn |
| Mất mạng hoặc bị giới hạn, có số cũ | Số mờ đi, thêm dòng lỗi trong thẻ. Popover giữ nguyên cách cũ |
| Lỗi khác, có số cũ | Dòng cảnh báo dưới đầu thẻ, số mờ đi |
| Đang tải, chưa có số | Vòng xoay giữa thẻ |
| Không có cửa sổ nào | Icon và "No active limits" thay chỗ số lớn, vẫn hiện Credits nếu có |
| Lỗi, không có số | Icon và câu lỗi thay chỗ số lớn, kèm nút khi có việc để làm |
| Không bật provider nào | `ContentUnavailableView` như popover |

Câu lỗi và nút (Choose path…, Retry, Report issue) dùng chung với popover. Mức warning và critical theo
ngưỡng trong Settings.

### 3.4 Trang Instructions

File nằm thẳng trên trường màu, không có khung, cột rộng tối đa 720pt canh giữa.

Từ trên xuống: bộ chọn provider dạng tab glass có logo và tên, canh trái ngay trên tên file, rồi tên file cỡ lớn.
Tiếp theo là đường dẫn, nút Show in Finder, "Applies to new sessions". Sau đó là editor. Viên lưu nổi ở đáy,
canh giữa.

Dấu `#` và `-` mang màu provider, heading đậm hơn và lớn hơn. File ghi ra vẫn là Markdown thuần.
Cả hai provider luôn hiện, kể cả khi đã tắt theo dõi usage. Mỗi provider giữ bản nháp riêng.

| Trạng thái | Cách hiển thị |
|---|---|
| Không có thay đổi | Không có viên lưu |
| Có thay đổi | Viên lưu: "Unsaved changes", Revert, Save (⌘S) |
| File chưa có | Chữ mờ trong editor: "This file doesn't exist yet. Agenty creates it when you save." Lưu tạo cả thư mục cha nếu thiếu |
| `AGENTS.override.md` không trống | Dòng cam dưới đường dẫn. Override trống thì không cảnh báo, vì Codex lấy file không trống đầu tiên |
| File đổi từ ngoài, không có bản nháp | Tự tải lại |
| File đổi từ ngoài, có bản nháp | Viên lưu: "Changed outside Agenty", Keep Mine, Reload |
| Lưu lỗi | Viên lưu nêu lý do, kèm Try Again, giữ nguyên bản nháp |
| File không đọc được hoặc không phải UTF-8 | Thông báo thay cho editor, kèm Show in Finder |

Keep Mine giữ bản nháp và coi nội dung mới trên đĩa là gốc, nên lần Save sau mới ghi đè.

**Đóng cửa sổ và thoát app:** bản nháp nằm trong model của app, không nằm trong view, nên đóng cửa sổ không
mất gì và mở lại vẫn còn. Thoát app khi còn bản nháp thì hỏi xác nhận qua `applicationShouldTerminate`, với
ba lựa chọn Save, Discard, Cancel.

## 4. Kiến trúc

Logic đặt trong `UsageCore` vì target app không có test. Tên package hơi lệch với phần mới, nhưng tách package
riêng lúc này chưa đáng.

| Unit | Vị trí | Trách nhiệm |
|---|---|---|
| `InstructionsFile` | `UsageCore/Instructions/` | Đường dẫn theo provider, đọc, ghi, kiểm tra override |
| `InstructionsDocument` | `UsageCore/Instructions/` | `@Observable`: nội dung gốc, bản nháp, trạng thái, xung đột, lưu, revert |
| `MarkdownLineStyle` | `UsageCore/Instructions/` | Phân loại từng dòng và vị trí dấu, chưa dính SwiftUI |
| `AppPage` | `App/Views/Main/` | Enum `CaseIterable` với title và view của từng mục |
| `MainWindow`, `AmbientField` | `App/Views/Main/` | Khung và nền |
| `UsagePage`, `UsageProviderCard` | `App/Views/Main/` | Trang Usage |
| `InstructionsPage`, `SaveCapsule` | `App/Views/Main/` | Trang Instructions |
| `DockPolicy` | `App/System/` | Đổi activation policy theo cửa sổ chính |

`AppModel` giữ một `InstructionsDocument` cho mỗi provider, tạo từ `home` sẵn có trong `init`.
Câu lỗi trong `ProviderErrorView` được tách ra để popover và thẻ provider dùng chung.

**Đọc:** đọc `Data`, giải mã UTF-8. File không tồn tại là trạng thái hợp lệ với nội dung rỗng.

**Phát hiện thay đổi ngoài:** so nội dung trên đĩa với nội dung gốc khi trang xuất hiện, khi app được activate,
và ngay trước khi lưu. Không dùng file watcher, vì file nhỏ và các thời điểm này đã đủ.

**Ghi:** resolve symlink để lấy file đích, ghi ra file tạm cùng thư mục, rồi dùng `FileManager.replaceItemAt`
để thay file mà vẫn giữ quyền truy cập. App không sandbox nên không cần xin quyền file.

**Rủi ro lớn nhất, làm đầu tiên:** bản thử chỉ tô màu một lần lúc mở, chưa tô lại khi đang gõ. Tô lại trong lúc
bộ gõ tiếng Việt đang ghép chữ có thể làm hỏng ký tự. Bước đầu của phần editor là kiểm tra `TextEditor` với
`AttributedString`. Nếu không ổn thì bọc `NSTextView` để chỉ tô lại khi không có marked text.

## 5. Kiểm thử

Unit test trong `UsageCoreTests`, dùng thư mục tạm:
- Đọc file có sẵn, file thiếu, file không phải UTF-8.
- Lưu tạo được file và thư mục cha, giữ quyền truy cập, ghi xuyên symlink mà symlink còn nguyên.
- Override: không có, trống, không trống.
- Bản nháp: dirty, revert, tự tải lại khi sạch, báo xung đột khi có nháp, Keep Mine rồi lưu.
- Phân loại dòng Markdown: heading các cấp, danh sách, dòng thường.

Phần giao diện: build, SwiftUI preview, và xem nhanh trên bản Agenty Dev: mở cửa sổ, icon Dock, cửa sổ nhỏ và
full screen, light và dark, gõ tiếng Việt, lưu thử một lần. Đo tương phản của màu provider trên nền sáng.
