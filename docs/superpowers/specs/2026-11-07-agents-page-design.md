# Agenty — trang Agents để xem agent tầng user của Claude, Codex và Grok

- **Ngày:** 2026-11-07
- **Trạng thái:** Đã duyệt
- **Repo:** github.com/vuxng/agenty
- **Dựa trên:** `DESIGN.md`, `docs/superpowers/specs/2026-11-06-app-shell-instructions-design.md`,
  `docs/superpowers/specs/2026-11-07-config-page-design.md`
- **Phiên bản đã kiểm tra:** Claude Code 2.1.319, Codex CLI 0.167.0, Grok 1.0.77
- **Mockup:** ảnh chụp prototype SwiftUI trong `.superpowers/brainstorm/81576-1794044787/content/`, bản cuối là
  `agents-detail-v4.html` (chỉ có trên máy, không commit)

## 1. Mục tiêu

Mỗi CLI giữ agent của người dùng trong một thư mục riêng, và muốn biết mình có agent nào, agent đó dùng model gì,
có hook hay prompt gì thì phải mở từng file. Spec này thêm trang **Agents / Agent** trên thanh giữa toolbar để
xem các agent đó. Đợt này chỉ xem, phần tạo và sửa làm sau.

**Thành công khi:**
- Mỗi tab provider liệt kê đúng các file agent mà CLI đó nạp từ thư mục user, kèm model của từng agent.
- Bấm vào một agent thì thấy mọi field có trong file, hook và prompt, không cần mở file.
- Trang trông như cùng một bộ với trang Instructions: cùng cột, cùng phần đầu trang, cùng chất liệu.
- File hỏng hay YAML không chuẩn vẫn hiện được, kèm lời báo, không làm hỏng cả trang.
- Agenty không ghi gì vào thư mục agent.

## 2. Phạm vi

### Trong phạm vi
- Thư mục user: `~/.claude/agents/`, `~/.codex/agents/`, `~/.grok/agents/`.
- Danh sách và trang chi tiết, chỉ xem.
- Chuỗi en và vi trong `Localizable.xcstrings`, cập nhật `DESIGN.md` và README.

### Ngoài phạm vi
- Tạo, sửa, xoá, nhân bản, bật tắt agent. Kết quả thử đường ghi đã có, dùng cho đợt sau.
- Tầng project (`.claude/agents/`, `.codex/agents/`, `.grok/agents/` trong repo), agent có sẵn của CLI, agent
  của plugin.
- Agent Codex khai báo trong bảng `[agents.<tên>]` của `~/.codex/config.toml`.
- Agent Grok mượn từ Cursor.
- Kiểm tra agent có hợp lệ với từng CLI không, ví dụ thiếu `description`. Trang chỉ hiện những gì có trong file.
- Báo tên trùng. Hai file cùng `name` thì hiện cả hai.
- Tìm kiếm, lọc, theo dõi file thay đổi theo thời gian thực.
- `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, cùng lý do với các spec trước: app chạy từ GUI chỉ dùng đường dẫn mặc định.
- Bump version và phát hành, làm riêng sau khi merge.

## 3. Thiết kế giao diện

### 3.1 Bố cục chung

Trang theo khuôn trang Instructions: cột rộng tối đa 720pt, lề ngang 24pt, lề trên 16pt, canh giữa. Phần đầu
trang nằm thẳng trên trường màu, giống hệt Instructions. Phần đầu trang đứng yên, phần dưới cuộn.

| Vùng | Thành phần | Ghi chú |
|---|---|---|
| Thanh giữa toolbar | Mục Agents / Agent | Thứ tự: Usage, Instructions, Agents, Config |
| Đầu trang, danh sách | Bộ chọn provider có cả Claude, Codex, Grok; tiêu đề "6 agents" 52pt; đường dẫn thư mục và nút Hiện trong Finder | Không có dòng "Áp dụng cho phiên mới", vì trang không sửa gì |
| Đầu trang, chi tiết | Nút quay lại "‹ 6 agents"; tên agent 52pt; đường dẫn file và nút Hiện trong Finder | Nút quay lại nằm đúng chỗ bộ chọn, cùng kiểu glass |
| Nội dung | Lưới thẻ hoặc trang chi tiết | Mục 3.2 và 3.3 |
| Nền | `AmbientField` của provider đang chọn, độ mạnh 0.45 | Grok dùng màu xám đã có trong `ProviderStyle` |

Tiêu đề số agent dùng plural của `Localizable.xcstrings`: "1 agent", "6 agents", tiếng Việt "6 agent".

Không có breakpoint. Cửa sổ tối thiểu 860×580 vẫn giữ hai cột thẻ.

### 3.2 Danh sách

- **Thẻ agent:** cùng chất liệu với thẻ provider: `.thinMaterial`, bo góc 24pt, padding 24pt. Lưới hai cột,
  cách nhau 16pt.
  - Hàng đầu: tên agent `.title3` semibold, bên phải là badge model (`.caption` medium trên nền `.fill.secondary`
    hình viên thuốc, như badge gói trên thẻ Usage).
  - Dưới đó là `description`, `.caption` `.secondary`, tối đa 2 dòng và luôn giữ chỗ 2 dòng để các thẻ cao bằng
    nhau. Không có `description` thì ghi "No description" bằng `.tertiary`.
  - Không có dòng thống kê nào khác. Người dùng thấy dòng Prompt và Hooks vô nghĩa nên đã bỏ.
- **Badge model:** luôn hiện.
  - File có `model` khác `inherit`: hiện nguyên giá trị, ví dụ `sonnet`, `claude-opus-5-5`, `gpt-5.5`.
  - Không có `model`, hoặc ghi `inherit`: hiện "Session model", chữ `.secondary`. Lúc đó CLI dùng model của phiên
    đang chạy agent (với Claude còn có `CLAUDE_CODE_SUBAGENT_MODEL`), nên Agenty không đoán một tên cụ thể.
- **Thứ tự:** theo `name`, dùng `localizedStandardCompare`.
- **Bấm thẻ:** mở trang chi tiết.
- **Tab Grok:** Grok mặc định nạp cả agent trong `~/.claude/agents/`. Khi thư mục đó có ít nhất một agent ở cấp
  trên cùng, dưới đường dẫn có thêm một dòng `Label` icon `info.circle`, `.callout` `.secondary`: "Grok also uses
  the agents in ~/.claude/agents." Tab Grok vẫn chỉ liệt kê file trong `~/.grok/agents/`, theo lựa chọn của người
  dùng.

### 3.3 Trang chi tiết

Thứ tự từ trên xuống, cách nhau 16pt:

1. **Dòng cảnh báo** nếu file được đọc theo dòng (mục 4.2): `Label` cam, icon
   `exclamationmark.triangle.fill`, như dòng báo `AGENTS.override.md` của Instructions.
2. **Mô tả:** `description`, `.body`, nằm thẳng trên trường màu.
3. **Thẻ field:** dòng đầu luôn là `model`, giá trị theo đúng luật của badge. Sau đó là mọi field đơn khác có
   trong file, theo thứ tự trong file. Tên field giữ nguyên như trong file, ví dụ `permissionMode`. Mỗi dòng là tên
   `.body` bên trái, giá trị `.body` semibold bên phải.
4. **Thẻ code:** mỗi field lồng nhau một thẻ, ví dụ `hooks`, `mcpServers`, `features`. Tiêu đề là tên field
   `.title3` semibold, nội dung 13pt monospaced, chọn và copy được.
5. **Prompt:** thân file `.md`, hoặc `developer_instructions` của Codex. Nằm thẳng trên trường màu, cùng cách hiển
   thị với editor của Instructions: 13pt monospaced, heading đậm và lớn hơn, dấu Markdown tô màu provider. Chỉ đọc,
   chọn và copy được. Không có prompt thì bỏ phần này.

Field nào được tính là field đơn hay lồng nhau xem mục 4.2 và 4.3. `name` và `description` không lặp lại trong thẻ
field vì đã ở tiêu đề và mô tả.

### 3.4 Hành vi và trạng thái

| Tình huống | Hành vi |
|---|---|
| Đang tải | `ProgressView` ở chỗ lưới thẻ, phần đầu trang giữ nguyên |
| Thư mục chưa có | Tiêu đề "0 agents", đường dẫn không có nút Finder. Khối báo giống khối lỗi của Instructions: icon `doc.badge.ellipsis`, "This folder doesn't exist yet, so Codex has no agents of yours." |
| Thư mục rỗng | Như trên, câu là "Codex has no agents of yours in this folder." |
| File không có frontmatter hoặc không có `name` | Ẩn. Claude coi những file này là tài liệu |
| YAML không chuẩn | Vẫn hiện, đọc theo dòng, có dòng cảnh báo ở trang chi tiết |
| File không đọc được (TOML hỏng, không phải UTF-8, lỗi quyền) | Thẻ lấy tên file bỏ đuôi làm tên, không có badge, chỗ mô tả là lý do bằng `.orange`. Trang chi tiết là khối lỗi của Instructions: "Agenty can't read this file: …" và nút Hiện trong Finder |
| Không tìm thấy CLI Codex | Tab Codex hiện khối báo cùng kiểu: lý do và nút Chọn đường dẫn… như trang Config. Tab Claude và Grok không cần CLI |
| Lỗi khi chạy `codex app-server` | Khối báo nêu lý do, kèm nút Thử lại |
| Agent đang mở bị xoá hoặc đổi tên | Lần làm mới sau thì quay về danh sách |

**Làm mới:** khi trang xuất hiện, khi đổi provider và khi app được activate, như Instructions. Không theo dõi file.

**Điều hướng:** đổi provider hoặc rời trang thì về danh sách. Nút quay lại và phím Esc đưa về danh sách.

**Provider đang chọn:** dùng chung `selectedProvider` với Instructions và Config. Hai trang đó không có Grok, nên
khi đang chọn Grok mà sang Instructions hoặc Config thì lựa chọn chuyển về Claude.

## 4. Kiến trúc

Logic đặt trong `UsageCore` vì target app không có test, cùng lý do với các spec trước.

### 4.1 Các unit

| Unit | Vị trí | Trách nhiệm |
|---|---|---|
| `AgentDefinition`, `AgentField` | `UsageCore/Agents/` | Dữ liệu thuần: provider, URL, tên, mô tả, model, các field theo thứ tự, prompt, lỗi đọc, cờ đọc theo dòng. `AgentField` có giá trị `.text(String)` hoặc `.block(String)` |
| `MarkdownAgentParser` | `UsageCore/Agents/` | Hàm thuần: text của một file `.md` → `AgentDefinition?`. Dùng Yams, hỏng thì đọc theo dòng |
| `AgentDirectory` | `UsageCore/Agents/` | Tìm file trong thư mục: đuôi, có quét thư mục con không, thư mục có tồn tại không |
| `AgentSource` | `UsageCore/Agents/` | Protocol `load() async throws(AgentLoadError) -> AgentListing`. `AgentListing` gồm thư mục có tồn tại không, danh sách agent, và cờ "Grok cũng dùng agent của Claude" |
| `MarkdownAgentSource` | `UsageCore/Agents/` | Cho Claude và Grok: `AgentDirectory` cộng `MarkdownAgentParser` |
| `CodexAgentSource` | `UsageCore/Agents/` | Đọc `.toml` qua `codex app-server`, mục 4.3 |
| `AgentsDocument` | `UsageCore/Agents/` | `@Observable`: đang tải, listing, lỗi, `refresh()`. Chỉ phụ thuộc `AgentSource` |
| `AgentsPage`, `AgentCard`, `AgentDetail` | `App/Views/Main/` | Giao diện |
| `PageHeader` | `App/Views/Main/` | Tách từ `InstructionsPage`: ô trên cùng (bộ chọn hoặc nút quay lại), tiêu đề 52pt, hàng đường dẫn. Instructions và Agents dùng chung để hai trang không lệch nhau |
| `MarkdownStyler` | `App/Views/Main/` | Tách phần tô Markdown từ `InstructionsEditor` thành hàm dùng chung. Editor và prompt chỉ đọc cùng gọi nó |
| `ProviderSelector` | `App/Views/Main/` | Thêm tham số `providers`, mặc định là `ProviderID.configurable` |

`AppModel` giữ một `AgentsDocument` cho mỗi provider. `AppPage` thêm `agents`. `AppCommands` coi trang Agents là
không có gì chưa lưu.

### 4.2 Claude và Grok

| | Claude | Grok |
|---|---|---|
| Thư mục | `~/.claude/agents/` | `~/.grok/agents/` |
| File | `*.md` | `*.md` |
| Thư mục con | Quét, theo tài liệu Claude Code | Không quét. Đã thử bằng home tạm với `grok inspect --json`: file trong thư mục con không được nạp |

Grok mặc định nạp cả `~/.claude/agents/*.md` ở cấp trên cùng, và file trong `~/.grok/agents/` thắng khi trùng tên.
Đã thử bằng home tạm. `MarkdownAgentSource` của Grok bật cờ ở mục 3.2 khi thư mục đó có ít nhất một file `.md`.

**Đọc file:**
- Frontmatter nằm giữa dòng `---` đầu file và dòng `---` kế tiếp. Không có thì ẩn file.
- Parse bằng Yams 6.2.2 (MIT, thêm vào `Package.swift` của `UsageCore`), dùng `Node` để giữ thứ tự key.
- Giá trị đơn hiện nguyên chuỗi gốc trong file, nên `yes` vẫn là `yes`, không thành `true`.
- Chuỗi có xuống dòng, mapping, hoặc sequence có phần tử không đơn là field lồng nhau. Sequence chỉ gồm giá trị đơn
  hiện thành một dòng, nối bằng ", ".
- Nội dung thẻ code là đoạn text gốc trong file: các dòng dưới dòng key, cho tới key cấp trên cùng tiếp theo, bỏ
  phần thụt lề chung. Viết kiểu một dòng như `tools: [Read, Grep]` thì lấy phần sau dấu `:`.
- Thân file sau frontmatter, bỏ dòng trống ở đầu, là prompt. Rỗng thì coi như không có.

**Đọc theo dòng** khi Yams báo lỗi, ví dụ `description` có `: ` mà không có ngoặc. Đã gặp ở 2 trong 94 file agent
trên máy. Mỗi dòng không thụt lề có dạng `key: value` là một key. Có giá trị trên cùng dòng thì là field đơn, bỏ
ngoặc kép hoặc ngoặc đơn bao ngoài. Không có thì các dòng thụt lề phía dưới là thẻ code. Agent đọc kiểu này có cờ
`lineScanned` để trang chi tiết hiện cảnh báo.

### 4.3 Codex

- **Thư mục:** `~/.codex/agents/`, quét cả thư mục con, lấy `*.toml`. Giống `collect_agent_role_files` trong mã
  nguồn Codex.
- **Đọc:** dùng lại `CodexAppServer` của trang Config, một phiên cho cả thư mục. Tạo thư mục tạm quyền 0700, với
  từng file thì chép thành `config.toml` quyền 0600 rồi gọi `config/read` với `includeLayers: true`, lấy `config`
  của layer `user`. Xong thì xoá thư mục tạm, kể cả khi lỗi. Đã thử: một phiên đọc lại được file vừa đổi, mỗi phiên
  khởi động khoảng 0,07 giây, 10 phiên mới mất 0,66 giây.
- **Map giá trị:** `name`, `description`, `model` như trên. `developer_instructions` là prompt. Chuỗi, số, bool là
  field đơn. Object và array là thẻ code, hiện JSON thụt 2 dấu cách, vì `config/read` trả về JSON và không còn text
  gốc. Thứ tự field theo thứ tự `config/read` trả về.
- **Lỗi một file:** `config/read` báo lỗi TOML kèm dòng và cột. Lỗi đó thuộc về file, không làm hỏng cả listing.
  Đường dẫn thư mục tạm được bỏ khỏi thông báo, như `CodexConfigBackend.sanitized`.
- **Không có `name`:** ẩn, như Claude.
- **Lỗi cả tab:** không tìm thấy CLI, hoặc `app-server` không chạy được.

### 4.4 Rủi ro

- **Đọc agent Codex bằng home tạm là mượn tính năng ngoài mục đích của nó.** Nếu Codex sau này kiểm tra
  `config.toml` chặt hơn, key riêng của agent như `developer_instructions` có thể bị báo lỗi. Test tích hợp ở mục 5
  báo sớm. Phương án dự phòng là một thư viện TOML.
- **Hành vi của Grok mới chỉ thử trên 1.0.77** và không có tài liệu. Dòng báo ở tab Grok sai nếu người dùng tắt
  chế độ tương thích Claude của Grok, vì Agenty không đọc cài đặt đó.
- **Đọc theo dòng chỉ là gần đúng.** Đủ cho các file đã gặp, không hiểu hết YAML.
- **Thư mục tạm chứa bản sao file agent.** Phải giới hạn quyền và luôn xoá.

## 5. Kiểm thử

Unit test trong `UsageCoreTests`, chạy cả trên CI:

- **`MarkdownAgentParser`:** file có `hooks` như agent thật trên máy; file có `model`, `tools`, `permissionMode` và
  prompt Markdown; `model: inherit`; giá trị `yes` và `123` giữ nguyên chuỗi; `description` dạng `>` nhiều dòng;
  sequence một dòng; YAML có `: ` không ngoặc thì đọc theo dòng và có cờ; không có frontmatter hoặc không có `name`
  thì trả về nil; thân rỗng thì không có prompt; dòng kết thúc CRLF.
- **`AgentDirectory`:** quét thư mục con khi bật, không quét khi tắt, bỏ qua đuôi khác, thư mục chưa có.
- **`MarkdownAgentSource`:** cờ của Grok bật khi `~/.claude/agents` có file `.md` ở cấp trên cùng, tắt khi không có.
  File không đọc được thành agent có lỗi, không làm hỏng listing.
- **`CodexAgentSource`:** fake channel với dữ liệu lấy từ giao thức thật: map field, prompt, JSON cho object, lỗi
  TOML của một file, thiếu CLI. Thư mục tạm bị xoá sau khi đọc, kể cả khi lỗi.
- **`AgentsDocument`:** đang tải, listing, lỗi, làm mới.

Một test tích hợp với `codex` thật, bỏ qua khi máy không có CLI: đọc một file agent có `developer_instructions`,
bảng `[features]` và key lạ qua `CodexAgentSource`, rồi so kết quả.

Không viết test tự động cho SwiftUI, có `#Preview` cho các trạng thái chính: danh sách, thư mục chưa có, thiếu CLI,
chi tiết có prompt, chi tiết có cảnh báo đọc theo dòng, file không đọc được.

Kiểm tra bằng mắt một lần trên bản Agenty Dev: ba tab, một trang chi tiết, cửa sổ tối thiểu, light và dark.

## 6. Cập nhật `DESIGN.md`

- **Color Palette:** thêm Provider Grok `#9AA0A6`, dùng cho trường màu. Sửa câu "Màu hex chỉ có hai màu provider"
  thành ba màu.
- **Typography:** vai trò "Tên file" đổi thành "Tiêu đề trang", 52pt, thin, rounded, dùng cho tên file
  (Instructions), số agent và tên agent (Agents). Vai trò "Tên provider" đổi thành "Tiêu đề thẻ", dùng cho cả tên
  agent trên thẻ.
- **Components:** thêm Thẻ agent, cùng chất liệu với thẻ provider. Thêm Nút quay lại, glass, cùng kiểu với bộ chọn
  provider. Thêm Trang Agents vào nhóm Template, biến thể Danh sách và Chi tiết.
- **Depth:** thêm nút quay lại vào danh sách lớp điều khiển dùng Liquid Glass.
- **Không có control tự viết.** Lưới thẻ là `LazyVGrid`, nút là `Button`.
