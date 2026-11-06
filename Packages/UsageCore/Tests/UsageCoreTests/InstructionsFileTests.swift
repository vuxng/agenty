import Foundation
import Testing
@testable import UsageCore

@Suite struct InstructionsFileTests {
    @Test func grokHasNoInstructionsFile() async {
        await #expect(processExitsWith: .failure) {
            _ = InstructionsFile(provider: .grok, home: URL(filePath: "/unused"))
        }
    }

    @Test func pathsPerProvider() throws {
        try withTemporaryHome { home in
            let claude = InstructionsFile(provider: .claude, home: home)
            let codex = InstructionsFile(provider: .codex, home: home)
            #expect(claude.provider == .claude)
            #expect(codex.provider == .codex)
            #expect(claude.url == home.appendingPathComponent(".claude/CLAUDE.md"))
            #expect(codex.url == home.appendingPathComponent(".codex/AGENTS.md"))
            #expect(claude.fileName == "CLAUDE.md")
            #expect(codex.fileName == "AGENTS.md")
            #expect(claude.displayPath == "~/.claude/CLAUDE.md")
            #expect(codex.displayPath == "~/.codex/AGENTS.md")
        }
    }

    @Test func readExisting() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .claude, home: home)
            try createParent(of: file.url)
            try Data("Instructions 📝\n".utf8).write(to: file.url)
            #expect(try file.read() == "Instructions 📝\n")
        }
    }

    @Test func readMissing() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .claude, home: home)
            let text = try file.read()
            #expect(text == nil)
        }
    }

    @Test func readNotUTF8() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .claude, home: home)
            try createParent(of: file.url)
            try Data([0xFF, 0xFE, 0x00]).write(to: file.url)
            #expect(throws: InstructionsError.notText) { try file.read() }
        }
    }

    @Test func writeCreatesParents() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .claude, home: home)
            #expect(!FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path))
            try file.write("new instructions")
            #expect(try Data(contentsOf: file.url) == Data("new instructions".utf8))
        }
    }

    @Test func writeKeepsPermissions() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .claude, home: home)
            try createParent(of: file.url)
            try Data("old".utf8).write(to: file.url)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
            try file.write("new")
            let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            #expect(try Data(contentsOf: file.url) == Data("new".utf8))
        }
    }

    @Test func writeThroughSymlink() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .claude, home: home)
            let target = home.appendingPathComponent("target.md")
            let intermediate = home.appendingPathComponent("intermediate.md")
            try createParent(of: file.url)
            try Data("old".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(atPath: intermediate.path, withDestinationPath: target.path)
            try FileManager.default.createSymbolicLink(atPath: file.url.path, withDestinationPath: "../intermediate.md")
            try file.write("new")
            #expect(try Data(contentsOf: target) == Data("new".utf8))
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: file.url.path) == "../intermediate.md")
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: intermediate.path) == target.path)
        }
    }

    @Test func writeThroughDanglingSymlink() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .codex, home: home)
            let target = home.appendingPathComponent("nested/target.md")
            try createParent(of: file.url)
            try FileManager.default.createSymbolicLink(atPath: file.url.path, withDestinationPath: "../nested/target.md")
            #expect(!FileManager.default.fileExists(atPath: target.path))
            try file.write("new")
            #expect(try Data(contentsOf: target) == Data("new".utf8))
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: file.url.path) == "../nested/target.md")
        }
    }

    @Test func roundTripKeepsBytes() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .codex, home: home)
            try file.write("a\r\nb")
            #expect(try file.read() == "a\r\nb")
            #expect(try Data(contentsOf: file.url) == Data("a\r\nb".utf8))
        }
    }

    @Test func overrideAbsentEmptyOrFilled() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .codex, home: home)
            let override = home.appendingPathComponent(".codex/AGENTS.override.md")
            #expect(!file.isOverridden)
            try createParent(of: override)
            for text in ["", " \n"] {
                try Data(text.utf8).write(to: override)
                #expect(!file.isOverridden)
            }
            try Data("x".utf8).write(to: override)
            #expect(file.isOverridden)
        }
    }

    @Test func overrideClaudeAlwaysFalse() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .claude, home: home)
            #expect(!file.isOverridden)
            for path in [".claude/AGENTS.override.md", ".codex/AGENTS.override.md"] {
                let override = home.appendingPathComponent(path)
                try createParent(of: override)
                try Data("x".utf8).write(to: override)
            }
            #expect(!file.isOverridden)
        }
    }

    @Test func readFailureIncludesSystemReason() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .claude, home: home)
            try FileManager.default.createDirectory(at: file.url, withIntermediateDirectories: true)
            do {
                _ = try file.read()
                Issue.record("Expected a read failure for a directory")
            } catch {
                guard case InstructionsError.readFailed(let reason) = error else {
                    Issue.record("Unexpected error: \(error)")
                    return
                }
                #expect(!reason.isEmpty)
            }
        }
    }

    @Test func writeFailureIncludesSystemReason() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .claude, home: home)
            try Data("blocked parent".utf8).write(to: home.appendingPathComponent(".claude"))
            do {
                try file.write("new")
                Issue.record("Expected a write failure for a non-directory parent")
            } catch {
                guard case InstructionsError.writeFailed(let reason) = error else {
                    Issue.record("Unexpected error: \(error)")
                    return
                }
                #expect(!reason.isEmpty)
            }
        }
    }

    @Test func writeRejectsSymlinkCycle() throws {
        try withTemporaryHome { home in
            let file = InstructionsFile(provider: .claude, home: home)
            try createParent(of: file.url)
            try FileManager.default.createSymbolicLink(atPath: file.url.path, withDestinationPath: "CLAUDE.md")
            do {
                try file.write("new")
                Issue.record("Expected a write failure for a symlink cycle")
            } catch {
                guard case InstructionsError.writeFailed(let reason) = error else {
                    Issue.record("Unexpected error: \(error)")
                    return
                }
                #expect(!reason.isEmpty)
            }
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: file.url.path) == "CLAUDE.md")
        }
    }

    private func createParent(of url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private func withTemporaryHome(_ body: (URL) throws -> Void) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: home)
            } catch {
                Issue.record(error)
            }
        }
        try body(home)
    }
}
