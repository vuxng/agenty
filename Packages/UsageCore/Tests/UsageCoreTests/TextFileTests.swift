import Foundation
import Testing
@testable import UsageCore

@Suite struct TextFileTests {
    @Test func missingFileReadsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.txt")
        let file = TextFile(url: url)
        #expect(file.url == url)
        #expect(try file.read() == nil)
    }

    @Test func writeCreatesParentDirectories() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                Issue.record(error)
            }
        }
        let file = TextFile(url: directory.appendingPathComponent("nested/parent/settings.txt"))
        #expect(!FileManager.default.fileExists(atPath: file.url.deletingLastPathComponent().path))
        try file.write("settings 📝\r\n")
        #expect(try Data(contentsOf: file.url) == Data("settings 📝\r\n".utf8))
        #expect(try file.read() == "settings 📝\r\n")
    }

    @Test func writeKeepsPermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: directory)
            } catch {
                Issue.record(error)
            }
        }
        let file = TextFile(url: directory.appendingPathComponent("settings.txt"))
        try Data("old".utf8).write(to: file.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        try file.write("new")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
        let mode = try #require(attributes[.posixPermissions] as? NSNumber).intValue
        #expect(mode == 0o600)
        #expect(try Data(contentsOf: file.url) == Data("new".utf8))
    }
}
