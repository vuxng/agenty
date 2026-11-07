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
    @Test func indentedSeparatorStaysInsideLiteralScalar() throws {
        let agent = try #require(parse("---  \nname: x\ninitialPrompt: |\n  hello\n  ---\n  world\n--- \nBody"))
        #expect(agent.fields == [AgentField(key: "initialPrompt", value: .block("hello\n---\nworld"))])
        #expect(agent.prompt == "Body")
        #expect(!agent.isLineScanned)
        #expect(parse("  ---\nname: x\n---") == nil)
    }
    @Test func columnZeroCommentPreservesNestedMapping() throws {
        let agent = try #require(parse("---\nname: x\nhooks:\n  Start: []\n# comment\n  Stop: []\ntools: Read\n---"))
        #expect(agent.fields == [
            AgentField(key: "hooks", value: .block("  Start: []\n# comment\n  Stop: []")),
            AgentField(key: "tools", value: .text("Read")),
        ])
        #expect(!agent.isLineScanned)
    }
    @Test func quotedScalarPreservesTrailingWhitespace() throws {
        let agent = try #require(parse("---\nname: x\nsuffix: \"value  \"\n---"))
        #expect(agent.fields == [AgentField(key: "suffix", value: .text("value  "))])
        #expect(!agent.isLineScanned)
    }
    @Test func sequenceOfMappingsIsBlock() {
        #expect(parse("---\nname: x\nskills:\n  - name: a\n    enabled: false\n---")?.fields == [AgentField(key: "skills", value: .block("- name: a\n  enabled: false"))])
    }
    @Test func flowMappingIsBlockFromSameLine() {
        #expect(parse("---\nname: x\nmcpServers: {a: {command: x}}\n---")?.fields == [AgentField(key: "mcpServers", value: .block("{a: {command: x}}"))])
    }
    @Test(arguments: [
        ("skills", "- name: auditing\n  enabled: true"),
        ("mcpServers", "- local:\n    command: server"),
    ])
    func columnZeroSequenceKeepsEntireBlock(key: String, block: String) throws {
        let agent = try #require(parse("---\nname: x\n\(key):\n\(block)\nmodel: sonnet\n---"))
        #expect(!agent.isLineScanned)
        #expect(agent.fields == [AgentField(key: key, value: .block(block))])
        #expect(agent.model == "sonnet")
    }
    @Test func multilineFlowMappingKeepsColumnZeroClosingBrace() throws {
        let agent = try #require(parse("---\nname: x\nmcpServers: {\n  local: {command: server}\n}\ntools: Read\n---"))
        #expect(!agent.isLineScanned)
        #expect(agent.fields == [
            AgentField(key: "mcpServers", value: .block("{\n  local: {command: server}\n}")),
            AgentField(key: "tools", value: .text("Read")),
        ])
    }
    @Test func lineScanKeepsColumnZeroSequenceUntilNextKey() throws {
        let agent = try #require(parse("---\nname: x\ndescription: Use when: needed\ntools:\n- Read\n# comment\n- Grep\npermissionMode: plan\n---"))
        #expect(agent.isLineScanned)
        #expect(agent.fields == [
            AgentField(key: "tools", value: .block("- Read\n# comment\n- Grep")),
            AgentField(key: "permissionMode", value: .text("plan")),
        ])
    }
    @Test(arguments: [false, true])
    func frontmatterPromptRemainsAnOrdinaryField(lineScanned: Bool) throws {
        let description = lineScanned ? "Use when: needed" : "Description"
        let agent = try #require(parse("---\nname: x\ndescription: \(description)\nprompt: Header prompt\n---\nBody prompt"))
        #expect(agent.isLineScanned == lineScanned)
        #expect(agent.fields == [AgentField(key: "prompt", value: .text("Header prompt"))])
        #expect(agent.prompt == "Body prompt")
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
