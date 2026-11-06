import Foundation
import Testing
@testable import UsageCore

@Suite @MainActor struct InstructionsDocumentTests {
    @Test func loadsContent() throws {
        try withTemporaryFile(content: "Instructions 📝\r\n") { file, document in
            document.refresh()
            #expect(document.file.url == file.url)
            #expect(document.draft == "Instructions 📝\r\n")
            #expect(document.fileExists)
            #expect(!document.isDirty)
            #expect(!document.hasConflict)
            #expect(document.loadError == nil)
            #expect(document.saveError == nil)
        }
    }

    @Test func missingIsCleanAndEmpty() throws {
        try withTemporaryFile(content: nil) { _, document in
            document.refresh()
            #expect(document.draft == "")
            #expect(!document.fileExists)
            #expect(!document.isDirty)
            #expect(!document.hasConflict)
            #expect(document.loadError == nil)
        }
    }

    @Test func dirtyAndRevert() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            document.draft = "draft"
            #expect(document.isDirty)
            document.revert()
            #expect(document.draft == "original")
            #expect(!document.isDirty)
            #expect(document.saveError == nil)
            let disk = try file.read()
            #expect(disk == "original")
        }
    }

    @Test func saveWritesAndCleans() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            document.draft = "saved 📝\r\n"
            document.save()
            let data = try Data(contentsOf: file.url)
            #expect(data == Data("saved 📝\r\n".utf8))
            #expect(document.draft == "saved 📝\r\n")
            #expect(!document.isDirty)
            #expect(document.fileExists)
            #expect(document.saveError == nil)
        }
    }

    @Test func saveCreatesMissingFile() throws {
        try withTemporaryFile(content: nil) { file, document in
            document.refresh()
            document.draft = "new"
            document.save()
            let disk = try file.read()
            #expect(disk == "new")
            #expect(document.fileExists)
            #expect(!document.isDirty)
            #expect(document.saveError == nil)
        }
    }

    @Test func cleanReloadsExternalChange() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            try file.write("external")
            document.refresh()
            #expect(document.draft == "external")
            #expect(!document.isDirty)
            #expect(!document.hasConflict)
            #expect(document.fileExists)
        }
    }

    @Test func dirtyFlagsConflict() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            document.draft = "draft"
            try file.write("external")
            document.refresh()
            #expect(document.hasConflict)
            #expect(document.draft == "draft")
            #expect(document.isDirty)
            document.refresh()
            #expect(document.hasConflict)
            #expect(document.draft == "draft")
        }
    }

    @Test func saveDuringConflictDoesNotWrite() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            document.draft = "draft"
            try file.write("external")
            // Save itself must discover the outside change.
            document.save()
            #expect(try file.read() == "external")
            #expect(document.hasConflict)
            #expect(document.draft == "draft")
            #expect(document.isDirty)
        }
    }

    @Test func keepMineThenSaveOverwrites() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            document.draft = "draft"
            try file.write("external")
            document.refresh()
            document.keepMine()
            #expect(!document.hasConflict)
            #expect(document.isDirty)
            #expect(document.draft == "draft")
            #expect(try file.read() == "external")
            document.save()
            #expect(try file.read() == "draft")
            #expect(!document.isDirty)
            #expect(document.saveError == nil)
        }
    }

    @Test func reloadDropsDraft() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            document.draft = "draft"
            try file.write("external")
            document.refresh()
            try file.write("latest external")
            document.reload()
            #expect(document.draft == "latest external")
            #expect(!document.hasConflict)
            #expect(!document.isDirty)
            #expect(document.fileExists)
            #expect(try file.read() == "latest external")
        }
    }

    @Test func conflictClearsWhenDiskReturns() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            document.draft = "draft"
            try file.write("external")
            document.refresh()
            #expect(document.hasConflict)
            try file.write("original")
            document.refresh()
            #expect(!document.hasConflict)
            #expect(document.draft == "draft")
            #expect(document.isDirty)
        }
    }

    @Test func deletedFileWithDraftIsConflict() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            document.draft = "draft"
            try FileManager.default.removeItem(at: file.url)
            document.refresh()
            #expect(document.hasConflict)
            #expect(!document.fileExists)
            document.save()
            #expect(try file.read() == nil)
            #expect(document.draft == "draft")
            #expect(document.isDirty)
            #expect(document.hasConflict)
        }
    }

    @Test func notUTF8SetsLoadError() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            document.draft = "draft"
            let invalid = Data([0xFF, 0xFE, 0x00])
            try invalid.write(to: file.url)
            document.refresh()
            #expect(document.loadError == .notText)
            document.save()
            #expect(try Data(contentsOf: file.url) == invalid)
            #expect(document.loadError == .notText)
            #expect(document.draft == "draft")
            #expect(document.isDirty)
            try file.write("original")
            document.refresh()
            #expect(document.loadError == nil)
            #expect(document.draft == "draft")
            #expect(!document.hasConflict)
        }
    }

    @Test func saveFailureKeepsDraft() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            document.draft = "draft"
            let parent = file.url.deletingLastPathComponent()
            defer {
                do {
                    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
                } catch {
                    Issue.record(error)
                }
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
            document.save()
            #expect(document.saveError != nil)
            #expect(document.loadError == nil)
            #expect(document.isDirty)
            #expect(document.draft == "draft")
            #expect(try file.read() == "original")

            document.revert()
            #expect(document.draft == "original")
            #expect(!document.isDirty)
            #expect(document.saveError == nil)

            document.draft = "retry"
            document.save()
            #expect(document.saveError != nil)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            document.save()
            #expect(document.saveError == nil)
            #expect(!document.isDirty)
            #expect(try file.read() == "retry")
        }
    }

    @Test func initializationDefersLoading() throws {
        try withTemporaryFile { file, document in
            #expect(document.draft == "")
            #expect(!document.fileExists)
            #expect(!document.isDirty)
            #expect(document.loadError == nil)
            document.draft = "typed before first load"
            document.save()
            #expect(document.hasConflict)
            #expect(document.draft == "typed before first load")
            let disk = try file.read()
            #expect(disk == "original")
        }
    }

    @Test func refreshUpdatesOverrideEvenOnLoadFailure() throws {
        try withTemporaryFile(provider: .codex) { file, document in
            let override = file.url.deletingLastPathComponent().appendingPathComponent("AGENTS.override.md")
            document.refresh()
            #expect(!document.isOverridden)
            try Data("override".utf8).write(to: override)
            try Data([0xFF]).write(to: file.url)
            document.refresh()
            #expect(document.isOverridden)
            #expect(document.loadError == .notText)
            #expect(document.draft == "original")
            try FileManager.default.removeItem(at: override)
            document.refresh()
            #expect(!document.isOverridden)
        }
    }

    @Test func missingAndEmptyAreDifferentDuringConflict() throws {
        try withTemporaryFile(content: nil) { file, document in
            document.refresh()
            document.draft = "draft"
            try file.write("")
            document.refresh()
            #expect(document.hasConflict)
            #expect(document.fileExists)
            document.reload()
            #expect(document.draft == "")
            #expect(!document.isDirty)
            document.draft = "draft"
            try FileManager.default.removeItem(at: file.url)
            document.refresh()
            #expect(document.hasConflict)
            #expect(!document.fileExists)
            document.reload()
            #expect(document.draft == "")
            #expect(!document.isDirty)
            #expect(!document.hasConflict)
            #expect(!document.fileExists)
        }
    }

    @Test func cleanDeletionReloadsAsMissing() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            try FileManager.default.removeItem(at: file.url)
            document.refresh()
            #expect(document.draft == "")
            #expect(!document.fileExists)
            #expect(!document.isDirty)
            #expect(!document.hasConflict)
        }
    }

    @Test func keepMineUsesLatestDiskAndStillChecksBeforeSave() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            document.draft = "draft"
            try file.write("external")
            document.refresh()
            try file.write("latest external")
            document.keepMine()
            document.refresh()
            #expect(!document.hasConflict)
            #expect(document.draft == "draft")
            try file.write("changed again")
            document.save()
            #expect(document.hasConflict)
            #expect(try file.read() == "changed again")
            #expect(document.draft == "draft")
        }
    }

    @Test func failedResolutionKeepsDraftAndBaseline() throws {
        try withTemporaryFile { file, document in
            document.refresh()
            document.draft = "draft"
            try file.write("external")
            document.refresh()
            try Data([0xFF]).write(to: file.url)
            document.keepMine()
            #expect(document.loadError == .notText)
            #expect(document.hasConflict)
            #expect(document.draft == "draft")
            document.reload()
            #expect(document.loadError == .notText)
            #expect(document.hasConflict)
            #expect(document.draft == "draft")
            document.revert()
            #expect(document.draft == "original")
        }
    }

    private func withTemporaryFile(
        content: String? = "original",
        provider: ProviderID = .claude,
        _ body: (InstructionsFile, InstructionsDocument) throws -> Void
    ) throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer {
            do {
                try FileManager.default.removeItem(at: home)
            } catch {
                Issue.record(error)
            }
        }
        let file = InstructionsFile(provider: provider, home: home)
        if let content { try file.write(content) }
        try body(file, InstructionsDocument(file: file))
    }
}
