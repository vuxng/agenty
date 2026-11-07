import Foundation
import Testing
@testable import UsageCore

@Suite struct MarkdownAgentParserTests {
    private func parse(_ text: String) -> AgentDefinition? {
        MarkdownAgentParser.parse(text, url: URL(filePath: "/tmp/a.md"))
    }

    @Test func parsesProjectAgentWithHooks() throws {
        let text = #"""
        ---
        name: agenty
        description: Main chat for the agenty project. Use only when the user starts a session with `claude --agent agenty`.
        hooks:
          SessionStart:
            - hooks:
                - type: command
                  command: jq -n --arg t agenty --rawfile c "$HOME/.claude/project-hq.md" '{hookSpecificOutput:{hookEventName:"SessionStart",sessionTitle:$t,additionalContext:$c}}'
        ---

        """#
        let agent = try #require(parse(text))
        #expect(agent.name == "agenty")
        #expect(agent.description == "Main chat for the agenty project. Use only when the user starts a session with `claude --agent agenty`.")
        #expect(agent.model == nil)
        #expect(agent.prompt == nil)
        #expect(!agent.isLineScanned)
        let hooks = #"""
        SessionStart:
          - hooks:
              - type: command
                command: jq -n --arg t agenty --rawfile c "$HOME/.claude/project-hq.md" '{hookSpecificOutput:{hookEventName:"SessionStart",sessionTitle:$t,additionalContext:$c}}'
        """#
        #expect(agent.fields == [AgentField(key: "hooks", value: .block(hooks))])
    }
    @Test func keepsFileOrderAndRawScalars() throws {
        let agent = try #require(parse("---\nname: reviewer\ndescription: Reviews code\nmodel: sonnet\ntools: [Read, Grep]\nbackground: yes\nmaxTurns: 123\npermissionMode: plan\n---\n\n# Reviewer\n- one\n"))
        #expect(agent.model == "sonnet")
        #expect(agent.fields == [AgentField(key: "tools", value: .text("Read, Grep")), AgentField(key: "background", value: .text("yes")), AgentField(key: "maxTurns", value: .text("123")), AgentField(key: "permissionMode", value: .text("plan"))])
        #expect(agent.prompt == "# Reviewer\n- one")
    }
    @Test func inheritIsSessionModel() throws {
        let agent = try #require(parse("---\nname: x\nmodel: inherit\n---"))
        #expect(agent.model == nil)
        #expect(agent.fields.isEmpty)
    }
    @Test func foldedDescription() {
        #expect(parse("---\nname: x\ndescription: >\n  Line one\n  line two\n---")?.description == "Line one line two")
    }
    @Test func literalScalarIsBlock() {
        #expect(parse("---\nname: x\ninitialPrompt: |\n  Hello\n  World\n---")?.fields == [AgentField(key: "initialPrompt", value: .block("Hello\nWorld"))])
    }
    @Test func sequenceOfMappingsIsBlock() {
        #expect(parse("---\nname: x\nskills:\n  - name: a\n    enabled: false\n---")?.fields == [AgentField(key: "skills", value: .block("- name: a\n  enabled: false"))])
    }
    @Test func flowMappingIsBlockFromSameLine() {
        #expect(parse("---\nname: x\nmcpServers: {a: {command: x}}\n---")?.fields == [AgentField(key: "mcpServers", value: .block("{a: {command: x}}"))])
    }
    @Test func unquotedColonFallsBackToLineScan() throws {
        let agent = try #require(parse("---\nname: hunter\ndescription: Use when: things break\nhooks:\n  Stop: []\n---\n"))
        #expect(agent.isLineScanned)
        #expect(agent.description == "Use when: things break")
        #expect(agent.fields == [AgentField(key: "hooks", value: .block("Stop: []"))])
    }
    @Test func lineScanStripsQuotes() throws {
        let agent = try #require(parse("---\nname: \"x\"\nmodel: 'opus'\ndescription: Use when: things break\n---"))
        #expect(agent.isLineScanned)
        #expect(agent.name == "x")
        #expect(agent.model == "opus")
    }
    @Test func skipsDocsAndNamelessFiles() {
        for text in ["# Notes\n", "---\ndescription: d\n---", "---\nname: \"\"\n---"] {
            #expect(parse(text) == nil)
        }
    }
    @Test func emptyBodyHasNoPrompt() {
        #expect(parse("---\nname: x\n---\n\n")?.prompt == nil)
    }
    @Test func handlesBOMAndCRLF() throws {
        let agent = try #require(parse("\u{FEFF}---\r\nname: x\r\ndescription: d\r\n---\r\nBody\r\n"))
        #expect(agent.name == "x")
        #expect(agent.prompt == "Body")
    }
    @Test func unreadableUsesFilenameAndEmptyContent() {
        let url = URL(filePath: "/tmp/a.md")
        let agent = AgentDefinition.unreadable(url: url, error: .notText)
        #expect(agent.id == url && agent.name == "a")
        #expect(agent.description == nil && agent.model == nil && agent.prompt == nil)
        #expect(agent.fields.isEmpty && !agent.isLineScanned)
        #expect(agent.readError == .notText)
    }
}
