import Foundation
import Synchronization
@testable import UsageCore

struct StaticCredentialSource: CredentialSource {
    let credential: ClaudeCredential?
    init(_ credential: ClaudeCredential?) { self.credential = credential }
    func load() throws -> ClaudeCredential? { credential }
}

/// Returns whatever credential was last set, so a test can swap tokens between fetches.
final class MutableCredentialSource: CredentialSource, Sendable {
    private let current: Mutex<ClaudeCredential?>
    init(_ credential: ClaudeCredential?) { current = Mutex(credential) }
    func set(_ credential: ClaudeCredential?) { current.withLock { $0 = credential } }
    func load() throws -> ClaudeCredential? { current.withLock { $0 } }
}

/// Never returns on its own: waits until the surrounding task is cancelled, like a slow Keychain read.
struct HangingCredentialSource: CredentialSource {
    func load() async throws -> ClaudeCredential? {
        try await Task.sleep(for: .seconds(3600))
        return nil
    }
}

struct ThrowingCredentialSource: CredentialSource {
    let error: CredentialSourceError
    init(_ error: CredentialSourceError) { self.error = error }
    func load() throws -> ClaudeCredential? { throw error }
}

/// Behaves like `KeychainCredentialSource` against a gate: the first call is "denied" and marks
/// the gate, later calls throw without counting as a Keychain access.
final class GatedCountingSource: CredentialSource, Sendable {
    private let gate: KeychainAccessGate
    private let calls = Mutex(0)

    init(gate: KeychainAccessGate) { self.gate = gate }

    var keychainCalls: Int { calls.withLock { $0 } }

    func load() throws -> ClaudeCredential? {
        if gate.isDenied { throw CredentialSourceError.accessDenied(-128) }
        calls.withLock { $0 += 1 }
        gate.markDenied()
        throw CredentialSourceError.accessDenied(-128)
    }
}
