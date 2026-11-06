# Cửa sổ chính Ambient và trình sửa instructions: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm cửa sổ chính kiểu Ambient với hai trang Usage và Instructions, trong đó Instructions xem và sửa được `~/.claude/CLAUDE.md` và `~/.codex/AGENTS.md`.

**Architecture:** Logic file và bản nháp nằm trong `UsageCore` để có unit test. Giao diện nằm trong `App/Views/Main/`, mỗi tính năng là một case của `AppPage`. `AppModel` giữ bản nháp nên đóng cửa sổ không mất dữ liệu.

**Tech Stack:** Swift 6, SwiftUI trên macOS 27, Swift Testing, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-06-app-shell-instructions-design.md`. Mọi giao diện theo `DESIGN.md`. Giá trị hiển thị tham khảo `docs/superpowers/spikes/2026-11-06-ambient-prototype.swift`, phần `ManuscriptEditor`, `ProviderColumn`, `StatesPage`, `AmbientField`, `Root`.

## Global Constraints

- Target macOS 27.0, `SWIFT_STRICT_CONCURRENCY: complete`, app không sandbox.
- Accent của hệ thống, không thêm asset `AccentColor`. Màu riêng chỉ có Claude `#D97857`, Codex `#6B6BF2`.
- Liquid Glass chỉ cho toolbar, bộ chọn provider, viên lưu. Thẻ dùng `.thinMaterial`, bo góc 24.
- Nội dung rộng tối đa 960pt, editor 720pt, cửa sổ tối thiểu 860×580, cỡ nội dung không phóng theo cửa sổ.
- Không đổi giao diện popover và Settings, trừ nút mở cửa sổ chính.
- Khoảng cách trong cửa sổ chính chỉ dùng token 4, 8, 12, 16, 24, 32 của `DESIGN.md`. Bản thử có các số 2, 6, 20: làm tròn về token gần nhất.
- Mọi chuỗi có bản en và vi trong `App/Resources/Localizable.xcstrings`.
- Commit không có dòng Co-Authored-By Claude. PR không có footer Claude Code.
- Sau mỗi lần `xcodebuild`, chạy `git checkout -- Packages/UsageCore/Package.resolved` trước khi commit.
- Giữ kiểm chứng vừa đủ: test, build, xem nhanh. Không chạy app kiểm tra dài.

**Lệnh dùng chung:**
- Test: `swift test --package-path Packages/UsageCore --filter <Suite>`
- Build: `xcodegen generate && xcodebuild -project Agenty.xcodeproj -scheme Agenty -configuration Debug -derivedDataPath build/DerivedData build`, kết quả phải có `** BUILD SUCCEEDED **`.

## Review Focus

1. File dùng CRLF hoặc không có newline cuối: lưu mà không sửa gì thì nội dung trên đĩa giữ nguyên từng byte. Test ở Task 1.
2. File bị xoá từ ngoài khi đang có bản nháp: báo xung đột, không âm thầm tạo lại. Test ở Task 2.
3. Symlink trỏ tới file chưa có: lưu tạo file đích, symlink còn nguyên. Test ở Task 1.
4. `AGENTS.override.md` chỉ có khoảng trắng: coi là trống, không cảnh báo. Test ở Task 1.
5. Thư mục không ghi được: báo lỗi, bản nháp còn nguyên, vẫn là dirty. Test ở Task 2.

---

### Task 0: Tạo nhánh và commit tài liệu

**Files:**
- Add: `DESIGN.md`, spec, spike, plan này

- [ ] **Step 1: Tạo nhánh từ `next`**

Run: `git switch -c feat/main-window`

- [ ] **Step 2: Commit tài liệu**

```bash
git add DESIGN.md docs/superpowers/specs/2026-11-06-app-shell-instructions-design.md docs/superpowers/spikes/2026-11-06-ambient-prototype.swift docs/superpowers/plans/2026-11-06-app-shell-instructions.md
git commit -m "docs: add the design language and the main window spec"
```

### Task 1: `InstructionsFile`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Instructions/InstructionsFile.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/InstructionsFileTests.swift`

**Interfaces:**
- Produces:

```swift
public enum InstructionsError: Error, Sendable, Equatable {
    case notText                // bytes are not valid UTF-8
    case readFailed(String)     // localized system reason
    case writeFailed(String)
}

public struct InstructionsFile: Sendable {
    public let provider: ProviderID
    public let url: URL
    public init(provider: ProviderID, home: URL)
    public var fileName: String      // "CLAUDE.md" | "AGENTS.md"
    public var displayPath: String   // "~/.claude/CLAUDE.md" | "~/.codex/AGENTS.md"
    public func read() throws(InstructionsError) -> String?   // nil when the file does not exist
    public func write(_ text: String) throws(InstructionsError)
    public var isOverridden: Bool    // Codex only: ~/.codex/AGENTS.override.md has non-whitespace content
}
```

- [ ] **Step 1: Viết test thất bại**

Mỗi test tạo một thư mục tạm làm `home`. Tên test và điều kiện:

- `pathsPerProvider`: `url` kết thúc bằng `.claude/CLAUDE.md` và `.codex/AGENTS.md`, `displayPath` đúng như trên.
- `readExisting`: `read()` trả đúng nội dung.
- `readMissing`: trả `nil`.
- `readNotUTF8`: file chứa `Data([0xFF, 0xFE, 0x00])`, ném `.notText`.
- `writeCreatesParents`: `home` chưa có `.claude`, `write` tạo được file.
- `writeKeepsPermissions`: file `0o600`, sau `write` vẫn `0o600`.
- `writeThroughSymlink`: `url` là symlink tới file khác, sau `write` file đích đổi nội dung, `url` vẫn là symlink.
- `writeThroughDanglingSymlink`: đích chưa có, sau `write` đích được tạo, `url` vẫn là symlink.
- `roundTripKeepsBytes`: `"a\r\nb"` (không newline cuối), `write` rồi `read` bằng đúng chuỗi đó, và `Data` trên đĩa bằng `Data("a\r\nb".utf8)`.
- `overrideAbsentEmptyOrFilled`: không có file thì false, `""` thì false, `" \n"` thì false, `"x"` thì true.
- `overrideClaudeAlwaysFalse`: provider `.claude` luôn false.

- [ ] **Step 2: Chạy test, xác nhận thất bại**

Run lệnh test với `--filter InstructionsFileTests`. Expected: lỗi biên dịch vì chưa có `InstructionsFile`.

- [ ] **Step 3: Viết `InstructionsFile`**

Ghi: theo chuỗi symlink bằng `destinationOfSymbolicLink` để lấy file đích (đích tương đối tính từ thư mục chứa link, đích có thể chưa tồn tại), tạo thư mục cha, ghi ra file tạm cùng thư mục. Nếu đích đã có thì `replaceItemAt`, chưa có thì `moveItem`. Không bỏ qua lỗi nào, chuyển thành `.writeFailed(error.localizedDescription)`.

- [ ] **Step 4: Chạy test, xác nhận đạt**

Expected: toàn bộ `InstructionsFileTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/UsageCore
git commit -m "feat(core): read and write the global instruction files"
```

### Task 2: `InstructionsDocument`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Instructions/InstructionsDocument.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/InstructionsDocumentTests.swift`

**Interfaces:**
- Consumes: `InstructionsFile`, `InstructionsError` từ Task 1.
- Produces:

```swift
@Observable @MainActor
public final class InstructionsDocument {
    public let file: InstructionsFile
    public var draft: String
    public private(set) var fileExists: Bool
    public private(set) var hasConflict: Bool
    public private(set) var loadError: InstructionsError?
    public private(set) var saveError: InstructionsError?
    public private(set) var isOverridden: Bool
    public var isDirty: Bool                     // draft != original
    public init(file: InstructionsFile)          // does not touch the disk
    public func refresh()                        // first load and every later disk check
    public func save()
    public func revert()                         // draft = original, clears saveError
    public func keepMine()                       // original = disk content, clears hasConflict
    public func reload()                         // draft = original = disk, clears hasConflict
}
```

`original` có kiểu `String?`, `nil` nghĩa là file chưa có. `isDirty` so `draft` với `original ?? ""`, nên file chưa có mà chưa gõ gì thì không dirty.

`refresh()`: đọc đĩa, cập nhật `isOverridden`. Nếu đĩa khác `original`: chưa dirty thì tự tải lại, đang dirty thì `hasConflict = true`. Nếu đĩa trở lại bằng `original` thì xoá `hasConflict`. File thiếu là `nil`, khác với `""`.

`save()`: gọi `refresh()` trước. Có xung đột hoặc `loadError` thì không ghi. Ghi thành công thì `original = draft`, `fileExists = true`, xoá `saveError`.

- [ ] **Step 1: Viết test thất bại**

Tên test và điều kiện:

- `loadsContent`, `missingIsCleanAndEmpty` (`fileExists == false`, `isDirty == false`).
- `dirtyAndRevert`.
- `saveWritesAndCleans`, `saveCreatesMissingFile`.
- `cleanReloadsExternalChange`.
- `dirtyFlagsConflict`: sửa file ngoài khi có nháp, `refresh()` cho `hasConflict == true`, nháp giữ nguyên.
- `saveDuringConflictDoesNotWrite`: đĩa vẫn giữ nội dung bên ngoài.
- `keepMineThenSaveOverwrites`.
- `reloadDropsDraft`.
- `conflictClearsWhenDiskReturns`: đĩa đổi rồi đổi lại đúng nội dung gốc, `refresh()` cho `hasConflict == false`, nháp giữ nguyên.
- `deletedFileWithDraftIsConflict`: xoá file khi có nháp, `refresh()` cho `hasConflict == true`, `save()` không tạo lại file.
- `notUTF8SetsLoadError`: `loadError == .notText`, `save()` không ghi.
- `saveFailureKeepsDraft`: thư mục cha đặt `0o500`, `save()` cho `saveError` khác nil, `isDirty == true`, nháp giữ nguyên. Trả quyền `0o700` khi dọn.

- [ ] **Step 2: Chạy test, xác nhận thất bại**

Expected: lỗi biên dịch.

- [ ] **Step 3: Viết `InstructionsDocument`**

- [ ] **Step 4: Chạy test, xác nhận đạt**

Expected: `InstructionsDocumentTests` PASS.

- [ ] **Step 5: Commit**

```bash
git add Packages/UsageCore
git commit -m "feat(core): track instruction drafts and outside changes"
```

### Task 3: `MarkdownLineStyle`

**Files:**
- Create: `Packages/UsageCore/Sources/UsageCore/Instructions/MarkdownLineStyle.swift`
- Test: `Packages/UsageCore/Tests/UsageCoreTests/MarkdownLineStyleTests.swift`

**Interfaces:**
- Produces:

```swift
public struct MarkdownLineStyle: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case heading(level: Int), listItem, plain }
    public let kind: Kind
    public let line: Range<String.Index>     // without the line break
    public let marker: Range<String.Index>?  // "## " or "- "
    public static func parse(_ text: String) -> [MarkdownLineStyle]
}
```

- [ ] **Step 1: Viết test thất bại**

- `headingLevels`: `"# a"` là level 1, `"### a"` là level 3, marker là phần `"# "`.
- `hashWithoutSpaceIsPlain`: `"#tag"` là `.plain`.
- `listItem`: `"- a"` là `.listItem`. `"-a"` là `.plain`.
- `blankAndPlain`: `""` là `.plain`, marker nil.
- `crlfLinesExcludeBreak`: `"# a\r\nb"` cho 2 dòng, `text[line]` của dòng đầu là `"# a"`.
- `vietnameseIndices`: `"# Tiếng Việt"`, `text[line]` bằng đúng chuỗi đó.

- [ ] **Step 2: Chạy test, xác nhận thất bại**

- [ ] **Step 3: Viết `MarkdownLineStyle.parse`**

- [ ] **Step 4: Chạy test, xác nhận đạt**

- [ ] **Step 5: Commit**

```bash
git add Packages/UsageCore
git commit -m "feat(core): classify markdown lines for the editor"
```

### Task 4: Khung cửa sổ chính và Dock

**Files:**
- Create: `App/Views/Main/AppPage.swift`, `App/Views/Main/MainWindow.swift`, `App/Views/Main/AmbientField.swift`, `App/System/DockPolicy.swift`
- Modify: `App/AgentyApp.swift`, `App/AppModel.swift`, `App/Settings/AppSettings.swift`, `App/Views/Popover/PopoverFooter.swift`, `App/Views/ProviderStyle.swift`

**Interfaces:**
- Consumes: `InstructionsFile`, `InstructionsDocument`.
- Produces:

```swift
enum AppPage: String, CaseIterable, Identifiable { case usage, instructions }  // title: LocalizedStringResource
struct MainWindow: View { let model: AppModel }
struct AmbientField: View { let page: AppPage; let selected: ProviderID }
enum DockPolicy { @MainActor static func windowDidAppear(); @MainActor static func windowDidDisappear() }
extension ProviderStyle { static func tint(_ p: ProviderID) -> Color }  // #D97857, #6B6BF2

// AppModel
let instructions: [ProviderID: InstructionsDocument]
var selectedInstructions: ProviderID = .claude
// AppSettings
SettingsKey.mainPage = "mainPage"
```

- [ ] **Step 1: Thêm scene `Window("Agenty", id: "main")`**

Dùng `.windowStyle(.hiddenTitleBar)`, `.windowToolbarStyle(.unified)`, `.windowBackgroundDragBehavior(.enabled)`, `.defaultSize(width: 980, height: 640)`, `.defaultLaunchBehavior(.suppressed)`.

- [ ] **Step 2: Viết `MainWindow`, `AmbientField`, `AppPage`**

Lấy từ `Root` và `AmbientField` trong bản thử: `.toolbar(removing: .title)`, `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`, mục điều hướng ở `.principal`, `frame(minWidth: 860, minHeight: 580)`. Độ mạnh màu 1 ở Usage, 0.45 ở Instructions. Mỗi trang tạm là `Text` để build được, Task 5 và 7 thay vào.

- [ ] **Step 3: Viết `DockPolicy`, gọi từ `onAppear` và `onDisappear` của `MainWindow`**

Xuất hiện: `.regular` rồi `NSApp.activate()`. Biến mất: `.accessory`.

- [ ] **Step 4: Thêm nút mở cửa sổ vào footer popover**

Icon `macwindow`, đặt trước nút Settings, nhãn VoiceOver và `help` là "Open Agenty". Dùng `@Environment(\.openWindow)`, gọi `openWindow(id: "main")` rồi `NSApp.activate()`. Popover không có `AppModel`, chỉ cần môi trường.

- [ ] **Step 5: Build và xem nhanh**

Run lệnh build rồi mở `build/DerivedData/Build/Products/Debug/Agenty Dev.app`. Expected: app khởi động không mở cửa sổ. Bấm nút thì cửa sổ mở và icon Dock hiện, đóng thì icon biến mất, bấm lần hai không tạo cửa sổ thứ hai. Traffic light thẳng hàng với thanh điều hướng.

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "feat: add the main window with an ambient background"
```

### Task 5: Trang Usage

**Files:**
- Create: `App/Views/Main/UsagePage.swift`, `App/Views/Main/UsageProviderCard.swift`, `App/Views/Main/AppCommands.swift`
- Modify: `App/Views/Popover/ProviderErrorView.swift`, `App/Views/Main/MainWindow.swift`, `App/AgentyApp.swift`

**Interfaces:**
- Consumes: `UsageStore.summaries`, `ProviderSummary.window` (đã là `mostConstrained`), `summary.level`, `summary.displayError`, `Formatting.title`, `Formatting.reset`, `Formatting.credits`, `UsageWindow.sharesReset(with:)`, `UsageLevel.of`.
- Produces:

```swift
struct UsagePage: View { let store: UsageStore; let onRetryKeychain: @MainActor () -> Void }
struct UsageProviderCard: View { let summary: ProviderSummary; let store: UsageStore; let onRetryKeychain: @MainActor () -> Void }
struct ProviderErrorContent  // shared message and action button, used by ProviderErrorView and the card
struct AppCommands: Commands { let model: AppModel }  // reads the page from @AppStorage(SettingsKey.mainPage)
```

- [ ] **Step 1: Tách câu lỗi và nút khỏi `ProviderErrorView`**

Popover phải hiển thị y như cũ. Thẻ dùng lại đúng câu và nút đó.

- [ ] **Step 2: Viết `UsageProviderCard`**

Bố cục theo spec mục 3.3, kích thước theo `ProviderColumn` trong bản thử. Các nhánh trạng thái theo bảng ở spec, dùng `Hero`, `Blocked`, `InlineNotice` trong bản thử làm mẫu. Icon: warning `exclamationmark.triangle.fill`, critical `exclamationmark.octagon.fill`, mất mạng `wifi.slash`. Không có cửa sổ nào vẫn hiện Credits nếu có. Thêm `#Preview` cho từng trạng thái.

- [ ] **Step 3: Viết `UsagePage`**

Các thẻ trong `HStack(alignment: .top, spacing: 24)`, `.frame(maxWidth: 960)`, canh giữa. Một provider thì thẻ giữ độ rộng 468pt, không kéo đầy. Không có provider thì `ContentUnavailableView("No providers enabled", systemImage: "gauge")`. Làm mới bằng `store.refreshIfOlder(than: .seconds(60))` khi trang xuất hiện.

- [ ] **Step 4: Thêm toolbar và lệnh Refresh**

`Updated` và nút Refresh ở `.primaryAction`, chỉ ở trang Usage. Dùng lại đúng chuỗi và cách đổi cam khi `isStale` của `PopoverFooter`. Thêm `AppCommands` vào scene `Window` bằng `.commands`, có `CommandGroup(after: .toolbar)` chứa Refresh ⌘R, chỉ bật ở trang Usage.

- [ ] **Step 5: Build và xem nhanh**

Expected: số lớn và dòng phụ khớp popover, cửa sổ nhỏ và lớn đều gọn. Xem các trạng thái lỗi bằng `#Preview`.

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "feat: show usage as provider cards in the main window"
```

### Task 6: Editor Markdown và kiểm tra bộ gõ

**Files:**
- Create: `App/Views/Main/InstructionsEditor.swift`
- Modify: `App/Views/Main/MainWindow.swift`

**Interfaces:**
- Consumes: `MarkdownLineStyle.parse`, `ProviderStyle.tint`.
- Produces:

```swift
struct InstructionsEditor: View {
    @Binding var text: String   // plain Markdown, never contains styling
    let tint: Color
}
```

- [ ] **Step 1: Viết `InstructionsEditor` bằng `TextEditor` với `AttributedString`**

Heading cấp 1 là 22pt, các cấp khác 16pt, chữ thường 13pt, đều monospaced. Heading semibold. Dấu marker mang `tint`. Tô lại mỗi khi text đổi, giữ nguyên vị trí con trỏ. Binding `text` lấy từ `String(attributed.characters)`.

- [ ] **Step 2: Dừng lại, nhờ người dùng thử bộ gõ**

Tạm gắn editor vào trang Instructions, build Agenty Dev. Người dùng gõ tiếng Việt bằng Telex: `tiếng Việt được không`, ở cả dòng heading. Tiêu chí đạt: không lặp hay mất ký tự, con trỏ không nhảy, ⌘Z hoạt động.

- [ ] **Step 3: Nếu không đạt, viết lại bằng `NSViewRepresentable` bọc `NSTextView`**

Giữ nguyên interface ở trên. Chỉ tô lại khi `hasMarkedText()` là false, áp màu trực tiếp lên `textStorage`. Lặp lại Step 2. Nếu đạt ngay ở Step 2 thì bỏ qua bước này.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "feat: add a markdown editor for instruction files"
```

### Task 7: Trang Instructions, viên lưu và xác nhận khi thoát

**Files:**
- Create: `App/Views/Main/InstructionsPage.swift`, `App/Views/Main/SaveCapsule.swift`, `App/System/AppDelegate.swift`
- Modify: `App/AgentyApp.swift`, `App/Views/Main/MainWindow.swift`

**Interfaces:**
- Consumes: `AppModel.instructions`, `AppModel.selectedInstructions`, toàn bộ API của `InstructionsDocument`, `InstructionsEditor`.
- Produces:

```swift
struct InstructionsPage: View { let model: AppModel }
struct SaveCapsule: View { let document: InstructionsDocument }
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()   // AgentyApp reads this instead of its own @State
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply
}
```

- [ ] **Step 1: Viết `InstructionsPage`**

Bố cục theo `ManuscriptEditor` trong bản thử, trạng thái theo bảng spec mục 3.4. Gọi `document.refresh()` khi trang xuất hiện, khi đổi provider, và khi nhận `NSApplication.didBecomeActiveNotification`. Bộ chọn provider có `help` và nhãn VoiceOver. Chữ gợi ý của file chưa có phải canh cùng vị trí với text, không chạm con trỏ.

- [ ] **Step 2: Viết `SaveCapsule`**

Theo `Capsule2` trong bản thử, ưu tiên trạng thái: `hasConflict`, rồi `saveError`, rồi `isDirty`. Câu chữ: "Unsaved changes", "Changed outside Agenty", "Couldn't save: \(reason)". Nút: Revert, Save, Keep Mine, Reload, Try Again.

- [ ] **Step 3: Thêm lệnh Save vào menu**

Thêm vào `AppCommands`: `CommandGroup(replacing: .saveItem)`, ⌘S, gọi `save()` của document đang chọn, chỉ bật khi đang ở trang Instructions và `isDirty`.

- [ ] **Step 4: Viết `AppDelegate` và nối bằng `@NSApplicationDelegateAdaptor`**

Chuyển `AppModel` sang `AppDelegate`, để delegate đọc được bản nháp. `AgentyApp` bỏ `@State model`, dùng `delegate.model`.

Nếu có document `isDirty`, hiện `NSAlert` với Save, Discard, Cancel. Save lưu mọi document dirty, và nếu có cái lỗi hoặc xung đột thì huỷ thoát. Không có bản nháp thì thoát ngay.

- [ ] **Step 5: Build và thử nhanh**

Expected: sửa rồi Save thì `~/.claude/CLAUDE.md` đổi. Đóng cửa sổ rồi mở lại, bản nháp còn. Sửa file ngoài khi có nháp, quay lại app thì viên lưu báo xung đột. Thoát khi có nháp thì có hộp xác nhận. Dùng file tạm hoặc sao lưu trước, không để lại thay đổi trong file thật của người dùng.

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "feat: edit global instructions in the main window"
```

### Task 8: Bản dịch, README và rà soát cuối

**Files:**
- Modify: `App/Resources/Localizable.xcstrings`, `README.md`

- [ ] **Step 1: Thêm bản vi cho mọi chuỗi mới**

Sau khi build, tìm chuỗi thiếu bằng cách lọc các key không có `vi` trong `Localizable.xcstrings`. Expected: không còn key thiếu.

- [ ] **Step 2: Cập nhật README**

Thêm cửa sổ chính và trang Instructions vào phần tính năng.

- [ ] **Step 3: Chạy toàn bộ test và build**

Run: `swift test --package-path Packages/UsageCore`, rồi lệnh build. Expected: tất cả PASS, `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Xem nhanh theo spec mục 5**

Cửa sổ nhỏ và full screen, light và dark. Đo tương phản của `#D97857` và `#6B6BF2` trên nền sáng. Nếu dấu Markdown dưới 3:1 thì báo lại người dùng, chưa tự đổi màu.

- [ ] **Step 5: Commit**

```bash
git add App README.md
git commit -m "docs: describe the main window and add Vietnamese strings"
```
