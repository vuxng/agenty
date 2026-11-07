import Foundation
import UsageCore

struct PreviewUsageProvider: UsageProvider {
    let id: ProviderID
    let result: Result<UsageSnapshot, UsageError>

    func fetch() async throws(UsageError) -> UsageSnapshot {
        try result.get()
    }
}

@MainActor
func previewStore(_ results: [ProviderID: Result<UsageSnapshot, UsageError>]) async -> UsageStore {
    let providers = results.map { PreviewUsageProvider(id: $0.key, result: $0.value) }
    let store = UsageStore(
        providers: providers,
        configuration: StoreConfiguration(enabled: Set(results.keys)),
        defaults: UserDefaults(suiteName: "io.github.vuxng.Agenty.preview") ?? .standard
    )
    await store.refreshAll()
    return store
}

extension UsageSnapshot {
    static func preview(_ provider: ProviderID, percent: Double, plan: String? = "Pro") -> UsageSnapshot {
        UsageSnapshot(
            provider: provider,
            plan: plan,
            windows: [UsageWindow(kind: .weekly, usedPercent: percent, resetsAt: Date().addingTimeInterval(86_400))],
            credits: nil,
            fetchedAt: Date()
        )
    }
}

struct PreviewAgentSource: AgentSource {
    let provider: ProviderID
    let result: Result<AgentListing, AgentLoadError>

    var directory: AgentDirectory {
        let home = URL(fileURLWithPath: "/tmp/agenty-agents-preview", isDirectory: true)
        return AgentDirectory(url: home.appendingPathComponent(".\(provider.rawValue)/agents"),
                              home: home, fileExtension: provider == .codex ? "toml" : "md",
                              recursive: provider != .grok)
    }

    func load() async throws(AgentLoadError) -> AgentListing {
        try result.get()
    }

    static let claudeListing = AgentListing(folderExists: true, agents: [
        agent("code-reviewer", description: "Reviews changes for correctness and clarity.", model: "sonnet"),
        agent("debugger", description: "Finds the cause of failing tests and unexpected behavior.", model: "opus"),
        agent("docs-writer", description: "Writes clear documentation and examples.", model: nil),
        agent("planner", description: "Breaks down work into small implementation steps.", model: "inherit"),
        agent("researcher", description: "Checks sources and summarizes findings.", model: "haiku"),
        agent("test-runner", description: nil, model: nil),
    ])

    static let hooksAgent = AgentDefinition(
        url: URL(fileURLWithPath: "/tmp/agenty-agents-preview/.claude/agents/agenty.md"),
        name: "agenty",
        description: "Main chat for the agenty project. Use only when the user starts a session with `claude --agent agenty`.",
        model: nil,
        fields: [AgentField(key: "hooks", value: .block(#"""
        SessionStart:
          - hooks:
              - type: command
                command: jq -n --arg t agenty --rawfile c "$HOME/.claude/project-hq.md" '{hookSpecificOutput:{hookEventName:"SessionStart",sessionTitle:$t,additionalContext:$c}}'
        """#))],
        prompt: nil
    )

    static let promptAgent = AgentDefinition(
        url: URL(fileURLWithPath: "/tmp/agenty-agents-preview/.claude/agents/code-reviewer.md"),
        name: "code-reviewer", description: "Reviews changes for correctness and clarity.", model: "sonnet",
        fields: [
            AgentField(key: "tools", value: .text("Read, Grep, Glob")),
            AgentField(key: "permissionMode", value: .text("plan")),
            AgentField(key: "maxTurns", value: .text("12")),
        ],
        prompt: """
        # Code reviewer
        Review the changes and explain what needs attention.

        ## Review checklist
        - Check correctness and error handling.
        - Keep feedback specific and actionable.

        > Include file paths and line numbers for findings.
        """
    )

    static let lineScannedAgent = AgentDefinition(
        url: URL(fileURLWithPath: "/tmp/agenty-agents-preview/.claude/agents/hunter.md"),
        name: "hunter", description: "Use when: things break", model: "inherit",
        fields: [AgentField(key: "hooks", value: .block("Stop: []"))],
        prompt: nil, isLineScanned: true
    )

    static let unreadableAgent = AgentDefinition.unreadable(
        url: URL(fileURLWithPath: "/tmp/agenty-agents-preview/.claude/agents/unreadable.md"),
        error: .notText
    )

    private static func agent(_ name: String, description: String?, model: String?) -> AgentDefinition {
        AgentDefinition(url: URL(fileURLWithPath: "/tmp/agenty-agents-preview/.claude/agents/\(name).md"),
                        name: name, description: description, model: model, fields: [], prompt: nil)
    }
}
