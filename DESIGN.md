# Agenty Design Language

> App macOS cho dev dùng Claude, Codex và Grok: theo dõi usage, quản lý cấu hình trên máy.

## 1. Visual Theme

**Theme statement:** ambient, precise, instrument

**Character:** Cửa sổ chính là một trường màu sinh ra từ các provider, trên đó là số liệu cỡ lớn và text
kỹ thuật. Chất liệu vẫn của macOS 27 (Liquid Glass, material, type), còn bố cục thì không theo khuôn
sidebar mặc định. Popover và Settings vẫn gọn và native.

**Reference:** Apple Human Interface Guidelines, SwiftUI.

**Dials:** Creativity=Bold (ở bố cục), Density=Balanced, Variance=Uniform, Motion=thấp.

## 2. Color Palette

Accent, text, bề mặt và màu trạng thái đều của hệ thống, tự đổi theo light/dark. Màu riêng duy nhất là
màu của từng provider.

| Vai trò | Giá trị | Dùng cho |
|---|---|---|
| Accent | Accent của hệ thống (không có asset `AccentColor`) | Selection, nút chính, focus |
| Text | `.primary`, `.secondary`, `.tertiary` | Nội dung, thông tin phụ |
| Bề mặt | `.thinMaterial`, `.fill`, `.quaternary` | Thẻ, badge, nền thanh progress |
| Thanh progress, số lớn mức thường | `.primary` | Không dùng accent |
| Warning | `.orange` | Usage cao, cảnh báo |
| Error | `.red` | Usage nguy hiểm |
| Success | `.green` | Trạng thái ổn |
| Provider Claude | `#D97857` | Trường màu, dấu Markdown |
| Provider Codex | `#6B6BF2` | Trường màu, dấu Markdown |
| Provider Grok | `#9AA0A6` | Trường màu |

Màu provider chỉ dùng cho trường màu nền và dấu Markdown trong editor, không dùng cho chữ nội dung hay nút.
Trang có nhiều chữ dùng trường màu nhạt hơn, chỉ của provider đang chọn.
Trạng thái luôn kèm icon hoặc chữ, không chỉ dựa vào màu.

## 3. Typography

**Font:** SF Pro, SF Pro Rounded và SF Mono của hệ thống. Dùng text style, trừ glyph trên menu bar và
các cỡ hiển thị lớn ghi trong bảng.

| Vai trò | Style | Dùng cho |
|---|---|---|
| Số lớn | 112pt, thin, rounded, `.monospacedDigit()` | Giới hạn gần chạm nhất của provider |
| Tiêu đề trang | 52pt, thin, rounded | Tên file (Instructions), số agent và tên agent (Agents) |
| Tên model | 52pt, thin, rounded | Hero trang Config |
| Tiêu đề thẻ | `.title3`, semibold | Tên provider và tên agent trên thẻ |
| Nhãn khối | `.headline`, `.secondary` | Tên giới hạn trên số lớn |
| Nội dung | `.body` | Text thường |
| Phụ, trạng thái | `.caption`, `.secondary` | Thời gian, ghi chú |
| Số liệu | Style theo ngữ cảnh + `.monospacedDigit()` | Phần trăm, thời gian reset |
| Đường dẫn | `.caption` + `.monospaced()` | Đường dẫn file |
| Nội dung file | 13pt monospaced, heading đậm và lớn hơn | Editor |

Riêng popover còn dùng `.subheadline.weight(.medium)`, `.callout`,
`.caption2.weight(.medium)`.

## 4. Components

| Component | Cấp | Mục đích | Biến thể |
|---|---|---|---|
| `ProviderCard` | Component | Usage của một provider | Có lỗi, đang tải |
| `WindowRow` | Component | Một cửa sổ usage kèm thanh progress | Có hoặc không có thời gian reset |
| `ProviderErrorView` | Component | Lỗi kèm cách xử lý | Theo loại lỗi |
| `UpdateBanner` | Component | Báo có bản mới | — |
| `UsagePopover` | Template | Xem nhanh từ menu bar | — |
| Settings panes | Template | Cài đặt, dùng `Form` grouped | General, Providers, Notifications |
| Thẻ provider | Component | Một provider trong cửa sổ chính | Bình thường, cảnh báo, số cũ, không có số |
| Thẻ cấu hình | Component | Nhóm cấu hình, cùng chất liệu `.thinMaterial`, bo góc 24pt và padding 24pt như thẻ provider | Model, quyền, sandbox, plugin |
| Thẻ agent | Component | Agent của provider đang chọn, cùng chất liệu `.thinMaterial`, bo góc 24pt và padding 24pt như thẻ provider | Có model, model của phiên, lỗi đọc file |
| Nút quay lại | Component | Trở về danh sách agent, glass dạng capsule cùng kiểu với bộ chọn provider | — |
| Bộ chọn provider | Component | Tab glass có logo và tên, canh trái ngay trên tên file | Đang chọn, không chọn |
| Viên lưu | Component | Glass nổi ở đáy, nơi duy nhất cho việc lưu | Chưa lưu, xung đột, lưu lỗi, lỗi kiểm tra |
| Trang Usage | Template | Các thẻ provider cạnh nhau | — |
| Trang Instructions | Template | File nằm thẳng trên trường màu | — |
| Trang Config | Template | Cấu hình của provider đang chọn | Điều khiển, File |
| Trang Agents | Template | Xem agent của provider đang chọn, chỉ đọc | Danh sách, Chi tiết |

Ưu tiên control SwiftUI có sẵn: `Button`, `Toggle`, `Picker`, `Slider`, `Menu`, `Stepper`, `ProgressView`,
`ContentUnavailableView`, `Label`. Lưới thẻ agent dùng `LazyVGrid`, nút dùng `Button`.

## 5. Layout

**Grid:** fluid, cột `adaptive`, không chia cột cố định.
**Ngoại lệ:** Lưới thẻ agent trên trang Agents dùng 2 cột `.flexible()`, cách nhau 16pt, giữ 2 cột cả ở cửa sổ tối thiểu 860×580.
**Base unit:** 4pt.
**Composition:** Trường màu tràn cửa sổ, thanh điều hướng giữa toolbar, nội dung canh giữa.
**Độ rộng tối đa:** 960pt cho nội dung, 720pt cho editor. Nội dung giữ cỡ cố định, không phóng theo cửa sổ.
**Điều hướng:** Mỗi tính năng là một mục trên thanh giữa toolbar, chia theo tính năng, không chia theo provider.
**Density:** một mức Default.

| Token | pt | Dùng cho |
|---|---|---|
| `xs` | 4 | Giữa icon và chữ |
| `sm` | 8 | Trong nhóm nhỏ |
| `md` | 12 | Padding trong card |
| `lg` | 16 | Giữa các card |
| `xl` | 24 | Giữa khối lớn, lề trang |
| `2xl` | 32 | Khoảng trống lớn, trạng thái rỗng |

Thẻ dùng padding `xl`. Bảng này áp dụng cho cửa sổ chính. Popover (rộng 340pt) và Settings (rộng 460pt)
giữ nguyên kích thước và khoảng cách hiện tại.

## 6. Depth

Không có shadow tự đặt. Thẻ dùng `.thinMaterial`, bo góc 24pt, control dùng mặc định của hệ thống.
Liquid Glass chỉ dùng cho lớp điều khiển nổi: toolbar, bộ chọn provider, nút Điều khiển / File, nút quay lại, viên lưu.
Không dùng cho thẻ hay vùng nội dung.

## 7. Do's and Don'ts

### Do
- Dùng semantic color và text style của hệ thống.
- Dùng SF Mono cho đường dẫn và nội dung file.
- Dùng `.monospacedDigit()` cho số thay đổi theo thời gian.
- Kèm icon hoặc chữ khi báo trạng thái.
- Theo light/dark, Dynamic Type và các tuỳ chọn trợ năng của hệ thống.

### Don't
- Không thêm `AccentColor`. Màu hex chỉ có ba màu provider.
- Không dùng accent cho trang trí hoặc thanh progress.
- Không tự viết control khi SwiftUI đã có.
- Không dịch tay traffic light, để toolbar của hệ thống canh.
- Không dùng `Spacer` để giãn nội dung theo cửa sổ.
- Không dùng `Form` kiểu Settings cho trang dữ liệu.
- Không đặt số spacing ngoài bảng trong cửa sổ chính.

## 8. Responsive

Không có breakpoint. Nội dung giữ cỡ cố định và canh giữa, chỉ trường màu tràn cửa sổ. Cửa sổ tối thiểu
860×580.

## 9. Agent Prompt Guide

- Đọc file này trước khi thêm hoặc sửa UI.
- Accent luôn là của hệ thống.
- Không thêm font, màu hay shadow riêng ngoài các mục đã ghi.
- Cửa sổ chính chỉ dùng spacing trong bảng ở mục 5.
- Mỗi tính năng là một mục trên thanh điều hướng, không nhét vào popover hay Settings.

## 10. Motion

Chỉ dùng animation mặc định của hệ thống, không có animation tự viết.

## 11. Voice & Tone

Ngắn, nói rõ việc, dùng từ của người dùng. Lỗi nói rõ chuyện gì xảy ra và cách xử lý.
Mọi chuỗi có bản en và vi trong `Localizable.xcstrings`.
