import Foundation
import Testing
import UsageCore

@Suite struct CodexConfigIntegrationTests {
    private static let executable: String? = {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin").path,
               "/opt/homebrew/bin", "/usr/local/bin"]
        return paths.map { URL(filePath: $0).appending(path: "codex").path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    @Test(.enabled(if: Self.executable != nil))
    func batchWritePreservesUnrelatedTOML() async throws {
        let executable = try #require(Self.executable)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let codexHome = home.appending(path: ".codex")
        defer { try? FileManager.default.removeItem(at: home) }
        let locator = CLILocator(home: home, shell: FakeShell(result: nil))
        let backend = CodexConfigBackend(locator: locator, pathOverride: { executable }, runner: SubprocessRunner(),
                                          clientVersion: "0.1.0", home: home, codexHome: codexHome)
        try backend.file.write("""
        # Preserve this comment
        model = "gpt-5.4"
        unknown_future_key = 42

        [desktop]
        theme = "system"

        """)
        let snapshot = try await backend.load()
        #expect(snapshot.version != nil)
        _ = try await backend.save([
            ConfigEdit(path: ["model"], value: .string("gpt-5.4-mini")),
            ConfigEdit(path: ["plugins", "x.y@agenty-test", "enabled"], value: .bool(true)),
        ], version: snapshot.version)
        let text = try #require(try backend.file.read())
        #expect(text.contains("# Preserve this comment"))
        #expect(text.contains("[desktop]"))
        #expect(text.contains("theme = \"system\""))
        #expect(text.contains("unknown_future_key = 42"))
        #expect(text.contains("model = \"gpt-5.4-mini\""))
        #expect(text.contains("[plugins.\"x.y@agenty-test\"]"))
        #expect(text.contains("enabled = true"))
    }
}
