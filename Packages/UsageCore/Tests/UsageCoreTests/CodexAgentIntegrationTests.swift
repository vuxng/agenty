import Foundation
import Testing
import UsageCore

@Suite struct CodexAgentIntegrationTests {
    private static let executable: String? = {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin").path,
               "/opt/homebrew/bin", "/usr/local/bin"]
        return paths.map { URL(filePath: $0).appending(path: "codex").path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    @Test(.enabled(if: Self.executable != nil))
    func readsAgentFilesThroughRealCodex() async throws {
        let executable = try #require(Self.executable)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appending(path: ".codex/agents")
        try TextFile(url: folder.appending(path: "broken.toml")).write("name = \"a\"\ndescription = \"unterminated\n")
        try TextFile(url: folder.appending(path: "reviewer.toml")).write("""
        name = "reviewer"
        developer_instructions = "# Hi\\n- one\\n"
        unknown_future_key = "kept"

        [features]
        apps = false

        """)
        let source = CodexAgentSource(locator: CLILocator(home: home, shell: FakeShell(result: nil)),
                                      pathOverride: { executable }, runner: SubprocessRunner(),
                                      clientVersion: "0.1.0", home: home)
        let listing = try await source.load()
        #expect(listing.agents.count == 2)
        let broken = try #require(listing.agents.first { $0.url.lastPathComponent == "broken.toml" })
        guard case .failed(let message) = broken.readError else { Issue.record("Expected invalid TOML"); return }
        #expect(message.contains("broken.toml:"))
        #expect(!message.contains("agenty-agents-"))
        let reviewer = try #require(listing.agents.first { $0.name == "reviewer" })
        #expect(reviewer.readError == nil)
        #expect(reviewer.prompt == "# Hi\n- one")
        #expect(reviewer.fields.first { $0.key == "features" }?.value == .block("{\n  \"apps\": false\n}"))
        #expect(reviewer.fields.first { $0.key == "unknown_future_key" }?.value == .text("kept"))
    }
}
