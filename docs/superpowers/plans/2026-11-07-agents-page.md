# Trang Agents chỉ xem: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm trang Agents / Agent để xem agent tầng user của Claude, Codex và Grok: danh sách thẻ và trang chi tiết, không ghi gì vào thư mục agent.

**Architecture:** Logic nằm trong `UsageCore/Agents/`. `MarkdownAgentParser` đọc file `.md` bằng Yams, hỏng thì đọc theo dòng. `CodexAgentSource` đọc `.toml` qua `codex app-server` trong một `CODEX_HOME` tạm. `AgentsDocument` giữ trạng thái và chỉ phụ thuộc protocol `AgentSource`, nên test được bằng fake. Giao diện nằm trong `App/Views/Main/`, dùng chung phần đầu trang với Instructions.

**Tech Stack:** Swift 6, SwiftUI trên macOS 27, Swift Testing, Yams 6.2.2, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-07-agents-page-design.md`. Mọi giao diện theo `DESIGN.md`. Bố cục và trạng thái nằm ở mục 3, cách đọc file ở mục 4.2 và 4.3 của spec.

## Global Constraints

- Target macOS 27.0, `SWIFT_STRICT_CONCURRENCY: complete`, app không sandbox.
- Agenty không ghi gì vào `~/.claude/agents/`, `~/.codex/agents/`, `~/.grok/agents/`.
- Cột rộng tối đa 720pt, lề ngang 24pt, lề trên 16pt, canh giữa. Phần đầu trang giống hệt Instructions.
- Thẻ: `.thinMaterial`, bo góc 24, padding 24. Lưới 2 cột, cách nhau 16. Tên agent `.title3` semibold. Badge `.caption` medium trên `.fill.secondary` hình capsule. Mô tả `.caption` `.secondary`, 2 dòng, luôn giữ chỗ 2 dòng.
- Tiêu đề trang 52pt, thin, rounded. Hàng field `.body`, giá trị `.body` semibold. Code và prompt 13pt monospaced.
- Liquid Glass chỉ cho toolbar, bộ chọn provider, nút quay lại, viên lưu.
- Thứ tự toolbar: Usage, Instructions, Agents, Config.
- Khoảng cách trong cửa sổ chính chỉ dùng token 4, 8, 12, 16, 24, 32. Không tự viết control, không có animation tự viết.
- Mọi chuỗi có bản en và vi trong `App/Resources/Localizable.xcstrings`.
- Test chỉ dùng thư mục tạm, không bao giờ đọc hay ghi cấu hình thật.
- Commit không có dòng Co-Authored-By Claude. PR không có footer Claude Code.
- Sau mỗi lần `xcodebuild`, chạy `git checkout -- Packages/UsageCore/Package.resolved` nếu diff chỉ là pin Sparkle hoặc dòng `originHash`. Pin Yams ở Task 0 thì giữ.
- Giữ kiểm chứng vừa đủ: test, build, xem nhanh.

**Lệnh dùng chung:**
- Test: `swift test --package-path Packages/UsageCore --filter <Suite>`
- Build: `xcodegen generate && xcodebuild -project Agenty.xcodeproj -scheme Agenty -configuration Debug -derivedDataPath build/DerivedData build`, kết quả phải có `** BUILD SUCCEEDED **`. Sandbox Codex không chạy được `xcodebuild`, nên controller build.

## Review Focus

1. File agent hoặc cả thư mục `agents` là symlink, kiểu dotfiles: vẫn được liệt kê như file thường. Test ở Task 2.
2. File có BOM UTF-8 hoặc xuống dòng CRLF: frontmatter vẫn được nhận. Test ở Task 1.
3. Hai file cùng `name`, ví dụ một file trong thư mục con: cả hai đều hiện và không đè nhau, vì định danh là URL. Test ở Task 2.
4. Một file Codex làm `config/read` báo lỗi (TOML hỏng, sai kiểu) nằm trước các file tốt: các file sau vẫn đọc được trong cùng phiên, và lời báo nêu tên file agent, không lộ đường dẫn tạm. Đã thử với Codex 0.167.0: phiên vẫn chạy tiếp sau lỗi. Test ở Task 3.
5. Thư mục có file không phải agent: `README.md` không có frontmatter, `notes.txt`, `.DS_Store`: bỏ qua, không lỗi. Test ở Task 2.

---

### Task 0: Chuẩn bị (controller làm)

Sandbox Codex không có mạng, nên controller thêm Yams và resolve trước khi giao việc.

**Files:**
- Modify: `Packages/UsageCore/Package.swift`, `Packages/UsageCore/Package.resolved`
- Add: `docs/superpowers/plans/2026-11-07-agents-page.md`, spec đã đổi trạng thái

- [ ] **Step 1: Thêm Yams vào `UsageCore`**

Thêm `.package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")` vào `dependencies`, và
`.product(name: "Yams", package: "Yams")` vào dependency của target `UsageCore`.

- [ ] **Step 2: Resolve và chạy toàn bộ test**

Run: `swift package --package-path Packages/UsageCore resolve && swift test --package-path Packages/UsageCore`
Expected: mọi test pass, `Package.resolved` có pin Yams.

- [ ] **Step 3: Commit**

```bash
git add Packages/UsageCore/Package.swift Packages/UsageCore/Package.resolved docs/superpowers/specs/2026-11-07-agents-page-design.md docs/superpowers/plans/2026-11-07-agents-page.md
git commit -m "chore: add Yams and the Agents page plan"
```

---

### Task 1: Kiểu dữ liệu agent và `MarkdownAgentParser`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Agents/AgentDefinition.swift`
- Create: `Packages/UsageCore/Sources/UsageCore/Agents/MarkdownAgentParser.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/MarkdownAgentParserTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum AgentFieldValue: Sendable, Equatable {
      case text(String)    // một dòng, hiện trong thẻ field
      case block(String)   // lồng nhau hoặc nhiều dòng, hiện trong thẻ code
  }
  public struct AgentField: Sendable, Equatable {
      public let key: String
      public let value: AgentFieldValue
      public init(key: String, value: AgentFieldValue)
  }
  public enum AgentReadError: Sendable, Equatable { case notText, failed(String) }
  public struct AgentDefinition: Sendable, Equatable, Identifiable {
      public var id: URL { url }
      public let url: URL
      public let name: String
      public let description: String?
      public let model: String?        // nil khi thiếu hoặc là "inherit", tức Session model
      public let fields: [AgentField]  // theo thứ tự trong file, không có name, description, model và key prompt
      public let prompt: String?
      public let readError: AgentReadError?
      public let isLineScanned: Bool
      public init(url: URL, name: String, description: String?, model: String?, fields: [AgentField],
                  prompt: String?, readError: AgentReadError? = nil, isLineScanned: Bool = false)
      /// File không đọc được: tên là tên file bỏ đuôi, các trường khác rỗng.
      public static func unreadable(url: URL, error: AgentReadError) -> AgentDefinition
  }
  public enum MarkdownAgentParser {
      /// nil khi không có frontmatter hoặc `name` rỗng.
      public static func parse(_ text: String, url: URL) -> AgentDefinition?
  }
  ```

- [ ] **Step 1: Viết test `@Suite struct MarkdownAgentParserTests`**

Mỗi test gọi `MarkdownAgentParser.parse(text, url: URL(filePath: "/tmp/a.md"))`.

```swift
@Test func parsesProjectAgentWithHooks()
// Text là nguyên file agenty.md thật (name, description, hooks SessionStart như trong spec mục 3.3).
// #expect name == "agenty", model == nil, prompt == nil, isLineScanned == false
// #expect fields == [AgentField(key: "hooks", value: .block("SessionStart:\n  - hooks:\n      - type: command\n        command: jq -n --arg t agenty ..."))]
//   (block là các dòng dưới `hooks:`, bỏ 2 dấu cách thụt lề chung)

@Test func keepsFileOrderAndRawScalars()
// "---\nname: reviewer\ndescription: Reviews code\nmodel: sonnet\ntools: [Read, Grep]\nbackground: yes\nmaxTurns: 123\npermissionMode: plan\n---\n\n# Reviewer\n- one\n"
// #expect model == "sonnet"
// #expect fields == [("tools", .text("Read, Grep")), ("background", .text("yes")), ("maxTurns", .text("123")), ("permissionMode", .text("plan"))]
// #expect prompt == "# Reviewer\n- one"

@Test func inheritIsSessionModel()          // model: inherit → model == nil, không có field "model"
@Test func foldedDescription()              // "description: >\n  Line one\n  line two\n" → description == "Line one line two"
@Test func literalScalarIsBlock()           // "initialPrompt: |\n  Hello\n  World\n" → .block("Hello\nWorld")
@Test func sequenceOfMappingsIsBlock()      // "skills:\n  - name: a\n    enabled: false\n" → .block("- name: a\n  enabled: false")
@Test func flowMappingIsBlockFromSameLine() // "mcpServers: {a: {command: x}}" → .block("{a: {command: x}}")
@Test func unquotedColonFallsBackToLineScan()
// "---\nname: hunter\ndescription: Use when: things break\nhooks:\n  Stop: []\n---\n"
// #expect isLineScanned, description == "Use when: things break", fields == [("hooks", .block("Stop: []"))]
@Test func lineScanStripsQuotes()           // fallback với name: "x" và model: 'opus' → name "x", model "opus"
@Test func skipsDocsAndNamelessFiles()      // "# Notes\n", frontmatter không có name, name: "" → nil
@Test func emptyBodyHasNoPrompt()           // thân "\n\n" → prompt == nil
@Test func handlesBOMAndCRLF()              // "\u{FEFF}---\r\nname: x\r\ndescription: d\r\n---\r\nBody\r\n" → name "x", prompt "Body"
```

- [ ] **Step 2: Chạy test, phải fail vì chưa có kiểu**

Run: `swift test --package-path Packages/UsageCore --filter MarkdownAgentParserTests`
Expected: FAIL, không biên dịch được `MarkdownAgentParser`.

- [ ] **Step 3: Viết `AgentDefinition.swift` và `MarkdownAgentParser.parse(_:url:)`**

- Bỏ BOM, đổi CRLF thành LF. Dòng đầu phải là `---` (cho phép khoảng trắng cuối dòng), frontmatter kết thúc ở dòng `---` kế tiếp.
- Đường Yams: `Yams.compose(yaml:)` ra `Node`, phải là mapping. Duyệt `Node.Mapping` để giữ thứ tự.
  - Scalar: dùng `Node.Scalar.string`, chuỗi gốc chưa đổi kiểu. Có xuống dòng thì là `.block`, không thì `.text`.
  - Sequence chỉ gồm scalar một dòng: `.text` nối bằng `", "`. Còn lại, và mọi mapping: `.block` lấy từ text gốc.
- Text gốc của một key: phần sau `key:` trên cùng dòng, trừ khi rỗng hoặc là ký hiệu block scalar (`|`, `>`, có thể kèm `-`, `+`, số), cộng các dòng thụt lề hoặc dòng trống phía dưới cho tới key cấp trên cùng kế tiếp. Bỏ thụt lề chung và dòng trống ở cuối.
- `name` trim, rỗng thì trả về nil. `description` là chuỗi của scalar. `model` là `inherit` thì thành nil. Ba key này không vào `fields`.
- Yams lỗi thì đọc theo dòng: dòng ở cột 0 khớp `^([A-Za-z_][A-Za-z0-9_.-]*):(?:\s+(.*))?$` mở một key, dòng bắt đầu bằng `#` bị bỏ qua. Có giá trị trên cùng dòng thì là `.text`, bỏ cặp `"` hoặc `'` bao ngoài. Không có thì gom thành `.block` như trên. `isLineScanned = true`.
- Prompt là phần sau dòng `---` đóng, bỏ dòng trống ở đầu và khoảng trắng ở cuối. Rỗng thì nil.

- [ ] **Step 4: Chạy test, phải pass**

Run: `swift test --package-path Packages/UsageCore --filter MarkdownAgentParserTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/UsageCore/Sources/UsageCore/Agents Packages/UsageCore/Tests/UsageCoreTests/MarkdownAgentParserTests.swift
git commit -m "feat: parse Markdown agent files"
```

---

### Task 2: `AgentDirectory`, `AgentSource` và `MarkdownAgentSource`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Agents/AgentDirectory.swift`
- Create: `Packages/UsageCore/Sources/UsageCore/Agents/AgentSource.swift`
- Create: `Packages/UsageCore/Sources/UsageCore/Agents/MarkdownAgentSource.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/AgentDirectoryTests.swift`, `Packages/UsageCore/Tests/UsageCoreTests/MarkdownAgentSourceTests.swift`

**Interfaces:**
- Consumes: `MarkdownAgentParser.parse(_:url:)`, `AgentDefinition.unreadable(url:error:)` từ Task 1. `TextFile(url:).read()` có sẵn, ném `TextFileError.notText` khi không phải UTF-8.
- Produces:
  ```swift
  public struct AgentDirectory: Sendable {
      public let url: URL
      public let home: URL
      public let fileExtension: String   // "md" hoặc "toml"
      public let recursive: Bool
      public init(url: URL, home: URL, fileExtension: String, recursive: Bool)
      /// nil khi thư mục không tồn tại. Sắp theo đường dẫn, bỏ file ẩn, đi theo symlink.
      public func files() -> [URL]?
      /// "~/.claude/agents/review/x.md": thay phần home bằng "~".
      public func displayPath(of url: URL) -> String
  }
  public enum AgentLoadError: Error, Sendable, Equatable { case cliNotFound, failed(String) }
  public struct AgentListing: Sendable, Equatable {
      public let folderExists: Bool
      public let agents: [AgentDefinition]   // sắp theo name bằng localizedStandardCompare
      public let usesClaudeAgents: Bool      // chỉ Grok dùng
      public init(folderExists: Bool, agents: [AgentDefinition], usesClaudeAgents: Bool = false)
  }
  public protocol AgentSource: Sendable {
      var provider: ProviderID { get }
      var directory: AgentDirectory { get }
      func load() async throws(AgentLoadError) -> AgentListing
  }
  public struct MarkdownAgentSource: AgentSource {
      public static func claude(home: URL) -> MarkdownAgentSource  // ~/.claude/agents, quét thư mục con
      public static func grok(home: URL) -> MarkdownAgentSource    // ~/.grok/agents, chỉ cấp trên cùng
  }
  ```

- [ ] **Step 1: Viết test `@Suite struct AgentDirectoryTests`**

```swift
@Test func listsRecursivelyOnlyWhenAsked()
// home tạm có agents/a.md, agents/sub/b.md, agents/notes.txt, agents/.hidden.md
// recursive: true → [a.md, sub/b.md]; recursive: false → [a.md]
@Test func missingFolderIsNil()             // files() == nil
@Test func followsSymlinks()                // agents/link.md → file ngoài thư mục; cả thư mục agents là symlink → đều có trong files()
@Test func displayPathUsesTilde()           // home/.claude/agents/x.md → "~/.claude/agents/x.md"
```

- [ ] **Step 2: Viết test `@Suite struct MarkdownAgentSourceTests`**

```swift
@Test func claudeListsSortedAgentsAndSkipsDocs()
// ~/.claude/agents: zeta.md (name zeta), Alpha.md (name alpha), sub/beta.md (name beta), README.md (không frontmatter), .DS_Store, notes.txt
// #expect listing.folderExists, listing.agents.map(\.name) == ["alpha", "beta", "zeta"]
@Test func duplicateNamesAreBothListed()    // a.md và sub/a2.md cùng name "same" → 2 agent, id khác nhau
@Test func nonTextFileIsUnreadableAgent()   // bad.md chứa byte 0xFF 0xFE 0x00 → agent name "bad", readError == .notText
@Test func grokReadsTopLevelAndFlagsClaudeAgents()
// ~/.grok/agents/top.md (name top), ~/.grok/agents/sub/nested.md, ~/.claude/agents/c.md
// #expect names == ["top"], usesClaudeAgents == true; xoá c.md → usesClaudeAgents == false
@Test func missingFolder()                  // folderExists == false, agents == []
```

- [ ] **Step 3: Chạy hai suite, phải fail**

Run: `swift test --package-path Packages/UsageCore --filter "AgentDirectoryTests|MarkdownAgentSourceTests"`
Expected: FAIL, chưa có kiểu.

- [ ] **Step 4: Viết ba file**

- `files()`: `recursive` thì dùng `FileManager.enumerator` với `.skipsHiddenFiles`, không thì `contentsOfDirectory`. Đi theo symlink bằng `resolvingSymlinksInPath()` khi kiểm tra file thường hay thư mục, nhưng trả về URL trong thư mục agent. Lọc theo `fileExtension`.
- `MarkdownAgentSource.load()`: đọc từng file bằng `TextFile`. Lỗi đọc thành `AgentDefinition.unreadable` (`.notText` giữ nguyên, lỗi khác thành `.failed(String(describing:))`). Parser trả về nil thì bỏ file. Không bao giờ ném lỗi.
- Grok: `usesClaudeAgents` đúng khi `AgentDirectory(url: home/.claude/agents, home: home, fileExtension: "md", recursive: false).files()` có ít nhất một file.

- [ ] **Step 5: Chạy lại, phải pass**

Run: `swift test --package-path Packages/UsageCore --filter "AgentDirectoryTests|MarkdownAgentSourceTests"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Packages/UsageCore/Sources/UsageCore/Agents Packages/UsageCore/Tests/UsageCoreTests/AgentDirectoryTests.swift Packages/UsageCore/Tests/UsageCoreTests/MarkdownAgentSourceTests.swift
git commit -m "feat: list Claude and Grok agent files"
```

---

### Task 3: `CodexAgentSource`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Agents/CodexAgentSource.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/CodexAgentSourceTests.swift`, `Packages/UsageCore/Tests/UsageCoreTests/CodexAgentIntegrationTests.swift`

**Interfaces:**
- Consumes: `AgentDirectory`, `AgentSource`, `AgentListing`, `AgentLoadError` từ Task 2. `CodexAppServer.withSession(environment:_:)`, `CodexAppServerError.cliNotFound`, `JSONRPCError.server(code:message:data:)`, `OrderedJSON(parsing:)` và `serialized()` có sẵn. Test dùng `ScriptedChannel`, `FakeProcessRunner`, `FakeProbe`, `FakeShell` trong `Tests/UsageCoreTests/Support/`.
- Produces:
  ```swift
  public struct CodexAgentSource: AgentSource {
      public init(locator: CLILocator, pathOverride: @escaping @Sendable () -> String?, runner: any ProcessRunner,
                  clientVersion: String, home: URL, timeout: Duration = .seconds(15))
      public func load() async throws(AgentLoadError) -> AgentListing
  }
  ```

- [ ] **Step 1: Viết test `@Suite struct CodexAgentSourceTests`**

Responder của `ScriptedChannel` trả về chuỗi JSON viết tay để giữ thứ tự key, theo thứ tự lần gọi `config/read`.

```swift
@Test func mapsUserLayerConfigInOrder()
// user layer config: {"name":"reviewer","description":"Reviews","developer_instructions":"# Hi\n- one\n","model":"gpt-5.5","nickname_candidates":["Rev","R2"],"features":{"apps":false},"model_verbosity":"low"}
// #expect name "reviewer", model "gpt-5.5", prompt "# Hi\n- one"
// #expect fields == [("nickname_candidates", .text("Rev, R2")), ("features", .block("{\n  \"apps\": false\n}")), ("model_verbosity", .text("low"))]
@Test func oneBadFileDoesNotStopTheOthers()
// bad.toml rồi good.toml. Lần gọi đầu trả lỗi -32603 "failed to read configuration layers: <CODEX_HOME>/config.toml:2:28: invalid basic string"
// (lấy <CODEX_HOME> từ runner.environment). #expect bad.readError là .failed chứa "bad.toml:2:28" và không chứa đường dẫn tạm; good đọc bình thường
@Test func skipsFilesWithoutName()
@Test func readsSubfolders()                // sub/x.toml có trong listing
@Test func missingOrEmptyFolderDoesNotLaunchCodex() // folderExists false / true, agents rỗng, runner.runCount == 0
@Test func missingCLIThrows()               // probe không thấy codex → throws .cliNotFound
@Test func launchFailureThrowsFailed()      // runner.launchError → throws .failed
@Test func removesTemporaryHome()           // sau load thành công và sau launchError: thư mục ở runner.environment["CODEX_HOME"] không còn
```

- [ ] **Step 2: Viết test tích hợp `@Suite struct CodexAgentIntegrationTests`**

Tìm `codex` như `CodexConfigIntegrationTests`, bỏ qua khi không có. Home tạm có `.codex/agents/broken.toml`
(`name = "a"\ndescription = "unterminated\n`) và `.codex/agents/reviewer.toml` có `developer_instructions`, bảng
`[features]` và một key lạ. Chạy `load()`:
`#expect` broken có `readError` chứa `broken.toml:`, reviewer có prompt, field `features` là `.block`, key lạ là `.text`.

- [ ] **Step 3: Chạy hai suite, phải fail**

Run: `swift test --package-path Packages/UsageCore --filter "CodexAgentSourceTests|CodexAgentIntegrationTests"`
Expected: FAIL, chưa có `CodexAgentSource`.

- [ ] **Step 4: Viết `CodexAgentSource`**

- `directory`: `~/.codex/agents`, đuôi `toml`, quét thư mục con. Không có file nào thì trả về listing ngay, không mở Codex.
- Tạo thư mục tạm quyền 0700, rỗng lúc mở phiên. Mở một phiên với `CODEX_HOME` là thư mục đó. Với từng file: đọc bằng `TextFile` (lỗi thì `unreadable`), ghi thành `config.toml` quyền 0600, gọi `config/read` với `includeLayers: true`.
- Parse phản hồi bằng `OrderedJSON`, lấy `config` của layer có `name.type == "user"`.
- Map: `name` trim, rỗng thì bỏ file. `description` là chuỗi. `model` như Task 1. `developer_instructions` là prompt, trim, rỗng thì nil. Còn lại theo thứ tự: chuỗi một dòng, số (giữ literal), bool là `.text`; chuỗi nhiều dòng là `.block`; array chỉ gồm giá trị đơn là `.text` nối `", "`; object và array khác là `.block(serialized())` bỏ newline cuối; `null` bỏ qua.
- `JSONRPCError.server` của một file thành `unreadable(.failed)`. Lời báo thay `<tạm>/config.toml` bằng tên file agent, rồi bỏ mọi tiền tố đường dẫn tạm, cả bản đã resolve symlink như `CodexConfigBackend.sanitized`.
- `CodexAppServerError.cliNotFound` thành `.cliNotFound`, lỗi khác của phiên thành `.failed`. Xoá thư mục tạm trong mọi trường hợp.

- [ ] **Step 5: Chạy lại, phải pass**

Run: `swift test --package-path Packages/UsageCore --filter "CodexAgentSourceTests|CodexAgentIntegrationTests"`
Expected: PASS. Test tích hợp chạy thật khi máy có `codex`.

- [ ] **Step 6: Commit**

```bash
git add Packages/UsageCore/Sources/UsageCore/Agents/CodexAgentSource.swift Packages/UsageCore/Tests/UsageCoreTests/CodexAgentSourceTests.swift Packages/UsageCore/Tests/UsageCoreTests/CodexAgentIntegrationTests.swift
git commit -m "feat: read Codex agent files through app-server"
```

---

### Task 4: `AgentsDocument`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Agents/AgentsDocument.swift`
- Create: `Packages/UsageCore/Tests/UsageCoreTests/Support/FakeAgentSource.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/AgentsDocumentTests.swift`

**Interfaces:**
- Consumes: `AgentSource`, `AgentListing`, `AgentLoadError` từ Task 2.
- Produces:
  ```swift
  @Observable @MainActor
  public final class AgentsDocument {
      public let source: any AgentSource
      public private(set) var listing: AgentListing?
      public private(set) var loadError: AgentLoadError?
      public private(set) var isLoading: Bool   // chỉ đúng khi chưa có listing và chưa có lỗi
      public init(source: any AgentSource)
      public func refresh() async               // đang chạy thì lần gọi mới bỏ qua
  }
  ```

- [ ] **Step 1: Viết `FakeAgentSource` và test `@Suite @MainActor struct AgentsDocumentTests`**

`FakeAgentSource` trả về kết quả theo kịch bản, đếm số lần `load()`, và có cổng chờ để giữ một lần load đang chạy.

```swift
@Test func firstLoadShowsLoadingThenListing() // trong lúc load: isLoading == true; sau đó listing == kết quả, isLoading == false
@Test func errorKeepsLastListing()            // thành công, rồi lỗi .cliNotFound: loadError set, listing giữ nguyên; thành công lần nữa thì loadError == nil
@Test func overlappingRefreshLoadsOnce()      // hai refresh cùng lúc → source.loadCount == 1
```

- [ ] **Step 2: Chạy test, phải fail**

Run: `swift test --package-path Packages/UsageCore --filter AgentsDocumentTests`
Expected: FAIL

- [ ] **Step 3: Viết `AgentsDocument`**

- [ ] **Step 4: Chạy lại, phải pass**

Run: `swift test --package-path Packages/UsageCore --filter AgentsDocumentTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Packages/UsageCore/Sources/UsageCore/Agents/AgentsDocument.swift Packages/UsageCore/Tests/UsageCoreTests/Support/FakeAgentSource.swift Packages/UsageCore/Tests/UsageCoreTests/AgentsDocumentTests.swift
git commit -m "feat: add the Agents document"
```

---

### Task 5: Khung trang và danh sách

**Files:**
- Create: `App/Views/Main/PageHeader.swift`, `App/Views/Main/PageMessage.swift`, `App/Views/Main/AgentsPage.swift`, `App/Views/Main/AgentCard.swift`
- Modify: `App/Views/Main/InstructionsPage.swift`, `App/Views/Main/ProviderSelector.swift`, `App/Views/Main/AppPage.swift`, `App/Views/Main/MainWindow.swift`, `App/Views/Main/AppCommands.swift`, `App/AppModel.swift`, `App/Views/PreviewSupport.swift`, `App/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `AgentsDocument`, `MarkdownAgentSource.claude(home:)`, `.grok(home:)`, `CodexAgentSource(...)`, `AgentDirectory.displayPath(of:)` từ Task 2 đến 4.
- Produces:
  ```swift
  struct PageHeader<Top: View, Trailing: View>: View {
      init(title: String, path: String, revealURL: URL?,
           @ViewBuilder top: () -> Top, @ViewBuilder trailing: () -> Trailing)
  }
  struct PageMessage<Actions: View>: View {
      init(systemImage: String, text: String, @ViewBuilder actions: () -> Actions)
  }
  struct AgentsPage: View { let model: AppModel }
  struct AgentCard: View { let agent: AgentDefinition }
  // AppModel: let agents: [ProviderID: AgentsDocument]
  // ProviderSelector: var providers: [ProviderID] = ProviderID.configurable
  // AppPage: case usage, instructions, agents, config
  ```

- [ ] **Step 1: Tách `PageHeader` và `PageMessage` từ `InstructionsPage`**

- `PageHeader` là đúng khối đầu trang hiện có: `VStack(spacing: 12)` gồm `top` và tiêu đề 52pt, rồi hàng đường dẫn `HStack(spacing: 8)` `.caption.monospaced()`, nút Show in Finder khi `revealURL` khác nil, rồi `trailing`, cả hàng `.secondary`. Hai phần cách nhau 16.
- `PageMessage` là khối báo lỗi hiện có: icon `.title` `.secondary`, text, actions, `VStack(spacing: 12)`, `.padding(.top, 24)`, canh trên trái.
- `InstructionsPage` dùng hai view này. Trang phải trông y như cũ: `trailing` là `·` và "Applies to new sessions".

- [ ] **Step 2: Nối trang vào app**

- `ProviderSelector` thêm `providers`, mặc định `ProviderID.configurable`.
- `AppPage` thêm `agents` giữa `instructions` và `config`, tiêu đề "Agents".
- `AppModel.agents`: Claude và Grok dùng `MarkdownAgentSource`, Codex dùng `CodexAgentSource` với cùng `locator`, `pathOverride`, `runner`, `version` như `CodexConfigBackend`.
- `MainWindow`: thêm `case .agents: AgentsPage(model: model)`. Khi `page` đổi sang `instructions` hoặc `config` mà `selectedProvider` không thuộc `ProviderID.configurable` thì đặt về `.claude`.
- `AppCommands`: `.agents` không lưu được, Save bị tắt.

- [ ] **Step 3: Viết `AgentCard` và phần danh sách của `AgentsPage`**

- Khung trang như Instructions: `.frame(maxWidth: 720)`, `.padding(.horizontal, 24)`, `.padding(.top, 16)`, canh trên.
- `PageHeader`: `top` là `ProviderSelector(selection:providers: ProviderID.allCases)`. Tiêu đề là "%lld agents" theo số agent, chưa có listing thì là "Agents". Đường dẫn là `directory.displayPath(of: directory.url)`, nút Finder chỉ khi `folderExists`. `trailing` rỗng.
- `usesClaudeAgents`: `Label` icon `info.circle`, `.callout` `.secondary`, ngay dưới phần đầu trang.
- Nội dung, theo thứ tự ưu tiên:
  - `loadError == .cliNotFound`: `PageMessage` icon `exclamationmark.triangle`, "Agenty needs the Codex CLI to read Codex agents.", nút "Choose path…" như trang Config (lưu vào `SettingsKey.providerPath(.codex)` rồi làm mới).
  - `.failed(reason)`: `PageMessage` icon `exclamationmark.triangle`, "Agenty can't read the Codex agents: %@", nút "Try Again".
  - `isLoading`: `ProgressView`.
  - Thư mục chưa có hoặc rỗng: `PageMessage` icon `doc.badge.ellipsis` với hai câu ở spec mục 3.4.
  - Còn lại: `ScrollView` chứa `LazyVGrid` 2 cột `.flexible()`, spacing 16, mỗi thẻ là `Button(.plain)`. Bấm thẻ thì Task 6 mở chi tiết, ở task này chỉ cần giữ `@State private var openURL: URL?`.
- `AgentCard` theo Global Constraints. Badge là `model` hoặc "Session model" chữ `.secondary`. Thiếu mô tả: "No description" `.tertiary`. Có `readError`: không badge, chỗ mô tả là lý do `.orange` ("This file isn't plain text." cho `.notText`, chuỗi lỗi cho `.failed`).
- Làm mới: `.task(id: model.selectedProvider)` và khi nhận `NSApplication.didBecomeActiveNotification`.

- [ ] **Step 4: Chuỗi và preview**

Thêm en và vi: "Agents" → "Agent"; "%lld agents" có plural en (one "%lld agent", other "%lld agents"), vi "%lld agent"; "Session model" → "Model của phiên"; "No description" → "Không có mô tả"; "Grok also uses the agents in ~/.claude/agents." → "Grok cũng dùng các agent trong ~/.claude/agents."; "This folder doesn't exist yet, so %@ has no agents of yours." → "Thư mục này chưa tồn tại, nên %@ chưa có agent nào của bạn."; "%@ has no agents of yours in this folder." → "%@ chưa có agent nào của bạn trong thư mục này."; "Agenty needs the Codex CLI to read Codex agents." → "Agenty cần CLI Codex để đọc agent của Codex."; "Agenty can't read the Codex agents: %@" → "Agenty không đọc được agent của Codex: %@"; "This file isn't plain text." → "File này không phải văn bản thuần.".

`PreviewSupport.swift` thêm một `AgentSource` trả về listing hoặc lỗi cố định. `#Preview` cho: 6 agent Claude, thư mục chưa có, thiếu CLI Codex, tab Grok có dòng báo.

- [ ] **Step 5: Build (controller)**

Run: lệnh Build ở đầu plan.
Expected: `** BUILD SUCCEEDED **`, `swift test --package-path Packages/UsageCore` vẫn pass.

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "feat: add the Agents page list"
```

---

### Task 6: Trang chi tiết

**Files:**
- Create: `App/Views/Main/MarkdownStyler.swift`, `App/Views/Main/AgentDetail.swift`
- Modify: `App/Views/Main/InstructionsEditor.swift`, `App/Views/Main/AgentsPage.swift`, `App/Views/PreviewSupport.swift`, `App/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `PageHeader`, `PageMessage`, `AgentsPage.openURL` từ Task 5; `AgentDefinition` từ Task 1.
- Produces:
  ```swift
  enum MarkdownStyler {
      static func apply(to value: inout AttributedString, tint: Color)  // chuyển nguyên từ InstructionsEditor.applyStyling
      static func styled(_ text: String, tint: Color) -> AttributedString
  }
  struct AgentDetail: View {
      let agent: AgentDefinition
      let provider: ProviderID
      let path: String          // directory.displayPath(of: agent.url)
      let backTitle: String     // cùng chuỗi "%lld agents" của tiêu đề danh sách
      let onBack: () -> Void
  }
  ```

- [ ] **Step 1: Tách `MarkdownStyler`**

`InstructionsEditor` gọi `MarkdownStyler.apply(to:tint:)`. Editor phải trông và chạy y như cũ.

- [ ] **Step 2: Viết `AgentDetail`**

- `PageHeader`: `top` là nút quay lại, `Button` `.plain` chứa `chevron.left` 16×16 và `backTitle` `.callout`, `.padding(.horizontal, 12).padding(.vertical, 4)`, rồi `.padding(4).glassEffect(.regular, in: .capsule)` như `ProviderSelector`. `.keyboardShortcut(.cancelAction)` để Esc quay lại, `.accessibilityLabel("Back to agents")`. Tiêu đề là `agent.name`, nút Finder trỏ `agent.url`.
- Có `readError`: `PageMessage` icon `doc.badge.ellipsis`, "Agenty can't read this file: %@" (chuỗi đã có), nút "Show in Finder".
- Không thì `ScrollView`, `VStack(spacing: 16)`, theo spec mục 3.3:
  1. `isLineScanned`: `Label` cam icon `exclamationmark.triangle.fill`, `.callout`, "This file isn't valid YAML, so Agenty read it line by line."
  2. `description`, `.body`.
  3. Thẻ field: dòng `model` trước, giá trị như badge của thẻ, rồi mọi `.text` field. Tên field dùng `Text(verbatim:)`.
  4. Mỗi `.block` field một thẻ code: tên `.title3` semibold, nội dung 13pt monospaced, `.textSelection(.enabled)`.
  5. `prompt`: `Text(MarkdownStyler.styled(prompt, tint: ProviderStyle.tint(provider)))`, `.textSelection(.enabled)`, nằm thẳng trên trường màu.

- [ ] **Step 3: Nối vào `AgentsPage`**

Bấm thẻ thì `openURL = agent.url`. Đổi provider thì `openURL = nil`. Sau mỗi lần làm mới, nếu `openURL` không còn trong listing thì về danh sách.

- [ ] **Step 4: Chuỗi và preview**

Thêm en và vi: "Back to agents" → "Quay lại danh sách agent"; "This file isn't valid YAML, so Agenty read it line by line." → "File này không phải YAML hợp lệ, nên Agenty đọc theo từng dòng.". `#Preview` cho: agent thật chỉ có hooks, agent có field và prompt, agent đọc theo dòng, file không đọc được.

- [ ] **Step 5: Build (controller)**

Run: lệnh Build ở đầu plan.
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "feat: add the agent detail page"
```

---

### Task 7: Tài liệu

**Files:**
- Modify: `DESIGN.md`, `README.md`

- [ ] **Step 1: Sửa `DESIGN.md` theo spec mục 6**

Palette thêm Grok `#9AA0A6` và sửa câu "hai màu provider" ở Don't thành ba màu. Typography: "Tên file" thành "Tiêu đề trang" (tên file, số agent, tên agent), "Tên provider" thành "Tiêu đề thẻ". Components: Thẻ agent, Nút quay lại, Trang Agents (Danh sách, Chi tiết). Depth: thêm nút quay lại vào danh sách Liquid Glass. Câu mở đầu nhắc cả Grok.

- [ ] **Step 2: Sửa `README.md`**

Dòng Main window kể thêm trang Agents. Thêm một đoạn sau đoạn Config: trang Agents liệt kê agent của bạn trong `~/.claude/agents`, `~/.codex/agents` và `~/.grok/agents`, có model và trang chi tiết, chỉ xem; tab Codex cần CLI Codex.

- [ ] **Step 3: Commit**

```bash
git add DESIGN.md README.md
git commit -m "docs: describe the Agents page"
```

---

### Task 8: Kiểm tra lần cuối (controller)

- [ ] **Step 1: Toàn bộ test và build**

Run: `swift test --package-path Packages/UsageCore`, rồi lệnh Build.
Expected: mọi test pass, `** BUILD SUCCEEDED **`. Hoàn nguyên `Package.resolved` nếu chỉ có pin Sparkle.

- [ ] **Step 2: Xem nhanh trên Agenty Dev**

Thoát Agenty Dev đang chạy, mở bản mới. Xem ba tab, một trang chi tiết, cửa sổ tối thiểu, light và dark. Trang chỉ đọc nên không cần home tạm, nhưng không chạy app lâu.

- [ ] **Step 3: Review cả nhánh**

Chạy nền `codex-task adversarial-review --base next` và `grok-task critique --base next`. Kiểm từng phát hiện với code trước khi sửa. Sửa thì commit riêng.
