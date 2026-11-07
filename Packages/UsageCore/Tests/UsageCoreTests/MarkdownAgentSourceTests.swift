import Foundation
import Testing
@testable import UsageCore

@Suite struct MarkdownAgentSourceTests {
    @Test func claudeListsSortedAgentsAndSkipsDocs() async throws {
        let f = AgentTestFolder(); defer { f.clean() }
        for (path, name) in [("zeta.md", "zeta"), ("Alpha.md", "alpha"), ("sub/beta.md", "beta")] {
            try f.write(".claude/agents/" + path, "---\nname: \(name)\n---\n")
        }
        for path in ["README.md", ".DS_Store", "notes.txt"] { try f.write(".claude/agents/" + path, "documentation") }
        let source = MarkdownAgentSource.claude(home: f.home)
        #expect(source.provider == .claude)
        let listing = try await source.load()
        #expect(listing.folderExists)
        #expect(listing.agents.map(\.name) == ["alpha", "beta", "zeta"])
        #expect(!listing.usesClaudeAgents)
    }
    @Test func duplicateNamesAreBothListed() async throws {
        let f = AgentTestFolder(); defer { f.clean() }
        try f.write(".claude/agents/sub/a2.md")
        try f.write(".claude/agents/a.md")
        let listing = try await MarkdownAgentSource.claude(home: f.home).load()
        #expect(listing.agents.map(\.name) == ["same", "same"])
        #expect(listing.agents.map(\.url) == [".claude/agents/a.md", ".claude/agents/sub/a2.md"].map { f.home.appendingPathComponent($0) })
        #expect(Set(listing.agents.map(\.id)).count == 2)
    }
    @Test func nonTextFileIsUnreadableAgent() async throws {
        let f = AgentTestFolder(); defer { f.clean() }
        try f.write(".claude/agents/bad.md")
        try Data([0xFF, 0xFE, 0x00]).write(to: f.home.appendingPathComponent(".claude/agents/bad.md"))
        let listing = try await MarkdownAgentSource.claude(home: f.home).load()
        #expect(listing.agents.map(\.name) == ["bad"])
        #expect(listing.agents.first?.readError == .notText)
    }
    @Test func grokReadsTopLevelAndFlagsClaudeAgents() async throws {
        let f = AgentTestFolder(); defer { f.clean() }
        try f.write(".grok/agents/top.md", "---\nname: top\n---\n")
        try f.write(".grok/agents/sub/nested.md")
        try f.write(".claude/agents/c.md")
        let source = MarkdownAgentSource.grok(home: f.home)
        #expect(source.provider == .grok)
        let listing = try await source.load()
        #expect(listing.agents.map(\.name) == ["top"])
        #expect(listing.usesClaudeAgents)
        try FileManager.default.removeItem(at: f.home.appendingPathComponent(".claude/agents/c.md"))
        try f.write(".claude/agents/sub/c.md")
        #expect(try await source.load().usesClaudeAgents == false)
    }
    @Test func missingFolder() async throws {
        let f = AgentTestFolder()
        for source in [MarkdownAgentSource.claude(home: f.home), .grok(home: f.home)] {
            let listing = try await source.load()
            #expect(!listing.folderExists)
            #expect(listing.agents == [])
        }
    }
}
