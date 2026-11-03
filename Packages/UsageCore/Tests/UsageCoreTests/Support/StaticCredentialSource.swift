import Foundation
import Synchronization
@testable import UsageCore

struct StaticCredentialSource: CredentialSource {
    let credential: ClaudeCredential?
    init(_ credential: ClaudeCredential?) { self.credential = credential }
    func load() throws -> ClaudeCredential? { credential }
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
