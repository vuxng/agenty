# Trang Config cho settings tầng user: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm trang Config / Cấu hình để xem và sửa `~/.claude/settings.json` và `~/.codex/config.toml`, gồm control cho Model, Quyền và sandbox, Plugin, cùng chế độ sửa toàn bộ file.

**Architecture:** `ConfigBackend` có hai bản: Claude tự sửa JSON giữ thứ tự key, Codex gọi `codex app-server` nên không phải tự xử lý TOML. `ConfigDocument` giữ nháp theo key và chỉ phụ thuộc protocol, nên test được bằng fake. Giao diện nằm trong `App/Views/Main/`, thêm một case vào `AppPage`.

**Tech Stack:** Swift 6, SwiftUI trên macOS 27, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-07-config-page-design.md`. Mọi giao diện theo `DESIGN.md`. Bảng giá trị và mô tả nằm ở mục 3.2 đến 3.5 của spec.

## Global Constraints

- Target macOS 27.0, `SWIFT_STRICT_CONCURRENCY: complete`, app không sandbox.
- Accent của hệ thống. Màu riêng chỉ có Claude `#D97857`, Codex `#6B6BF2`, và không dùng cho chữ hay nút.
- Liquid Glass chỉ cho toolbar, bộ chọn provider, nút Điều khiển / File, viên lưu. Thẻ dùng `.thinMaterial`, bo góc 24, padding 24.
- Nội dung rộng tối đa 960pt, editor 720pt, cửa sổ tối thiểu 860×580, không có breakpoint.
- Khoảng cách trong cửa sổ chính chỉ dùng token 4, 8, 12, 16, 24, 32.
- Không dùng `Form` kiểu Settings, không tự viết control khi SwiftUI đã có, không có animation tự viết.
- Mọi chuỗi có bản en và vi trong `App/Resources/Localizable.xcstrings`.
- Commit không có dòng Co-Authored-By Claude. PR không có footer Claude Code.
- Sau mỗi lần `xcodebuild`, chạy `git checkout -- Packages/UsageCore/Package.resolved` trước khi commit.
- Giữ kiểm chứng vừa đủ: test, build, xem nhanh. Không chạy app kiểm tra dài.
- Không bao giờ đụng cấu hình thật trong test hay khi kiểm tra. Khi mở app phải đặt cả `CFFIXED_USER_HOME` và `CODEX_HOME`: `CFFIXED_USER_HOME` không đổi `HOME` của tiến trình con, nên thiếu `CODEX_HOME` thì `codex app-server` ghi vào `~/.codex` thật.

**Lệnh dùng chung:**
- Test: `swift test --package-path Packages/UsageCore --filter <Suite>`
- Build: `xcodegen generate && xcodebuild -project Agenty.xcodeproj -scheme Agenty -configuration Debug -derivedDataPath build/DerivedData build`, kết quả phải có `** BUILD SUCCEEDED **`.

## Review Focus

1. Plugin id có dấu chấm: phần đó của key path phải đặt trong ngoặc kép, nếu không Codex ghi sai chỗ. Test ở Task 5.
2. `settings.json` thụt 4 dấu cách, CRLF hoặc không có newline cuối: lưu vẫn giữ mọi giá trị và thứ tự key, chỉ định dạng đổi về 2 dấu cách. Test ở Task 3.
3. `settings.json` rỗng 0 byte coi như chưa có key. Gốc không phải object thì báo file lỗi, không ghi đè. Test ở Task 4.
4. App được activate đúng lúc đang lưu: `refresh` không được chen vào làm mất nháp hay báo xung đột giả. Test ở Task 6.
5. Lỗi từ thư mục tạm: thông báo không được lộ đường dẫn tạm, và thư mục phải bị xoá cả khi lỗi. Test ở Task 5.

---

### Task 0: Tạo nhánh và commit tài liệu

**Files:**
- Add: `docs/superpowers/specs/2026-11-07-config-page-design.md`, `docs/superpowers/plans/2026-11-07-config-page.md`

- [ ] **Step 1: Tạo nhánh từ `next`**

Run: `git switch -c feat/config-page`

- [ ] **Step 2: Commit tài liệu**

```bash
git add docs/superpowers/specs/2026-11-07-config-page-design.md docs/superpowers/plans/2026-11-07-config-page.md
git commit -m "docs: add the Config page spec and plan"
```

---

### Task 1: Tách `TextFile` khỏi `InstructionsFile`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Infrastructure/TextFile.swift`
- Modify: `Packages/UsageCore/Sources/UsageCore/Instructions/InstructionsFile.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/TextFileTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum TextFileError: Error, Sendable, Equatable { case notText, readFailed(String), writeFailed(String) }
  public typealias InstructionsError = TextFileError
  public struct TextFile: Sendable {
      public let url: URL
      public init(url: URL)
      public func read() throws(TextFileError) -> String?   // nil khi file không tồn tại
      public func write(_ text: String) throws(TextFileError)
  }
  ```

- [ ] **Step 1: Viết test `@Suite struct TextFileTests`**

`missingFileReadsNil`, `writeCreatesParentDirectories` (file mới có quyền `0o600`), và `writeKeepsPermissions`: file có sẵn quyền `0o600` hoặc `0o644` giữ nguyên quyền sau `write`. Tạo file tạm quyền `0o600` trước khi ghi nội dung.

- [ ] **Step 2: Chạy `--filter TextFileTests`, mong đợi FAIL vì chưa có `TextFile`**

- [ ] **Step 3: Chuyển `read`, `write`, `resolvedWriteTarget`, `attributes`, `isMissingFile` sang `TextFile`**

`InstructionsFile` giữ `provider`, `url`, `fileName`, `displayPath`, `isOverridden`, và gọi qua một `TextFile`. Không sửa `InstructionsFileTests`.

- [ ] **Step 4: Chạy `--filter "TextFileTests|InstructionsFileTests|InstructionsDocumentTests"`, mong đợi PASS**

- [ ] **Step 5: Commit**

Message: `refactor: move safe file writes into TextFile`

---

### Task 2: `JSONRPCError` mang `data`, nới giới hạn dòng, tách phiên `app-server`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Providers/Codex/CodexAppServer.swift`
- Modify: `Infrastructure/JSONRPCClient.swift`, `Infrastructure/SubprocessRunner.swift:36`, `Providers/Codex/CodexProvider.swift:63-70,89`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/JSONRPCClientTests.swift`, `SubprocessRunnerTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum JSONRPCError { case server(code: Int, message: String, data: JSONValue? = nil); case closed }
  enum CodexAppServerError: Error { case cliNotFound }
  struct CodexAppServer: Sendable {
      let locator: CLILocator
      let pathOverride: @Sendable () -> String?
      let runner: any ProcessRunner
      let clientVersion: String
      let home: URL
      let timeout: Duration
      static func initialize(_ rpc: JSONRPCClient, version: String) async throws
      func withSession<R: Sendable>(environment: [String: String] = [:],
                                    _ body: @Sendable (JSONRPCClient) async throws -> R) async throws -> R
  }
  ```

- [ ] **Step 1: Viết test `serverErrorCarriesData` và `longLineArrivesWhole`**

`serverErrorCarriesData`: dòng trả về `{"id":1,"error":{"code":-32600,"message":"m","data":{"config_write_error_code":"configVersionConflict"}}}` phải ném `.server(code: -32600, message: "m", data: .object(["config_write_error_code": .string("configVersionConflict")]))`.

`longLineArrivesWhole` trong `SubprocessRunnerTests`: chạy `/bin/sh -c "head -c 300000 /dev/zero | tr '\\0' a; echo"`, `receive()` trả về một dòng đủ 300000 ký tự.

- [ ] **Step 2: Chạy `--filter "JSONRPCClientTests|SubprocessRunnerTests"`, mong đợi FAIL**

`longLineArrivesWhole` fail với `outputLimitExceeded`: `strings()` mặc định chặn ở 128 KiB, còn `plugin/installed` đã 59 KB một dòng.

- [ ] **Step 3: Thêm `data`, nới giới hạn dòng, viết `CodexAppServer`**

`SubprocessRunner` gọi `strings(bufferingPolicy: .maxLineLength(16 * 1024 * 1024))`.

`withSession` tìm `codex`, không thấy thì ném `.cliNotFound`. Chạy `runner.run` với arguments `["app-server"]`, environment gồm `PATH` từ `CodexProvider.searchPath` cộng `environment`, bọc `withTimeout(timeout)`, gọi `initialize`, chạy `body`, rồi `finishInput`. `initialize` gửi đúng `initialize` và `initialized` như `CodexProvider` hiện tại. `CodexProvider` gọi `CodexAppServer.initialize`, còn lại giữ nguyên.

- [ ] **Step 4: Chạy `--filter "JSONRPCClientTests|SubprocessRunnerTests|CodexProviderTests"`, mong đợi PASS**

- [ ] **Step 5: Commit**

Message: `refactor: share the Codex app-server handshake and allow long RPC lines`

---

### Task 3: `OrderedJSON`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Config/OrderedJSON.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/OrderedJSONTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum OrderedJSONError: Error, Sendable, Equatable { case invalid(line: Int, message: String) }
  public indirect enum OrderedJSON: Sendable, Equatable {
      public struct Member: Sendable, Equatable { public var key: String; public var value: OrderedJSON }
      case null, bool(Bool), number(String), string(String), array([OrderedJSON]), object([Member])
      public init(parsing text: String) throws(OrderedJSONError)
      public func serialized() -> String
      public func value(at path: [String]) -> OrderedJSON?
      public mutating func set(_ value: OrderedJSON, at path: [String])
      public mutating func remove(at path: [String])
  }
  ```

- [ ] **Step 1: Viết test `@Suite struct OrderedJSONTests`**

| Test | Khẳng định |
|---|---|
| `roundTripIsByteIdentical` | Với `{\n  "b": 1,\n  "a": {\n    "x": [\n      true,\n      null\n    ]\n  },\n  "e": {},\n  "f": []\n}\n`, `serialized()` trả về đúng chuỗi đó |
| `numbersStayVerbatim` | `1.0`, `1e3`, `400000` giữ nguyên chữ |
| `escapesMatchJSONStringify` | `"a\"b\n/é😀\u0001"` ra lại đúng `\"`, `\n`, `/`, `é`, `😀`, `\u0001` |
| `setKeepsOrderAndAppendsNewKeys` | Đổi `a` giữ nguyên vị trí, key mới nằm cuối |
| `setCreatesIntermediateObjects` | `set(.bool(true), at: ["p", "q"])` trên `{}` ra `{"p":{"q":true}}` |
| `removePrunesEmptyParents` | Xoá `["m","c","e"]` khỏi `{"m":{"c":{"e":1}},"k":1}` chỉ còn `k`. Nếu `c` còn key khác thì giữ `c` |
| `normalizesForeignFormatting` | Input 4 dấu cách, CRLF, không newline cuối: giá trị và thứ tự key giữ nguyên, `serialized()` thụt 2 dấu cách và kết thúc bằng `\n` |
| `invalidReportsLine` | `{\n  "a": ,\n}` ném `.invalid(line: 2, ...)` |

- [ ] **Step 2: Chạy `--filter OrderedJSONTests`, mong đợi FAIL**

- [ ] **Step 3: Viết parser đệ quy và `serialized()`**

Định dạng trùng `JSON.stringify(x, null, 2)` cộng `\n`: `"key": value`, object và mảng rỗng là `{}` và `[]`, chỉ escape `"`, `\`, ký tự điều khiển. Key trùng lặp: giữ vị trí đầu, lấy giá trị sau.

- [ ] **Step 4: Chạy `--filter OrderedJSONTests`, mong đợi PASS**

- [ ] **Step 5: Commit**

Message: `feat: add an order-preserving JSON document`

---

### Task 4: Kiểu dữ liệu Config và `ClaudeConfigBackend`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Config/AgentConfig.swift`, `Config/ConfigBackend.swift`, `Config/ClaudeConfigBackend.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/ClaudeConfigBackendTests.swift`, `Fixtures/claude-plugin-list.json`

**Interfaces:**
- Consumes: `TextFile` (Task 1), `OrderedJSON` (Task 3), `CLILocator`, `ProcessRunner`.
- Produces:
  ```swift
  public typealias ConfigPath = [String]
  public enum ConfigValue: Sendable, Hashable { case bool(Bool), string(String), opaque(String) }
  public struct ConfigEdit: Sendable, Equatable { public let path: ConfigPath; public let value: ConfigValue? } // nil = xoá key
  public enum ConfigChoiceKind: Sendable { case claudePermission, claudeSandbox, codexSandbox, codexApproval }
  public struct ConfigChoice: Sendable, Equatable {
      public let kind: ConfigChoiceKind; public let path: ConfigPath
      public let options: [ConfigValue?]            // nil = không đặt key, theo thứ tự hiển thị
      public let dangerous: Set<ConfigValue>
      public let unsetAliases: Set<ConfigValue>     // giá trị trong file hiển thị như nil
  }
  public struct ModelOption: Sendable, Equatable, Identifiable {
      public let id: String; public let displayName: String; public let isDefault: Bool
      public let efforts: [String]?; public let fastDescription: String? // nil = chưa biết, [] = không hỗ trợ mức nào
  }
  public struct ModelSetting: Sendable, Equatable { public let path: ConfigPath; public let options: [ModelOption]; public let allowsCustom: Bool }
  public struct EffortSetting: Sendable, Equatable {
      public let path: ConfigPath; public let modelName: String?   // nil = thanh chung
      public let levels: [String]?                                 // nil = lấy từ model đang chọn
  }
  public struct FastSetting: Sendable, Equatable {
      public let path: ConfigPath; public let onValue: ConfigValue; public let lockedValue: String?
      public let requiresModelTier: Bool   // true = ẩn khi model đang chọn không có fastDescription
  }
  public struct PluginItem: Sendable, Equatable, Identifiable {
      public let id: String; public let name: String; public let path: ConfigPath?  // nil = chỉ xem
      public let isEnabled: Bool
  }
  public struct AgentConfig: Sendable, Equatable {
      public var model: ModelSetting; public var efforts: [EffortSetting]; public var fast: FastSetting?
      public var choices: [ConfigChoice]; public var plugins: [PluginItem]; public var pluginsComplete: Bool
      public var values: [ConfigPath: ConfigValue]   // giá trị trên đĩa của mọi path ở trên, plugin lấy từ isEnabled
  }
  public struct ConfigSnapshot: Sendable, Equatable { public let config: AgentConfig; public let version: String? }
  public struct ConfigSaveResult: Sendable, Equatable { public let overrideMessage: String? }
  public enum ConfigValidation: Sendable, Equatable { case valid, unchecked }
  public enum ConfigError: Error, Sendable, Equatable {
      case cliNotFound, unsupportedCLI, conflict
      case invalidFile(String), invalidValue(String), readFailed(String), writeFailed(String)
  }
  public protocol ConfigBackend: Sendable {
      var provider: ProviderID { get }
      var file: TextFile { get }
      func load() async throws(ConfigError) -> ConfigSnapshot
      func save(_ edits: [ConfigEdit], version: String?) async throws(ConfigError) -> ConfigSaveResult
      func validate(_ text: String) async throws(ConfigError) -> ConfigValidation
      func writeFile(_ text: String) async throws(ConfigError)
  }
  extension ConfigBackend {
      public var displayPath: String { "~/.\(provider.rawValue)/\(file.url.lastPathComponent)" }
  }
  public struct ClaudeConfigBackend: ConfigBackend {
      public init(home: URL, locator: CLILocator, runner: any ProcessRunner, timeout: Duration = .seconds(15))
  }
  ```

Giá trị cố định của Claude:
- `file` là `<home>/.claude/settings.json`. Tìm CLI bằng `locate("claude", override: nil)`, vì app chỉ có đường dẫn tuỳ chỉnh cho Codex.
- `model.options`: `best`, `fable`, `opus`, `sonnet`, `haiku`, `opus[1m]`, `sonnet[1m]`, `opusplan`, `allowsCustom: true`, mọi option có `efforts: nil`. Giá trị trong file không có trong danh sách thì thêm vào cuối.
- Effort: mỗi mục `modelSettings.<m>` có `effortLevel` cho một `EffortSetting(modelName: m)`, rồi `EffortSetting(path: ["effortLevel"], modelName: nil)`. Levels `["low","medium","high","xhigh"]`.
- `fast`: path `["fastMode"]`, `onValue: .bool(true)`, `requiresModelTier: false`.
- Choice 1: `.claudePermission`, path `["permissions","defaultMode"]`, options theo bảng 3.3 của spec, `dangerous: [.string("bypassPermissions")]`, `unsetAliases: [.string("default"), .string("manual")]`.
- Choice 2: `.claudeSandbox`, path `["sandbox","enabled"]`, options `[nil, .bool(true), .bool(false)]`.
- Giá trị lạ trong file được thêm vào cuối `options`.

- [ ] **Step 1: Viết test `@Suite struct ClaudeConfigBackendTests`**

Dùng thư mục tạm, `FakeProcessRunner` và `ScriptedChannel(lines:)` trả về fixture `claude-plugin-list.json` gồm một plugin `scope: "user"` và một `scope: "synced"`.

| Test | Khẳng định |
|---|---|
| `missingFileLoadsDefaults` | Không có file: `version == nil`, `values` rỗng, không lỗi |
| `emptyFileLoadsDefaults` | File 0 byte: `values` rỗng, không lỗi |
| `nonObjectRootIsInvalid` | `[]` ném `.invalidFile` |
| `brokenJSONIsInvalid` | JSON lỗi ném `.invalidFile` có số dòng |
| `perModelEffortGetsItsOwnSetting` | `modelSettings.claude-opus-5-5.effortLevel = xhigh` cho hai `EffortSetting`, đúng path và `values` |
| `entryWithoutEffortHasNoSlider` | Mục `modelSettings` chỉ có `autoCompactWindow`: chỉ còn thanh chung |
| `customModelIsAppended` | `model = claude-opus-5-5` xuất hiện trong `model.options` |
| `unknownModeIsAppended` | `defaultMode = delegate` nằm trong `options`, `default` thì không |
| `syncedPluginsAreReadOnly` | Plugin `synced` có `path == nil`, plugin `user` có path `["enabledPlugins", id]` |
| `missingCLIFallsBackToFile` | Locator không thấy `claude`: plugin lấy từ `enabledPlugins`, `pluginsComplete == false` |
| `saveChangesOnlyEditedKeys` | Sửa `model`, xoá `effortLevel`: các key khác và thứ tự giữ nguyên, file kết thúc bằng `\n` |
| `saveDetectsConflict` | `version` khác nội dung đĩa ném `.conflict`, file không đổi |
| `saveCreatesMissingFile` | `version == nil`, file chưa có: tạo file |
| `validateRejectsBrokenJSON` | JSON lỗi, gốc không phải object, chuỗi rỗng hoặc chỉ có khoảng trắng ném `.invalidFile`. JSON object đúng trả về `.valid`; `load` vẫn chấp nhận file 0 byte |

- [ ] **Step 2: Chạy `--filter ClaudeConfigBackendTests`, mong đợi FAIL**

- [ ] **Step 3: Viết các kiểu và `ClaudeConfigBackend`**

`version` là nội dung file đã đọc. `save` đọc lại file, so với `version`, áp `edits`, ghi bằng `TextFile`. `ConfigValue` đổi sang `OrderedJSON.bool` hoặc `.string`. Giá trị object hoặc array đọc ra `.opaque`, và `.opaque` không bao giờ nằm trong edit vì chọn lại nó bằng giá trị trên đĩa. `TextFileError` đổi thành `.readFailed` khi đọc, `.writeFailed` khi ghi. Chạy `claude plugin list --json` với `PATH` từ `CodexProvider.searchPath`, đọc hết các dòng rồi parse. Mọi lỗi của bước này đều rơi về đọc từ `enabledPlugins`.

- [ ] **Step 4: Chạy `--filter ClaudeConfigBackendTests`, mong đợi PASS**

- [ ] **Step 5: Commit**

Message: `feat: read and edit Claude user settings`

---

### Task 5: `CodexConfigBackend`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Config/CodexConfigBackend.swift`
- Test: `CodexConfigBackendTests.swift`, `CodexConfigIntegrationTests.swift`, `Fixtures/codex-config-read.json`, `Fixtures/codex-model-list.json`, `Fixtures/codex-plugin-installed.json`

**Interfaces:**
- Consumes: `CodexAppServer` (Task 2), các kiểu của Task 4.
- Produces:
  ```swift
  public struct CodexConfigBackend: ConfigBackend {
      public init(locator: CLILocator, pathOverride: @escaping @Sendable () -> String?, runner: any ProcessRunner,
                  clientVersion: String, home: URL, codexHome: URL? = nil, timeout: Duration = .seconds(15))
  }
  ```
  `codexHome` khác nil thì đặt `CODEX_HOME`, chỉ dùng cho test tích hợp. `file` là `<codexHome hoặc home/.codex>/config.toml`.

Giá trị cố định:
- `load` chạy trong một phiên: `config/read` với `{"includeLayers": true}`, `model/list` với `{}`, `plugin/installed` với `{}`. Dùng `plugin/installed`, không dùng `plugin/list`.
- `model/list` có phân trang: còn `nextCursor` thì gọi tiếp với `{"cursor": nextCursor}`.
- Giá trị lấy từ `layers[]` có `name.type == "user"`: `config` và `version`.
- `ModelOption`: `id` là `model`, `displayName`, `isDefault`, `efforts` từ `supportedReasoningEfforts[].reasoningEffort`, `fastDescription` từ `serviceTiers[0].description`. `model.path` là `["model"]`, `allowsCustom: false`. Giá trị trong file không có trong danh sách thì thêm vào cuối với `efforts: nil` (chưa biết); danh sách hỗ trợ rỗng từ API vẫn là `[]`.
- `EffortSetting(path: ["model_reasoning_effort"], modelName: nil, levels: nil)`.
- `fast`: path `["service_tier"]`, `onValue: .string("priority")`, `requiresModelTier: true`. Giá trị khác `priority` và `default` thì đặt `lockedValue`.
- Choice: `.codexSandbox` path `["sandbox_mode"]`, `dangerous: [.string("danger-full-access")]`. `.codexApproval` path `["approval_policy"]`, `dangerous: [.string("never")]`. Options theo bảng 3.3. `approval_policy` là bảng thì đọc ra `.opaque("granular")` và thêm vào `options`.
- Plugin: `marketplaces[].plugins[]` có `installed == true`, path `["plugins", id, "enabled"]`, tên từ `interface.displayName`, không có thì lấy phần trước `@`.
- `save` gửi `config/batchWrite` với `{"edits":[{"keyPath","value","mergeStrategy":"replace"}],"expectedVersion":version}`. Xoá key thì `value` là `null`.
- Key path nối bằng `.`, phần nào chứa `.` thì bọc trong `"`.

**Đổi lỗi:**

| Lỗi nhận được | `ConfigError` |
|---|---|
| `CodexAppServerError.cliNotFound` | `.cliNotFound` |
| `data.config_write_error_code == "configVersionConflict"` | `.conflict` |
| `data.config_write_error_code == "configValidationError"` | `.invalidValue(message)` |
| `message` chứa `unknown variant` và không có `config_write_error_code` | `.unsupportedCLI` |
| Lỗi server khác khi `load` hoặc `validate` | `.invalidFile(message)` |
| Lỗi server khác khi `save` | `.writeFailed(message)` |
| Còn lại, gồm hết giờ và tiến trình thoát sớm | `.writeFailed(...)` khi `save`, `.readFailed(...)` khi `load` hoặc `validate` |

`validate` đổi `.cliNotFound` và `.unsupportedCLI` thành `.unchecked`, vì spec giữ chế độ File dùng được trong cả hai trường hợp.

- [ ] **Step 1: Lưu fixture từ giao thức thật**

Rút gọn từ phản hồi `app-server` trên một `CODEX_HOME` tạm, không lấy từ `~/.codex`. `codex-plugin-installed.json` có một plugin `installed: false` và một plugin thiếu `displayName`.

- [ ] **Step 2: Viết test `@Suite struct CodexConfigBackendTests`**

| Test | Khẳng định |
|---|---|
| `loadReadsUserLayerOnly` | Layer `system` có `model` khác: giá trị lấy từ layer `user`, `version` đúng |
| `loadMapsModelsAndEfforts` | `displayName`, `efforts`, `fastDescription` đúng |
| `modelListFollowsCursor` | Trang đầu có `nextCursor`: lời gọi sau gửi `cursor`, `options` gộp đủ hai trang |
| `unlistedModelIsAppended` | `model` trong file không có trong `model/list` vẫn nằm trong `options` |
| `loadKeepsOnlyInstalledPlugins` | Plugin chưa cài bị loại, plugin thiếu `displayName` lấy tên từ id |
| `granularApprovalIsOpaque` | `approval_policy` là bảng cho ra `.opaque("granular")` nằm trong `options` |
| `flexServiceTierLocksFast` | `service_tier = "flex"`: `lockedValue == "flex"`. `default` thì nil |
| `saveSendsBatchWithVersion` | Tham số gửi đi đúng, xoá key gửi `.null` |
| `pluginIdWithDotIsQuoted` | Path `["plugins","x.y@c","enabled"]` ra `plugins."x.y@c".enabled` |
| `versionConflictMapsToConflict` | Ném `.conflict` |
| `validationErrorMapsToInvalidValue` | Ném `.invalidValue` có message |
| `unknownMethodMapsToUnsupported` | `-32600` với `unknown variant` ném `.unsupportedCLI` |
| `overriddenStatusReturnsMessage` | `status: okOverridden` trả về `overriddenMetadata.message` |
| `missingCLIThrowsNotFound` | `load` ném `.cliNotFound` |
| `hangingServerTimesOut` | `ScriptedChannel.hangsWhenEmpty` với `timeout` ngắn: `load` ném `.readFailed`, `save` ném `.writeFailed` |
| `validateUsesTemporaryHome` | `environment["CODEX_HOME"]` có `config.toml` đúng nội dung và quyền `0o600` khi đang chạy |
| `validateCleansUpOnFailure` | Lỗi `.../config.toml:2:9: unclosed table` ra `config.toml:2:9: unclosed table`, thư mục tạm đã bị xoá |
| `validateWithoutCLIIsUnchecked` | Trả về `.unchecked` |
| `validateOnOldCodexIsUnchecked` | `config/read` trả về `-32600` với `unknown variant`: trả về `.unchecked` |

- [ ] **Step 3: Chạy `--filter CodexConfigBackendTests`, mong đợi FAIL**

- [ ] **Step 4: Viết `CodexConfigBackend`**

`validate` tạo thư mục quyền `0o700` trong `temporaryDirectory`, ghi `config.toml` quyền `0o600`, mở phiên với `CODEX_HOME` trỏ tới đó, gọi `config/read` với `{}`, bỏ đường dẫn thư mục tạm khỏi message, và xoá thư mục trong `defer`. `writeFile` dùng `TextFile`.

- [ ] **Step 5: Viết test tích hợp `CodexConfigIntegrationTests`**

Bật bằng `.enabled(if:)` khi có `codex` trên máy. Dùng `SubprocessRunner` thật và `codexHome` tạm chứa comment, `[desktop]`, `unknown_future_key`. Sau khi lưu một edit đặt `model` và một edit đặt `plugins.<id>.enabled`, file vẫn có comment, `[desktop]`, `unknown_future_key = 42`, và `model` mới.

- [ ] **Step 6: Chạy `--filter "CodexConfigBackendTests|CodexConfigIntegrationTests"`, mong đợi PASS**

- [ ] **Step 7: Commit**

Message: `feat: read and edit Codex user settings through app-server`

---

### Task 6: `ConfigDocument`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Config/ConfigDocument.swift`
- Test: `ConfigDocumentTests.swift`, `Support/FakeConfigBackend.swift`

**Interfaces:**
- Consumes: `ConfigBackend` và các kiểu của Task 4.
- Produces:
  ```swift
  public enum ConfigMode: Sendable { case controls, file }
  public enum ConfigNotice: Sendable, Equatable { case effortReset, fileNotChecked, overridden(String) }
  @Observable @MainActor public final class ConfigDocument {
      public let backend: any ConfigBackend
      public private(set) var mode: ConfigMode
      public private(set) var config: AgentConfig?
      public private(set) var edits: [ConfigEdit]
      public private(set) var diskText: String?      // từ backend.file.read(), có cả khi load lỗi
      public var fileDraft: String
      public private(set) var isLoading: Bool
      public private(set) var isSaving: Bool
      public private(set) var hasConflict: Bool
      public private(set) var loadError: ConfigError?
      public private(set) var saveError: ConfigError?
      public private(set) var notice: ConfigNotice?
      public var isDirty: Bool { get }
      public var dangerousEdits: [ConfigEdit] { get }
      public var currentModel: ModelOption? { get }  // model trong nháp, chưa đặt thì model isDefault
      public var isFastAvailable: Bool { get }
      public init(backend: any ConfigBackend)
      public func value(at path: ConfigPath) -> ConfigValue?
      public func set(_ value: ConfigValue?, at path: ConfigPath)
      public func selectModel(_ id: String?)
      public func levels(for setting: EffortSetting) -> [String]
      public func switchMode(to mode: ConfigMode) -> Bool      // false khi còn nháp
      public func refresh(force: Bool = false) async
      public func save() async
      public func revert()
      public func keepMine() async
      public func reload() async
  }
  ```

Quy tắc:
- `value(at:)` trả về giá trị trong nháp nếu path có edit, không thì giá trị trên đĩa.
- `set` thay edit cùng path. Giá trị bằng trên đĩa thì bỏ edit, nên chỉnh rồi chỉnh lại thì hết dirty. Với `ConfigChoice`, `nil` và các `unsetAliases` được coi là bằng nhau khi so.
- `isDirty`: chế độ Điều khiển là `!edits.isEmpty`, chế độ File là `fileDraft != (diskText ?? "")`.
- `dangerousEdits`: edit có giá trị nằm trong `dangerous` của một `ConfigChoice` và khác giá trị trên đĩa.
- `selectModel`: đặt `model.path`, rồi với từng `EffortSetting` có `levels == nil`: nếu `currentModel.efforts != nil` (kể cả `[]`) và không chứa mức hiện tại, thêm edit xoá key đó và đặt `notice = .effortReset`. Thanh có `levels` riêng, như của Claude, không bị đụng tới.
- `levels(for:)` dùng `setting.levels`, không có thì lấy `currentModel.efforts`, coi `nil` là danh sách rỗng. `value(at:)` không nằm trong danh sách thì thêm vào cuối, để giá trị lạ vẫn hiện và không bị đổi.
- `isFastAvailable`: có `config.fast`, và `requiresModelTier == false` hoặc `currentModel?.fastDescription != nil`.
- `refresh`: bỏ qua khi `isSaving` hoặc `isLoading`. Đọc `backend.file.read()`. Nội dung đổi khi có nháp thì đặt `hasConflict` và dừng. Nội dung đổi khi không có nháp, hoặc `force`, hoặc chưa tải lần nào, thì cập nhật `diskText`, `fileDraft` nếu không có nháp, rồi `backend.load()`. Còn lại thì dừng.
- `load` lỗi chỉ đặt `loadError`, giữ `config`, version và nháp cũ, cùng `diskText` và `fileDraft` để sửa ở chế độ File. Lần đầu tải lỗi vẫn chưa có `config`; lần tải thành công tiếp theo xoá `loadError` và cập nhật version. `isLoading` chỉ làm hiện vòng xoay khi `config == nil`.
- `save` chờ lần refresh đang chạy kết thúc (kể cả đọc lại sau lưu), không tắt nút Lưu vì refresh. Ở chế độ Điều khiển, nếu có `loadError` thì đặt `saveError` bằng lỗi đó, giữ nháp và không gọi backend; còn lại gọi `backend.save(edits, version:)`. `.conflict` đặt `hasConflict`. Lỗi khác đặt `saveError`, giữ nháp. Thành công thì xoá `edits`, `refresh(force: true)`, đặt `notice = .overridden` nếu có message.
- `save` ở chế độ File: đọc lại file, khác `diskText` thì đặt `hasConflict`. Rồi `backend.validate`, `writeFile`, `refresh(force: true)`. `.unchecked` đặt `notice = .fileNotChecked`.
- `revert`: xoá `edits`, `fileDraft = diskText ?? ""`.
- `keepMine`: đọc lại `diskText` và `load`, giữ nguyên `edits` và `fileDraft`, xoá `hasConflict`.
- `reload`: xoá `edits` và `hasConflict`, rồi `refresh(force: true)` với `fileDraft` lấy từ đĩa.
- `notice` bị xoá ở đầu `save`, `revert`, `reload`, `selectModel`.

- [ ] **Step 1: Viết `FakeConfigBackend` và test `@Suite @MainActor struct ConfigDocumentTests`**

`FakeConfigBackend` là actor-safe, ghi lại `saveCalls`, `writes`, `loadCount`, đổi được kết quả `load`, `save`, `validate`, và chặn được `save` bằng gate. `file` là một `TextFile` thật trong thư mục tạm, vì `refresh` đọc file đó.

| Test | Khẳng định |
|---|---|
| `refreshLoadsConfig` | `config` có giá trị, `loadError == nil` |
| `loadFailureIsReported` | `.invalidFile` nằm trong `loadError` |
| `brokenFileStillOpensInFileMode` | `load` lỗi: `fileDraft` vẫn là nội dung file, `switchMode(to: .file)` trả về `true`, sửa và lưu được |
| `editBackToDiskValueClearsDirty` | Bật rồi tắt lại: `isDirty == false` |
| `manualEqualsUnsetAlias` | Disk `default`, chọn `nil`: không có edit |
| `revertDropsEdits` | `edits` rỗng |
| `saveSendsOnlyEditsWithVersion` | Backend nhận đúng edit và version |
| `unknownValueIsNotEdited` | Disk `delegate`, đổi key khác: edit không chứa path của `delegate` |
| `saveFailureKeepsDraft` | `saveError` có giá trị, `edits` còn nguyên |
| `conflictOnSaveSetsFlag` | `hasConflict == true`, `edits` còn nguyên |
| `keepMineReappliesOnlyEdits` | Sau khi đĩa đổi key khác, `keepMine` rồi `save` chỉ gửi edit cũ với version mới |
| `keepMineInFileModeKeepsDraft` | `fileDraft` giữ nguyên, `save` ghi đúng bản nháp, không báo xung đột lại |
| `reloadDropsEdits` | `edits` rỗng, `hasConflict == false` |
| `externalChangeReloadsWhenClean` | `loadCount` tăng |
| `externalChangeConflictsWhenDirty` | `hasConflict == true` |
| `unchangedFileSkipsLoad` | `refresh()` lần hai không tăng `loadCount`, `refresh(force: true)` thì có |
| `refreshDuringSaveIsIgnored` | Chặn `save`, gọi `refresh()`, mở gate: không có `hasConflict`, không mất nháp |
| `dangerousEditsOnlyWhenNew` | Disk đã là `bypassPermissions`: rỗng. Đổi từ `plan` sang đó: có một edit |
| `modelChangeResetsUnsupportedEffort` | `ultra` với model không hỗ trợ: có edit xoá key, `notice == .effortReset` |
| `fixedLevelsSurviveModelChange` | `EffortSetting` có `levels` riêng: dù option có `efforts: []` hay `nil` như Claude, `selectModel` không xoá mức suy luận |
| `unknownEffortStaysInLevels` | Disk `turbo`: `levels(for:)` có `turbo`, sau `selectModel` sang model có `efforts: nil` (chưa biết) thì key không bị đụng |
| `fastHiddenWithoutModelTier` | `requiresModelTier` và model không có `fastDescription`: `isFastAvailable == false`. Claude thì `true` |
| `switchModeRefusesWhenDirty` | Trả về `false`, `mode` giữ nguyên |
| `fileSaveValidatesBeforeWriting` | Lỗi validate: `writes` rỗng, `saveError` có giá trị |
| `fileSaveWhenUncheckedWritesAndWarns` | `.unchecked`: có ghi, `notice == .fileNotChecked` |

- [ ] **Step 2: Chạy `--filter ConfigDocumentTests`, mong đợi FAIL**

- [ ] **Step 3: Viết `ConfigDocument` theo các quy tắc trên**

- [ ] **Step 4: Chạy `swift test --package-path Packages/UsageCore`, mong đợi toàn bộ PASS**

- [ ] **Step 5: Commit**

Message: `feat: add the Config draft document`

---

### Task 7: Khung trang và chế độ File

**Files:**
- Create: `App/Views/Main/ProviderSelector.swift`, `App/Views/Main/ConfigPage.swift`, `App/Views/Main/ConfigFileEditor.swift`
- Modify: `App/Views/Main/AppPage.swift`, `MainWindow.swift`, `InstructionsPage.swift`, `SaveCapsule.swift`, `App/AppModel.swift`, `AppCommands.swift`, `App/System/AppDelegate.swift`. `AmbientField` không cần sửa, trang mới tự nhận độ mạnh 0.45.

**Interfaces:**
- Consumes: `ConfigDocument` (Task 6), `ClaudeConfigBackend`, `CodexConfigBackend`.
- Produces:
  ```swift
  // AppModel
  var selectedProvider: ProviderID                 // đổi tên từ selectedInstructions, 11 chỗ
  let configs: [ProviderID: ConfigDocument]
  var pendingRiskySave: ProviderID?                // khác nil thì ConfigPage mở hộp xác nhận
  func requestConfigSave()                         // dangerousEdits rỗng thì lưu, không thì đặt pendingRiskySave
  // SaveCapsule.swift
  @MainActor protocol SaveCapsuleModel: AnyObject {
      var isDirty: Bool { get }
      var hasConflict: Bool { get }
      var saveFailureReason: String? { get }
      func save() async
      func revert()
      func keepMine() async
      func reload() async
  }
  struct SaveCapsule: View { let document: any SaveCapsuleModel; var onSave: (() -> Void)? = nil }
  // ProviderSelector.swift
  struct ProviderSelector: View { @Binding var selection: ProviderID }
  ```

- [ ] **Step 1: Đổi tên `selectedInstructions`, tách `ProviderSelector`, chuyển `SaveCapsule` sang protocol**

`InstructionsDocument` và `ConfigDocument` conform trong `SaveCapsule.swift`. Chuỗi lý do lỗi của `ConfigError` đặt ở đây. `onSave` khác nil thì nút Lưu gọi nó thay cho `save()`. Hành vi trang Instructions không đổi.

- [ ] **Step 2: Thêm `AppPage.config` và tạo document trong `AppModel`**

Title `Config`. Dùng chung `runner`, `locator`, `version` với `CodexProvider`.

- [ ] **Step 3: Viết `ConfigPage` với hàng đầu, chế độ File và các trạng thái lỗi**

- Hàng đầu: `ProviderSelector` bên trái, `Picker` kiểu `.segmented` Controls / File bên phải, bọc `.glassEffect`.
- Chuyển chế độ qua `switchMode(to:)`. Trả về `false` thì hiện dialog Save, Discard, Cancel. Save gọi `requestConfigSave()` rồi chỉ chuyển khi đã hết nháp. Discard gọi `revert()` rồi chuyển.
- `ConfigFileEditor` là `TextEditor` 13pt monospaced, `.scrollContentBackground(.hidden)`, tắt tự sửa chữ, rộng tối đa 720pt.
- Chế độ File có tên file 52pt, `backend.displayPath`, Show in Finder, "Applies to new sessions", dòng `notice`. `loadError == .cliNotFound` hoặc `notice == .fileNotChecked` thì hiện dòng báo chưa kiểm tra được.
- Chế độ Điều khiển tạm hiện các trạng thái: `ProgressView` khi tải, lỗi file kèm nút sang File, `.unsupportedCLI`, và `.cliNotFound` kèm nút Choose path…. Nút này dùng `ExecutablePicker.choose()`, ghi `SettingsKey.providerPath(.codex)`, rồi `refresh(force: true)`.
- Làm mới như `InstructionsPage`: `.onAppear` gọi `refresh(force: true)`, `.onChange(of: selectedProvider)` và `didBecomeActive` gọi `refresh()`. Đổi provider không gọi lại `app-server` khi file không đổi.

- [ ] **Step 4: Build, mong đợi `** BUILD SUCCEEDED **`**

- [ ] **Step 5: Chạy `swift test --package-path Packages/UsageCore`, mong đợi PASS**

- [ ] **Step 6: Commit**

Message: `feat: add the Config page shell with file editing`

---

### Task 8: Hero và các thẻ

**Files:**
- Create: `App/Views/Main/ConfigHero.swift`, `ConfigModelCard.swift`, `ConfigChoiceCard.swift`, `ConfigPluginCard.swift`, `ConfigText.swift`
- Modify: `App/Views/Main/ConfigPage.swift`, `App/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ConfigDocument`, `AgentConfig` và các kiểu đi kèm.
- Produces: `enum ConfigText { static func label(_ kind: ConfigChoiceKind, _ value: ConfigValue?) -> String; static func description(_ kind: ConfigChoiceKind, _ value: ConfigValue?) -> String? }`

- [ ] **Step 1: Viết `ConfigText` và thêm chuỗi vào `Localizable.xcstrings`**

Nhãn và mô tả tiếng Việt theo bảng 3.3 của spec, bản en dịch sát nghĩa. Giá trị kỹ thuật như `read-only` giữ nguyên ở cả hai ngôn ngữ. Giá trị lạ hiện nguyên văn, không có mô tả, `.opaque` hiện "Custom".

| en | vi |
|---|---|
| Config | Cấu hình |
| Controls | Điều khiển |
| Default | Mặc định |
| Not set | Chưa đặt |
| Other… | Khác… |
| Reasoning effort | Mức suy luận |
| Other models | Model khác |
| Permissions | Quyền |
| Approval | Phê duyệt |
| Plugins | Plugin |
| Search plugins | Tìm plugin |
| %lld of %lld on | %lld/%lld bật |
| Show all %lld | Xem tất cả %lld |
| Synced | Đồng bộ |
| On / Off | Bật / Tắt |
| Custom | Tuỳ chỉnh |
| Save a risky setting? | Lưu thiết lập rủi ro? |
| The agent could run commands without asking: %@ | Agent có thể chạy lệnh mà không hỏi: %@ |
| Save Anyway | Vẫn lưu |
| Save changes before switching? | Lưu thay đổi trước khi chuyển? |
| Reasoning effort went back to Default because this model doesn't support that level. | Mức suy luận đã về Mặc định vì model này không hỗ trợ mức đó. |
| Agenty can't check this file because it can't find the Codex CLI. | Agenty không kiểm tra được file này vì không tìm thấy CLI Codex. |
| Set to %@. Change it in File mode. | Đang đặt là %@. Sửa ở chế độ File. |
| Open File | Mở File |
| This version of Codex doesn't support editing settings yet. | Phiên bản Codex này chưa hỗ trợ sửa cấu hình. |
| Plugins from claude.ai are missing because Agenty can't find the Claude CLI. | Thiếu plugin từ claude.ai vì Agenty không tìm thấy CLI Claude. |

- [ ] **Step 2: Viết `ConfigHero`**

Nhãn Model `.headline .secondary`. Tên model 52pt thin rounded trong `Menu`, có dòng Default để xoá key. `allowsCustom` thì thêm Other…, mở `.alert` có `TextField`. Gọi `document.selectModel`. Dưới hero là đường dẫn, Show in Finder, "Applies to new sessions", rồi dòng cam nếu `notice` là `.overridden` hoặc `.effortReset`.

- [ ] **Step 3: Viết `ConfigModelCard`**

Mỗi `EffortSetting` là một `Slider` có `SliderTick` gắn nhãn, nấc đầu là Default và ứng với `nil`. Nhãn thanh: `modelName` nếu có, thanh chung là Other models khi có thanh theo model, ngược lại là Reasoning effort. `FastSetting` là `Toggle`, chỉ hiện khi `isFastAvailable`, off gọi `set(nil, at:)`, mô tả là `currentModel?.fastDescription`. `lockedValue` khác nil thì tắt toggle và hiện "Set to %@. Change it in File mode."

- [ ] **Step 4: Viết `ConfigChoiceCard`**

`Picker` kiểu `.radioGroup`. Mỗi lựa chọn có `.help` là mô tả. Lựa chọn đang chọn hiện mô tả bên dưới. Giá trị trong `dangerous` hiện chữ cam kèm `exclamationmark.triangle.fill`.

- [ ] **Step 5: Viết `ConfigPluginCard`**

Đếm số bật, ô tìm lọc theo tên, 8 dòng đầu, Show all mở rộng trong thẻ. `path == nil` hiện mờ với nhãn Synced, không có toggle. `pluginsComplete == false` hiện dòng báo.

- [ ] **Step 6: Ghép vào `ConfigPage`, thêm hộp xác nhận**

Hai `VStack` trong `ScrollView`: cột trái là thẻ Model và các thẻ quyền, cột phải là thẻ Plugin. Khi `isLoading && config == nil`, các thẻ vẫn giữ chỗ và hiện `ProgressView` bên trong.

`SaveCapsule(onSave: model.requestConfigSave)`. `pendingRiskySave` khác nil thì mở `.confirmationDialog` liệt kê các giá trị trong `dangerousEdits`, Save Anyway có `role: .destructive`, Cancel có `.keyboardShortcut(.defaultAction)`.

Thêm `#Preview` cho: Claude, Codex, đang tải, lỗi file, thiếu CLI, cảnh báo cam. Preview dùng một fake backend đặt ngay trong file preview.

- [ ] **Step 7: Build, mong đợi `** BUILD SUCCEEDED **`**

- [ ] **Step 8: Commit**

Message: `feat: add model, permission, and plugin controls to the Config page`

---

### Task 9: Lệnh menu, thoát app và tài liệu

**Files:**
- Modify: `App/Views/Main/AppCommands.swift`, `App/System/AppDelegate.swift`, `DESIGN.md`, `README.md`

- [ ] **Step 1: Sửa lệnh Save trong `AppCommands`**

Trang Config gọi `model.requestConfigSave()`, cùng đường với viên lưu nên có hộp xác nhận, và `disabled` theo `isDirty` của document đang chọn.

- [ ] **Step 2: Sửa `applicationShouldTerminate`**

Hộp thoại hiện khi Instructions hoặc Config có nháp, thông báo đổi thành "Your unsaved changes will be lost if you discard them."

Chọn Save: lưu Instructions đồng bộ như hiện tại. Nếu có nháp Config, trả về `.terminateLater`, lưu trong một `Task`, rồi gọi `NSApp.reply(toApplicationShouldTerminate:)`. Document có `dangerousEdits` thì không lưu nó: trả lời `false`, chuyển sang trang Config của provider đó, đặt `pendingRiskySave`. Document có `saveError`, `hasConflict` hoặc còn dirty sau khi lưu thì trả lời `false` và cũng chuyển sang trang đó.

- [ ] **Step 3: Cập nhật `DESIGN.md` theo mục 6 của spec**

Thêm vai trò "Tên model" vào bảng Typography. Thêm Thẻ cấu hình và Trang Config vào bảng Components. Viên lưu có thêm trạng thái lỗi kiểm tra. Nút Điều khiển / File nằm trong lớp glass.

- [ ] **Step 4: Thêm một đoạn về trang Config vào `README.md`**

- [ ] **Step 5: Build, mong đợi `** BUILD SUCCEEDED **`**

- [ ] **Step 6: Commit**

Message: `feat: save Config drafts from the menu and on quit`

---

### Task 10: Kiểm tra lần cuối

- [ ] **Step 1: Chạy toàn bộ test**

Run: `swift test --package-path Packages/UsageCore`
Mong đợi: PASS, gồm cả test tích hợp nếu máy có `codex`.

- [ ] **Step 2: Build Agenty Dev và mở với home tạm**

Tạo thư mục tạm có bản sao `.claude/settings.json` và `.codex/config.toml`, chỉ hai file này, không chép `auth.json` hay `.credentials.json`. Ghi lại `shasum` của hai file thật, rồi:

```bash
osascript -e 'quit app "Agenty Dev"'
open --env CFFIXED_USER_HOME=<temp> --env CODEX_HOME=<temp>/.codex "build/DerivedData/Build/Products/Debug/Agenty Dev.app"
```

Phải thoát bản đang chạy trước, vì `open` với app đang mở chỉ đưa nó lên trước và bỏ qua `--env`.

- [ ] **Step 3: Xem nhanh một lượt**

- Đổi một giá trị ở mỗi provider, lưu, xem `diff` file trong thư mục tạm.
- Chọn `Bypass` rồi Lưu: có hộp xác nhận, nút mặc định là Cancel.
- Chuyển sang File khi có nháp: có dialog.
- Xem cửa sổ 860×580 và cửa sổ rộng, light và dark.

- [ ] **Step 4: Dọn và kiểm tra**

So `shasum` của hai file thật với lúc đầu, mong đợi không đổi. Xoá thư mục tạm, vì nó có thể chứa secret trong `mcp_servers.*.env`.

Run: `git checkout -- Packages/UsageCore/Package.resolved && git status --short`
Mong đợi: không còn gì ngoài các commit của nhánh.
