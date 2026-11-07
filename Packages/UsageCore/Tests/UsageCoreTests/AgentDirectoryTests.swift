import Foundation
import Testing
@testable import UsageCore

struct AgentTestFolder {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    func write(_ path: String, _ text: String = "---\nname: same\n---\n") throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func clean() { try? FileManager.default.removeItem(at: home) }
    func directory(_ recursive: Bool = true) -> AgentDirectory {
        AgentDirectory(url: home.appendingPathComponent("agents"), home: home, fileExtension: "md", recursive: recursive)
    }
}

@Suite struct AgentDirectoryTests {
    @Test(arguments: [false, true]) func unreadableFolderThrows(recursive: Bool) throws {
        let f = AgentTestFolder(); defer { f.clean() }
        try f.write("agents/a.md")
        let folder = f.home.appendingPathComponent("agents")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        #expect(throws: AgentLoadError.self) { try f.directory(recursive).files() }
    }
    @Test func recursiveFailureThrows() throws {
        let f = AgentTestFolder(); defer { f.clean() }
        try f.write("agents/sub/a.md")
        let folder = f.home.appendingPathComponent("agents/sub")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        #expect(throws: AgentLoadError.self) { try f.directory().files() }
    }

    @Test func listsRecursivelyOnlyWhenAsked() throws {
        let f = AgentTestFolder(); defer { f.clean() }
        for path in ["agents/a.md", "agents/sub/b.md", "agents/notes.txt", "agents/.hidden.md", "agents/.hidden/c.md"] { try f.write(path) }
        #expect(try f.directory().files()?.map { $0.path } == ["agents/a.md", "agents/sub/b.md"].map { f.home.appendingPathComponent($0).path })
        #expect(try f.directory(false).files()?.map(\.lastPathComponent) == ["a.md"])
    }
    @Test func missingFolderIsNil() throws {
        let f = AgentTestFolder(); defer { f.clean() }
        #expect(try f.directory().files() == nil)
        try f.write("agents")
        #expect(try f.directory().files() == nil)
    }
    @Test func followsSymlinks() throws {
        let f = AgentTestFolder(); defer { f.clean() }
        try f.write("target/a.md")
        try f.write("outside.md")
        try FileManager.default.createSymbolicLink(at: f.home.appendingPathComponent("target/link.md"), withDestinationURL: f.home.appendingPathComponent("outside.md"))
        try FileManager.default.createSymbolicLink(at: f.home.appendingPathComponent("agents"), withDestinationURL: f.home.appendingPathComponent("target"))
        for recursive in [false, true] {
            #expect(try f.directory(recursive).files()?.map(\.path) == ["agents/a.md", "agents/link.md"].map { f.home.appendingPathComponent($0).path })
        }
    }
    @Test func displayPathUsesTilde() {
        let f = AgentTestFolder()
        #expect(try f.directory().displayPath(of: f.home.appendingPathComponent(".claude/agents/x.md")) == "~/.claude/agents/x.md")
        let outside = URL(fileURLWithPath: f.home.path + "-other/x.md")
        #expect(try f.directory().displayPath(of: outside) == outside.path)
    }
    @Test func emptyFolderIsEmpty() throws {
        let f = AgentTestFolder(); defer { f.clean() }
        try f.write("agents/notes.txt")
        #expect(try f.directory().files() == [])
    }
}
