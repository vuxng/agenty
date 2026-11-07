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
    @Test func listsRecursivelyOnlyWhenAsked() throws {
        let f = AgentTestFolder(); defer { f.clean() }
        for path in ["agents/a.md", "agents/sub/b.md", "agents/notes.txt", "agents/.hidden.md", "agents/.hidden/c.md"] { try f.write(path) }
        #expect(f.directory().files()?.map { $0.path } == ["agents/a.md", "agents/sub/b.md"].map { f.home.appendingPathComponent($0).path })
        #expect(f.directory(false).files()?.map(\.lastPathComponent) == ["a.md"])
    }
    @Test func missingFolderIsNil() throws {
        let f = AgentTestFolder(); defer { f.clean() }
        #expect(f.directory().files() == nil)
        try f.write("agents")
        #expect(f.directory().files() == nil)
    }
    @Test func followsSymlinks() throws {
        let f = AgentTestFolder(); defer { f.clean() }
        try f.write("target/a.md")
        try f.write("outside.md")
        try FileManager.default.createSymbolicLink(at: f.home.appendingPathComponent("target/link.md"), withDestinationURL: f.home.appendingPathComponent("outside.md"))
        try FileManager.default.createSymbolicLink(at: f.home.appendingPathComponent("agents"), withDestinationURL: f.home.appendingPathComponent("target"))
        for recursive in [false, true] {
            #expect(f.directory(recursive).files()?.map(\.path) == ["agents/a.md", "agents/link.md"].map { f.home.appendingPathComponent($0).path })
        }
    }
    @Test func displayPathUsesTilde() {
        let f = AgentTestFolder()
        #expect(f.directory().displayPath(of: f.home.appendingPathComponent(".claude/agents/x.md")) == "~/.claude/agents/x.md")
        let outside = URL(fileURLWithPath: f.home.path + "-other/x.md")
        #expect(f.directory().displayPath(of: outside) == outside.path)
    }
    @Test func emptyFolderIsEmpty() throws {
        let f = AgentTestFolder(); defer { f.clean() }
        try f.write("agents/notes.txt")
        #expect(f.directory().files() == [])
    }
}
