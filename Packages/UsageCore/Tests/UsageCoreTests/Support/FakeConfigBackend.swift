import Foundation
@testable import UsageCore

actor FakeConfigBackend: ConfigBackend {
    struct SaveCall: Sendable, Equatable {
        let edits: [ConfigEdit]
        let version: String?
    }

    nonisolated let provider: ProviderID = .codex
    nonisolated let file: TextFile
    private(set) var saveCalls: [SaveCall] = []
    private(set) var writes: [String] = []
    private(set) var validations: [String] = []
    private(set) var loadCount = 0
    private var loadResult: Result<ConfigSnapshot, ConfigError>
    private var saveResult: Result<ConfigSaveResult, ConfigError> = .success(.init(overrideMessage: nil))
    private var validationResult: Result<ConfigValidation, ConfigError> = .success(.valid)
    private var saveIsBlocked = false
    private var saveGate: CheckedContinuation<Void, Never>?
    private var saveStarted: CheckedContinuation<Void, Never>?
    private var validationIsBlocked = false
    private var validationGate: CheckedContinuation<Void, Never>?
    private var validationStarted: CheckedContinuation<Void, Never>?

    init(file: TextFile, snapshot: ConfigSnapshot) {
        self.file = file
        self.loadResult = .success(snapshot)
    }

    func setLoadResult(_ result: Result<ConfigSnapshot, ConfigError>) { loadResult = result }
    func setSaveResult(_ result: Result<ConfigSaveResult, ConfigError>) { saveResult = result }
    func setValidationResult(_ result: Result<ConfigValidation, ConfigError>) { validationResult = result }

    func blockSave() { saveIsBlocked = true }

    func waitForSave() async {
        if saveGate != nil { return }
        await withCheckedContinuation { saveStarted = $0 }
    }

    func releaseSave() {
        saveIsBlocked = false
        saveGate?.resume()
        saveGate = nil
    }

    func blockValidation() { validationIsBlocked = true }

    func waitForValidation() async {
        if validationGate != nil { return }
        await withCheckedContinuation { validationStarted = $0 }
    }

    func releaseValidation() {
        validationIsBlocked = false
        validationGate?.resume()
        validationGate = nil
    }

    func load() async throws(ConfigError) -> ConfigSnapshot {
        loadCount += 1
        return try loadResult.get()
    }

    func save(_ edits: [ConfigEdit], version: String?) async throws(ConfigError) -> ConfigSaveResult {
        saveCalls.append(SaveCall(edits: edits, version: version))
        if saveIsBlocked {
            await withCheckedContinuation {
                saveGate = $0
                saveStarted?.resume()
                saveStarted = nil
            }
        }
        return try saveResult.get()
    }

    func validate(_ text: String) async throws(ConfigError) -> ConfigValidation {
        validations.append(text)
        if validationIsBlocked {
            await withCheckedContinuation {
                validationGate = $0
                validationStarted?.resume()
                validationStarted = nil
            }
        }
        return try validationResult.get()
    }

    func writeFile(_ text: String) async throws(ConfigError) {
        do { try file.write(text) }
        catch { throw .writeFailed(String(describing: error)) }
        writes.append(text)
    }
}
