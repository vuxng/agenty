import AppKit
import SwiftUI

let claudeTint = Color(red: 0.85, green: 0.47, blue: 0.34)
let codexTint = Color(red: 0.42, green: 0.42, blue: 0.95)

func logo(_ name: String) -> Image {
    if let url = Bundle.main.url(forResource: name, withExtension: "svg"), let image = NSImage(contentsOf: url) {
        return Image(nsImage: image)
    }
    return Image(systemName: "circle.fill")
}

enum Page: String, CaseIterable, Identifiable {
    case usage = "Usage", instructions = "Instructions", states = "States (preview)"
    var id: Self { self }
}

enum Provider: String, CaseIterable, Identifiable {
    case claude = "Claude", codex = "Codex"
    var id: Self { self }
    var tint: Color { self == .claude ? claudeTint : codexTint }
    var logoName: String { self == .claude ? "ClaudeBrandLogo" : "CodexBrandLogo" }
    var path: String { self == .claude ? "~/.claude/CLAUDE.md" : "~/.codex/AGENTS.md" }
}

let args = ProcessInfo.processInfo.arguments
let contentWidth: CGFloat = 960

@main
struct ProtoApp: App {
    init() { NSApplication.shared.setActivationPolicy(.regular) }
    var body: some Scene {
        Window("Agenty", id: "main") {
            Root().onAppear {
                NSApp.activate()
                if args.contains("--small"), let screen = NSScreen.main {
                    let f = screen.visibleFrame
                    DispatchQueue.main.async { NSApp.windows.first?.setFrame(NSRect(x: f.midX - 490, y: f.midY - 320, width: 980, height: 640), display: true) }
                } else if args.contains("--big"), let screen = NSScreen.main {
                    DispatchQueue.main.async { NSApp.windows.first?.setFrame(screen.visibleFrame, display: true) }
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandMenu("Prototype") {
                Picker("Editor state", selection: Binding(get: { UserDefaults.standard.string(forKey: "editState") ?? "dirty" }, set: { UserDefaults.standard.set($0, forKey: "editState") })) {
                    ForEach(["clean", "dirty", "missing", "override", "conflict", "failed", "unreadable"], id: \.self) { Text($0).tag($0) }
                }
                Button("Editor A") { UserDefaults.standard.set("a", forKey: "editConcept") }.keyboardShortcut("1")
                Button("Editor B") { UserDefaults.standard.set("b", forKey: "editConcept") }.keyboardShortcut("2")
                Button("Editor C") { UserDefaults.standard.set("c", forKey: "editConcept") }.keyboardShortcut("3")
                Button("Light / Dark") { UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "lightMode"), forKey: "lightMode") }.keyboardShortcut("l")
            }
        }
    }
}

struct Root: View {
    @State private var page: Page = args.contains("--states") ? .states : args.contains("--instructions") ? .instructions : .usage
    @State private var provider = Provider.claude
    @AppStorage("editConcept") private var concept = "a"
    @AppStorage("lightMode") private var light = args.contains("--light")

    var body: some View {
        Group {
            switch page {
            case .usage: UsagePage()
            case .instructions: InstructionsPage(provider: $provider)
            case .states: StatesPage()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AmbientField(page: page == .instructions && concept == "b" ? .usage : page, provider: provider).ignoresSafeArea() }
        .frame(minWidth: 860, minHeight: 580)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 2) {
                    ForEach(Page.allCases) { item in
                        Button { page = item } label: {
                            Text(item.rawValue)
                                .font(.callout.weight(page == item ? .semibold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(page == item ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear), in: .capsule)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if page == .usage {
                ToolbarItem(placement: .primaryAction) {
                    Text("Updated 21:17").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {}
                }
            }
        }
        .preferredColorScheme(light ? .light : .dark)
        .animation(.smooth, value: page)
        .animation(.smooth, value: provider)
    }
}

/// Usage: Claude from one corner, Codex from the other. Instructions: only the selected provider, and quieter.
struct AmbientField: View {
    let page: Page
    let provider: Provider

    private var leading: Color { page == .usage ? claudeTint : provider.tint }
    private var trailing: Color { page == .usage ? codexTint : provider.tint }
    private var strength: Double { page == .usage ? 1 : 0.45 }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ], colors: [
                leading.opacity(0.75 * strength), leading.opacity(0.3 * strength), trailing.opacity(0.3 * strength),
                leading.opacity(0.45 * strength), .clear, trailing.opacity(0.5 * strength),
                leading.opacity(0.15 * strength), .clear, trailing.opacity(0.75 * strength),
            ])
        }
    }
}

// MARK: Usage

struct Limit: Identifiable {
    let name: String
    let percent: Int
    let reset: String
    var id: String { name }
    var isHigh: Bool { percent >= 80 }
}

struct UsagePage: View {
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ProviderColumn(provider: .claude, plan: "Max", account: "someone@example.com",
                           hero: Limit(name: "Weekly", percent: 62, reset: "resets Thu 03:00"),
                           others: [Limit(name: "Weekly · Fable", percent: 34, reset: "")],
                           footnote: nil)
            ProviderColumn(provider: .codex, plan: "Pro", account: "someone@example.com",
                           hero: Limit(name: "Weekly", percent: 18, reset: "resets Nov 12"),
                           others: [],
                           footnote: "61,863")
        }
        .frame(maxWidth: contentWidth)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProviderColumn: View {
    let provider: Provider
    let plan: String
    let account: String
    let hero: Limit
    let others: [Limit]
    let footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                logo(provider.logoName).resizable().scaledToFit().frame(width: 20, height: 20)
                Text(provider.rawValue).font(.title3.weight(.semibold))
                Spacer()
                Text(plan)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.fill.secondary, in: .capsule)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(hero.name).font(.headline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(hero.percent)")
                        .font(.system(size: 112, weight: .thin, design: .rounded))
                        .monospacedDigit()
                    Text("%").font(.system(size: 36, weight: .thin, design: .rounded))
                }
                Text(hero.reset).font(.callout.monospaced()).foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 0) {
                if others.isEmpty, let footnote {
                    HStack {
                        Text("Credits").font(.callout)
                        Spacer()
                        Text(footnote).font(.callout.monospaced()).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                } else {
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, limit in
                        if index > 0 { Divider() }
                        LimitRow(limit: limit)
                    }
                }
            }
            .frame(minHeight: 56, alignment: .top)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct LimitRow: View {
    let limit: Limit

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if limit.isHigh {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
                Text(limit.name).font(.callout)
                Spacer()
                if !limit.reset.isEmpty {
                    Text(limit.reset).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Text("\(limit.percent)%")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            Capsule().fill(.quaternary).frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(limit.isHigh ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                            .frame(width: geo.size.width * Double(limit.percent) / 100)
                    }
                }
        }
        .padding(.vertical, 10)
    }
}

// MARK: Instructions

let sampleClaude = """
# Working style

Reply in Vietnamese. Keep answers short.

## Git

- Never add Co-Authored-By to commits
- Branch first when on the default branch

## Verification

- Build, take a quick look, let CI do the rest
"""
let sampleCodex = """
# Global rules

Prefer small, reviewable changes.

## Style

- Match the code around you
"""

extension Provider {
    var fileName: String { self == .claude ? "CLAUDE.md" : "AGENTS.md" }
    var sample: String { self == .claude ? sampleClaude : sampleCodex }
}

/// Markdown styling that stays editable: headings and list markers only.
func styled(_ text: String, scaleHeadings: Bool, tint: Color) -> AttributedString {
    var result = AttributedString()
    for (index, line) in text.components(separatedBy: "\n").enumerated() {
        if index > 0 { result += AttributedString("\n") }
        let level = line.prefix { $0 == "#" }.count
        if level > 0 {
            var mark = AttributedString(String(line.prefix(level + 1)))
            var title = AttributedString(String(line.dropFirst(level + 1)))
            let size: CGFloat = scaleHeadings ? (level == 1 ? 22 : 16) : 13
            mark.font = .system(size: size, weight: .regular, design: .monospaced)
            mark.foregroundColor = tint
            title.font = .system(size: size, weight: .semibold, design: .monospaced)
            result += mark + title
        } else if line.hasPrefix("- ") {
            var mark = AttributedString("- ")
            var rest = AttributedString(String(line.dropFirst(2)))
            mark.font = .system(size: 13, design: .monospaced)
            mark.foregroundColor = tint
            rest.font = .system(size: 13, design: .monospaced)
            result += mark + rest
        } else {
            var plain = AttributedString(line)
            plain.font = .system(size: 13, design: .monospaced)
            result += plain
        }
    }
    return result
}

struct InstructionsPage: View {
    @Binding var provider: Provider
    @AppStorage("editConcept") private var concept = args.first { $0.hasPrefix("--edit=") }.map { String($0.dropFirst(7)) } ?? "a"

    var body: some View {
        switch concept {
        case "b": SheetsEditor(provider: $provider)
        case "c": WorkbenchEditor(provider: $provider)
        default: ManuscriptEditor(provider: $provider)
        }
    }
}

struct SaveCapsule: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(.orange).frame(width: 7, height: 7)
            Text("Unsaved changes").font(.callout)
            Button("Revert") {}.buttonStyle(.borderless)
            Button("Save") {}.buttonStyle(.glassProminent).keyboardShortcut("s")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

// A — Manuscript: no panel, the file sits on the colour field

struct ManuscriptEditor: View {
    @Binding var provider: Provider
    @AppStorage("editState") private var state = args.first { $0.hasPrefix("--state=") }.map { String($0.dropFirst(8)) } ?? "dirty"
    @State private var claude = styled(sampleClaude, scaleHeadings: true, tint: claudeTint)
    @State private var codex = styled(sampleCodex, scaleHeadings: true, tint: codexTint)
    @State private var empty = AttributedString()

    private var fileName: String { state == "override" ? "AGENTS.md" : provider.fileName }
    private var path: String { state == "override" ? "~/.codex/AGENTS.md" : provider.path }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(fileName).font(.system(size: 52, weight: .thin, design: .rounded))
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(Provider.allCases) { item in
                            Button { provider = item } label: {
                                logo(item.logoName).resizable().scaledToFit().frame(width: 20, height: 20)
                                    .frame(width: 38, height: 38)
                                    .background((state == "override" ? item == .codex : provider == item) ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(.clear), in: .circle)
                                    .contentShape(.circle)
                            }
                            .buttonStyle(.plain)
                            .help(item.rawValue)
                        }
                    }
                    .padding(4)
                    .glassEffect(.regular, in: .capsule)
                }
                HStack(spacing: 8) {
                    Text(path).font(.caption.monospaced())
                    Button("Show in Finder", systemImage: "folder") {}.labelStyle(.iconOnly).buttonStyle(.borderless)
                    Text("·")
                    Text("Applies to new sessions").font(.caption)
                }
                .foregroundStyle(.secondary)

                if state == "override" {
                    Label("Codex is using AGENTS.override.md, so it ignores this file.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                switch state {
                case "unreadable":
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "doc.badge.ellipsis").font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
                        Text("This file isn't plain text, so Agenty can't edit it.")
                        Button("Show in Finder") {}.buttonStyle(.glass)
                    }
                    .padding(.top, 24)
                    Spacer()
                case "missing":
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $empty).scrollContentBackground(.hidden).padding(.horizontal, -5)
                        Text("This file doesn't exist yet. Agenty creates it when you save.")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .allowsHitTesting(false)
                    }
                default:
                    TextEditor(text: state == "override" ? $codex : (provider == .claude ? $claude : $codex))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, -5)
                }
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .frame(maxWidth: .infinity)

            capsule.padding(.bottom, 24)
        }
    }

    @ViewBuilder private var capsule: some View {
        switch state {
        case "dirty":
            Capsule2(symbol: nil, message: "Unsaved changes", secondary: "Revert", primary: "Save")
        case "conflict":
            Capsule2(symbol: "exclamationmark.triangle.fill", message: "Changed outside Agenty", secondary: "Keep Mine", primary: "Reload")
        case "failed":
            Capsule2(symbol: "exclamationmark.triangle.fill", message: "Couldn't save: permission denied", secondary: nil, primary: "Try Again")
        default:
            EmptyView()
        }
    }
}

struct Capsule2: View {
    let symbol: String?
    let message: String
    let secondary: String?
    let primary: String

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(.orange)
            } else {
                Circle().fill(.orange).frame(width: 7, height: 7)
            }
            Text(message).font(.callout)
            if let secondary { Button(secondary) {}.buttonStyle(.borderless) }
            Button(primary) {}.buttonStyle(.glassProminent).keyboardShortcut("s")
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

// B — Sheets: both files side by side like the Usage cards, the active one grows

struct SheetsEditor: View {
    @Binding var provider: Provider
    @State private var claude = styled(sampleClaude, scaleHeadings: true, tint: claudeTint)
    @State private var codex = styled(sampleCodex, scaleHeadings: true, tint: codexTint)

    var body: some View {
        GeometryReader { geo in
            let total = min(geo.size.width - 48, contentWidth) - 16
            HStack(alignment: .top, spacing: 16) {
                sheet(.claude, text: $claude).frame(width: total * (provider == .claude ? 0.68 : 0.32))
                sheet(.codex, text: $codex).frame(width: total * (provider == .codex ? 0.68 : 0.32))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private func sheet(_ item: Provider, text: Binding<AttributedString>) -> some View {
        let active = provider == item
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                logo(item.logoName).resizable().scaledToFit().frame(width: 20, height: 20)
                Text(item.fileName).font(.title3.weight(.semibold))
                Spacer()
                if active { Text(item.path).font(.caption.monospaced()).foregroundStyle(.secondary) }
            }
            TextEditor(text: text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -5)
                .opacity(active ? 1 : 0.6)
                .disabled(!active)
            if active {
                HStack {
                    Text("Unsaved changes · applies to new sessions").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Revert") {}.buttonStyle(.glass)
                    Button("Save") {}.buttonStyle(.glassProminent).keyboardShortcut("s")
                }
            }
        }
        .padding(24)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture { provider = item }
    }
}

// C — Workbench: file tabs, line numbers, outline of the headings

struct WorkbenchEditor: View {
    @Binding var provider: Provider
    @State private var claude = styled(sampleClaude, scaleHeadings: false, tint: claudeTint)
    @State private var codex = styled(sampleCodex, scaleHeadings: false, tint: codexTint)

    private var lines: [String] { provider.sample.components(separatedBy: "\n") }
    private var headings: [(Int, String)] {
        lines.compactMap { line in
            let level = line.prefix { $0 == "#" }.count
            return level > 0 ? (level, String(line.dropFirst(level + 1))) : nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Provider.allCases) { item in
                    Button { provider = item } label: {
                        HStack(spacing: 8) {
                            logo(item.logoName).resizable().scaledToFit().frame(width: 15, height: 15)
                            Text(item.fileName).font(.callout.monospaced())
                            if item == .claude { Circle().fill(.orange).frame(width: 6, height: 6) }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(provider == item ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(.clear),
                                    in: UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.leading, 12)

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(lines.indices, id: \.self) { index in
                            Text("\(index + 1)").font(.system(size: 13, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.top, 16)
                    .frame(width: 44, alignment: .trailing)
                    TextEditor(text: provider == .claude ? $claude : $codex)
                        .scrollContentBackground(.hidden)
                        .padding(.top, 16)
                        .padding(.leading, 8)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Outline").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        ForEach(headings, id: \.1) { heading in
                            Text(heading.1)
                                .font(.callout)
                                .padding(.leading, CGFloat(heading.0 - 1) * 12)
                        }
                        Spacer()
                        Text("\(lines.count) lines").font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text("\(provider.sample.count) characters").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(width: 176, alignment: .leading)
                    .frame(maxHeight: .infinity)
                    .background(.fill.quaternary)
                }
                Divider()
                HStack(spacing: 8) {
                    Text(provider.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text("applies to new sessions").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Revert") {}.buttonStyle(.glass)
                    Button("Save") {}.buttonStyle(.glassProminent).keyboardShortcut("s")
                }
                .padding(12)
            }
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .frame(maxWidth: contentWidth)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: States (prototype only)

struct Shell<Content: View>: View {
    let provider: Provider
    var plan: String? = nil
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption).font(.caption.monospaced()).foregroundStyle(.secondary).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    logo(provider.logoName).resizable().scaledToFit().frame(width: 20, height: 20)
                    Text(provider.rawValue).font(.title3.weight(.semibold))
                    Spacer()
                    if let plan {
                        Text(plan)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.fill.secondary, in: .capsule)
                    }
                }
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct Hero: View {
    let name: String
    let percent: Int
    let reset: String
    var color: Color = .primary
    var symbol: String? = nil
    var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).foregroundStyle(color) }
                Text(name).font(.headline).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(percent)").font(.system(size: 96, weight: .thin, design: .rounded)).monospacedDigit()
                Text("%").font(.system(size: 30, weight: .thin, design: .rounded))
            }
            .foregroundStyle(color)
            Text(reset).font(.callout.monospaced()).foregroundStyle(.secondary)
        }
        .opacity(dimmed ? 0.55 : 1)
    }
}

/// Takes the hero's place when there is nothing to show.
struct Blocked: View {
    let symbol: String
    let message: String
    var action: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
            Text(message).font(.body)
            if let action { Button(action) {}.buttonStyle(.glass) }
            Spacer(minLength: 0)
        }
    }
}

struct InlineNotice: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.caption)
        }
    }
}

struct StatesPage: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 16, alignment: .top)], spacing: 20) {
                Shell(provider: .claude, plan: "Max", caption: "warning") {
                    Hero(name: "Weekly", percent: 84, reset: "resets Thu 03:00", color: .orange, symbol: "exclamationmark.triangle.fill")
                }
                Shell(provider: .claude, plan: "Max", caption: "critical") {
                    Hero(name: "Weekly", percent: 97, reset: "resets Thu 03:00", color: .red, symbol: "exclamationmark.octagon.fill")
                }
                Shell(provider: .codex, plan: "Pro", caption: "stale data, can't reach server") {
                    Hero(name: "Weekly", percent: 18, reset: "resets Nov 12", dimmed: true)
                    Label("Can't reach Codex — will retry", systemImage: "wifi.slash").font(.caption).foregroundStyle(.orange)
                }
                Shell(provider: .claude, plan: "Max", caption: "error with last data") {
                    InlineNotice(message: "Session expired — open Claude Code once")
                    Hero(name: "Weekly", percent: 62, reset: "resets Thu 03:00", dimmed: true)
                }
                Shell(provider: .claude, caption: "loading") {
                    VStack { Spacer(); ProgressView(); Spacer() }.frame(maxWidth: .infinity, minHeight: 130)
                }
                Shell(provider: .codex, plan: "Pro", caption: "no active limits") {
                    Blocked(symbol: "gauge.with.dots.needle.0percent", message: "No active limits")
                }
                Shell(provider: .claude, caption: "not signed in") {
                    Blocked(symbol: "person.crop.circle.badge.exclamationmark", message: "Not signed in — run `claude`")
                }
                Shell(provider: .codex, caption: "CLI not found") {
                    Blocked(symbol: "terminal", message: "Codex CLI not found", action: "Choose path…")
                }
                Shell(provider: .claude, caption: "keychain denied") {
                    Blocked(symbol: "lock", message: "Keychain access denied — allow Agenty to read “Claude Code-credentials”", action: "Retry")
                }
                Shell(provider: .claude, caption: "API changed") {
                    Blocked(symbol: "questionmark.diamond", message: "API format changed", action: "Report issue")
                }
            }
            .frame(maxWidth: contentWidth)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}
