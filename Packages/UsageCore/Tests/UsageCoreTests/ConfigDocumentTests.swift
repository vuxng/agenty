import Foundation
import Testing
@testable import UsageCore

@Suite @MainActor struct ConfigDocumentTests {
    private let permission: ConfigPath = ["permissions", "defaultMode"]
    private let effort = EffortSetting(path: ["effort"], modelName: nil, levels: nil)

    @Test func refreshLoadsConfig() async throws {
        try await withDocument { backend, document in
            #expect(document.config == nil)
            #expect(document.mode == .controls)
            await document.refresh()
            #expect(document.config == Self.config())
            #expect(document.loadError == nil)
            #expect(document.diskText == "original")
            #expect(!document.isLoading)
            #expect(await backend.loadCount == 1)
        }
    }

    @Test func loadFailureIsReported() async throws {
        try await withDocument { backend, document in
            await backend.setLoadResult(.failure(.invalidFile("broken")))
            await document.refresh()
            #expect(document.loadError == .invalidFile("broken"))
            #expect(document.config == nil)
            #expect(!document.isLoading)
        }
    }

    @Test func brokenFileStillOpensInFileMode() async throws {
        try await withDocument(content: "{broken") { backend, document in
            await backend.setLoadResult(.failure(.invalidFile("broken")))
            await document.refresh()
            #expect(document.diskText == "{broken")
            #expect(document.fileDraft == "{broken")
            #expect(document.switchMode(to: .file))
            document.fileDraft = "{}"
            await backend.setLoadResult(.success(.init(config: Self.config(), version: "repaired")))
            await document.save()
            #expect(await backend.writes == ["{}"])
            let saved = try backend.file.read()
            #expect(saved == "{}")
            #expect(document.diskText == "{}")
            #expect(document.fileDraft == "{}")
            #expect(!document.isDirty)
            #expect(document.loadError == nil)
        }
    }

    @Test func editBackToDiskValueClearsDirty() async throws {
        try await withDocument { _, document in
            await document.refresh()
            document.set(.bool(true), at: ["fast"])
            #expect(document.isDirty)
            #expect(document.value(at: ["fast"]) == .bool(true))
            document.set(.bool(false), at: ["fast"])
            #expect(!document.isDirty)
            #expect(document.edits.isEmpty)
        }
    }

    @Test func manualEqualsUnsetAlias() async throws {
        try await withDocument(config: Self.config(values: [permission: .string("default")])) { _, document in
            await document.refresh()
            document.set(nil, at: permission)
            #expect(document.edits.isEmpty)
            document.set(.string("manual"), at: permission)
            #expect(!document.isDirty)
        }
    }

    @Test func revertDropsEdits() async throws {
        try await withDocument { _, document in
            await document.refresh()
            document.selectModel("basic")
            #expect(document.notice == .effortReset)
            document.revert()
            #expect(document.edits.isEmpty)
            #expect(document.notice == nil)
            #expect(document.switchMode(to: .file))
            document.fileDraft = "draft"
            document.revert()
            #expect(document.fileDraft == "original")
            #expect(!document.isDirty)
        }
    }

    @Test func saveSendsOnlyEditsWithVersion() async throws {
        try await withDocument { backend, document in
            await document.refresh()
            document.set(.bool(true), at: ["fast"])
            await backend.setSaveResult(.success(.init(overrideMessage: "Managed setting")))
            await document.save()
            #expect(await backend.saveCalls == [.init(edits: [.init(path: ["fast"], value: .bool(true))], version: "v1")])
            #expect(document.edits.isEmpty)
            #expect(!document.isSaving)
            #expect(document.notice == .overridden("Managed setting"))
            #expect(await backend.loadCount == 2)
        }
    }

    @Test func unknownValueIsNotEdited() async throws {
        try await withDocument(config: Self.config(values: [permission: .string("delegate")])) { backend, document in
            await document.refresh()
            document.set(.bool(true), at: ["fast"])
            #expect(document.value(at: permission) == .string("delegate"))
            await document.save()
            #expect(await backend.saveCalls.first?.edits == [.init(path: ["fast"], value: .bool(true))])
        }
    }

    @Test func saveFailureKeepsDraft() async throws {
        try await withDocument { backend, document in
            await document.refresh()
            document.set(.bool(true), at: ["fast"])
            await backend.setSaveResult(.failure(.writeFailed("denied")))
            await document.save()
            #expect(document.saveError == .writeFailed("denied"))
            #expect(document.edits == [.init(path: ["fast"], value: .bool(true))])
            #expect(!document.isSaving)
            #expect(await backend.loadCount == 1)
        }
    }

    @Test func conflictOnSaveSetsFlag() async throws {
        try await withDocument { backend, document in
            await document.refresh()
            document.set(.bool(true), at: ["fast"])
            await backend.setSaveResult(.failure(.conflict))
            await document.save()
            #expect(document.hasConflict)
            #expect(document.saveError == nil)
            #expect(document.edits == [.init(path: ["fast"], value: .bool(true))])
        }
    }

    @Test func keepMineReappliesOnlyEdits() async throws {
        try await withDocument { backend, document in
            await document.refresh()
            document.set(.bool(true), at: ["fast"])
            try backend.file.write("external")
            await backend.setLoadResult(.success(.init(config: Self.config(values: [permission: .string("delegate")]), version: "v2")))
            await document.refresh()
            #expect(document.hasConflict)
            await document.keepMine()
            #expect(!document.hasConflict)
            #expect(document.value(at: permission) == .string("delegate"))
            #expect(document.value(at: ["fast"]) == .bool(true))
            await document.save()
            #expect(await backend.saveCalls == [.init(edits: [.init(path: ["fast"], value: .bool(true))], version: "v2")])
        }
    }

    @Test func keepMineInFileModeKeepsDraft() async throws {
        try await withDocument { backend, document in
            await document.refresh()
            #expect(document.switchMode(to: .file))
            document.fileDraft = "mine"
            try backend.file.write("external")
            await document.refresh()
            #expect(document.hasConflict)
            await document.keepMine()
            #expect(document.fileDraft == "mine")
            #expect(document.diskText == "external")
            #expect(!document.hasConflict)
            await document.save()
            #expect(await backend.writes == ["mine"])
            #expect(!document.hasConflict)
            #expect(!document.isDirty)
        }
    }

    @Test func reloadDropsEdits() async throws {
        try await withDocument { backend, document in
            await document.refresh()
            document.selectModel("basic")
            try backend.file.write("external")
            await document.refresh()
            await document.reload()
            #expect(document.edits.isEmpty)
            #expect(!document.hasConflict)
            #expect(document.notice == nil)
            #expect(document.switchMode(to: .file))
            document.fileDraft = "mine"
            try backend.file.write("latest")
            await document.reload()
            #expect(document.fileDraft == "latest")
            #expect(!document.isDirty)
        }
    }

    @Test func externalChangeReloadsWhenClean() async throws {
        try await withDocument { backend, document in
            await document.refresh()
            try backend.file.write("external")
            await document.refresh()
            #expect(await backend.loadCount == 2)
            #expect(document.diskText == "external")
            #expect(document.fileDraft == "external")
            #expect(!document.hasConflict)
        }
    }

    @Test func externalChangeConflictsWhenDirty() async throws {
        try await withDocument { backend, document in
            await document.refresh()
            document.set(.bool(true), at: ["fast"])
            try backend.file.write("external")
            await document.refresh()
            #expect(document.hasConflict)
            #expect(document.diskText == "original")
            #expect(document.edits == [.init(path: ["fast"], value: .bool(true))])
            #expect(await backend.loadCount == 1)
        }
    }

    @Test func unchangedFileSkipsLoad() async throws {
        try await withDocument { backend, document in
            await document.refresh()
            await document.refresh()
            #expect(await backend.loadCount == 1)
            await document.refresh(force: true)
            #expect(await backend.loadCount == 2)
        }
    }

    @Test func refreshDuringSaveIsIgnored() async throws {
        try await withDocument { backend, document in
            await document.refresh()
            document.set(.bool(true), at: ["fast"])
            await backend.blockSave()
            let saving = Task { await document.save() }
            await backend.waitForSave()
            #expect(document.isSaving)
            try backend.file.write("saved externally while awaiting backend")
            await document.refresh()
            #expect(!document.hasConflict)
            #expect(document.edits == [.init(path: ["fast"], value: .bool(true))])
            #expect(await backend.loadCount == 1)
            await backend.releaseSave()
            await saving.value
            #expect(!document.hasConflict)
            #expect(!document.isSaving)
            #expect(!document.isDirty)
            #expect(await backend.loadCount == 2)
        }
    }

    @Test func dangerousEditsOnlyWhenNew() async throws {
        try await withDocument(config: Self.config(values: [permission: .string("bypassPermissions")])) { _, document in
            await document.refresh()
            document.set(.string("bypassPermissions"), at: permission)
            #expect(document.dangerousEdits.isEmpty)
        }
        try await withDocument { _, document in
            await document.refresh()
            document.set(.string("bypassPermissions"), at: permission)
            #expect(document.dangerousEdits == [.init(path: permission, value: .string("bypassPermissions"))])
            document.set(.string("plan"), at: permission)
            #expect(document.dangerousEdits.isEmpty)
        }
    }

    @Test func modelChangeResetsUnsupportedEffort() async throws {
        try await withDocument { _, document in
            await document.refresh()
            #expect(document.currentModel?.id == "full")
            document.selectModel("basic")
            #expect(document.currentModel?.id == "basic")
            #expect(document.edits == [.init(path: ["model"], value: .string("basic")), .init(path: ["effort"], value: nil)])
            #expect(document.value(at: ["effort"]) == nil)
            #expect(document.notice == .effortReset)
            document.selectModel(nil)
            #expect(document.currentModel?.id == "full")
            #expect(document.notice == nil)
        }
    }

    @Test func fixedLevelsSurviveModelChange() async throws {
        var config = Self.config()
        let fixed = EffortSetting(path: ["effort"], modelName: "opus", levels: ["low", "ultra"])
        config.efforts = [fixed]
        try await withDocument(config: config) { _, document in
            await document.refresh()
            document.selectModel("no-efforts")
            #expect(document.value(at: ["effort"]) == .string("ultra"))
            #expect(document.edits == [.init(path: ["model"], value: .string("no-efforts"))])
            #expect(document.levels(for: fixed) == ["low", "ultra"])
            #expect(document.notice == nil)
        }
    }

    @Test func unknownEffortStaysInLevels() async throws {
        try await withDocument(config: Self.config(values: [["effort"]: .string("turbo")])) { _, document in
            await document.refresh()
            #expect(document.levels(for: effort) == ["low", "ultra", "turbo"])
            document.selectModel("no-efforts")
            #expect(document.value(at: ["effort"]) == .string("turbo"))
            #expect(document.levels(for: effort) == ["turbo"])
            #expect(document.edits == [.init(path: ["model"], value: .string("no-efforts"))])
        }
    }

    @Test func fastHiddenWithoutModelTier() async throws {
        try await withDocument { _, document in
            await document.refresh()
            #expect(document.isFastAvailable)
            document.selectModel("basic")
            #expect(!document.isFastAvailable)
            document.selectModel("custom")
            #expect(document.currentModel == nil)
            #expect(!document.isFastAvailable)
        }
        var config = Self.config()
        config.fast = FastSetting(path: ["fast"], onValue: .bool(true), lockedValue: nil, requiresModelTier: false)
        try await withDocument(config: config) { _, document in
            await document.refresh()
            document.selectModel("basic")
            #expect(document.isFastAvailable)
        }
        config.fast = nil
        try await withDocument(config: config) { _, document in
            await document.refresh()
            #expect(!document.isFastAvailable)
        }
    }

    @Test func switchModeRefusesWhenDirty() async throws {
        try await withDocument { _, document in
            await document.refresh()
            document.set(.bool(true), at: ["fast"])
            #expect(!document.switchMode(to: .file))
            #expect(document.mode == .controls)
            document.revert()
            #expect(document.switchMode(to: .file))
            document.fileDraft = "draft"
            #expect(!document.switchMode(to: .controls))
            #expect(document.mode == .file)
        }
    }

    @Test func fileSaveValidatesBeforeWriting() async throws {
        try await withDocument { backend, document in
            await document.refresh()
            #expect(document.switchMode(to: .file))
            document.fileDraft = "invalid"
            await backend.setValidationResult(.failure(.invalidFile("broken")))
            await document.save()
            #expect(await backend.validations == ["invalid"])
            #expect(await backend.writes.isEmpty)
            #expect(document.saveError == .invalidFile("broken"))
            #expect(document.fileDraft == "invalid")
            #expect(document.isDirty)
            let unchanged = try backend.file.read()
            #expect(unchanged == "original")
        }
    }

    @Test func fileSaveWhenUncheckedWritesAndWarns() async throws {
        try await withDocument { backend, document in
            await document.refresh()
            #expect(document.switchMode(to: .file))
            document.fileDraft = "unchecked"
            await backend.setValidationResult(.success(.unchecked))
            await document.save()
            #expect(await backend.validations == ["unchecked"])
            #expect(await backend.writes == ["unchecked"])
            #expect(document.notice == .fileNotChecked)
            #expect(!document.isDirty)
            #expect(await backend.loadCount == 2)
            await backend.setValidationResult(.failure(.invalidFile("broken")))
            document.fileDraft = "invalid"
            await document.save()
            #expect(document.notice == nil)
        }
    }

    private static func config(values: [ConfigPath: ConfigValue] = [:]) -> AgentConfig {
        AgentConfig(
            model: ModelSetting(path: ["model"], options: [
                ModelOption(id: "full", displayName: "Full", isDefault: true, efforts: ["low", "ultra"], fastDescription: "Fast"),
                ModelOption(id: "basic", displayName: "Basic", isDefault: false, efforts: ["low"], fastDescription: nil),
                ModelOption(id: "no-efforts", displayName: "No efforts", isDefault: false, efforts: [], fastDescription: nil),
            ], allowsCustom: true),
            efforts: [EffortSetting(path: ["effort"], modelName: nil, levels: nil)],
            fast: FastSetting(path: ["fast"], onValue: .bool(true), lockedValue: nil, requiresModelTier: true),
            choices: [ConfigChoice(kind: .claudePermission, path: ["permissions", "defaultMode"],
                                   options: [nil, .string("plan"), .string("bypassPermissions")],
                                   dangerous: [.string("bypassPermissions")], unsetAliases: [.string("default"), .string("manual")])],
            plugins: [], pluginsComplete: true,
            values: [["fast"]: .bool(false), ["effort"]: .string("ultra"), ["permissions", "defaultMode"]: .string("plan")]
                .merging(values) { _, new in new }
        )
    }

    private func withDocument(
        content: String? = "original", config: AgentConfig = Self.config(),
        _ body: @MainActor (FakeConfigBackend, ConfigDocument) async throws -> Void
    ) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) }
            catch { Issue.record(error) }
        }
        let file = TextFile(url: directory.appendingPathComponent("config.txt"))
        if let content { try file.write(content) }
        let backend = FakeConfigBackend(file: file, snapshot: ConfigSnapshot(config: config, version: "v1"))
        try await body(backend, ConfigDocument(backend: backend))
    }
}
