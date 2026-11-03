import Foundation
import Security
import Synchronization

public protocol CredentialSource: Sendable {
    func load() throws -> ClaudeCredential?
}

public enum CredentialSourceError: Error, Equatable {
    case accessDenied(OSStatus)
    case unreadable
}

/// Remembers that the user denied Keychain access this session. The legacy Keychain does not
/// remember a Deny, so without this every refresh would show the dialog again.
public final class KeychainAccessGate: Sendable {
    private let denied = Mutex(false)

    public init() {}

    public var isDenied: Bool { denied.withLock { $0 } }
    public func markDenied() { denied.withLock { $0 = true } }
    public func reset() { denied.withLock { $0 = false } }

    /// OSStatus values that mean "the user (or policy) refused": Deny, auth failure, no UI allowed.
    public static func isDenial(_ status: OSStatus) -> Bool {
        status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed
    }
}

/// Reads Claude Code's credential from the login Keychain. Read-only: `SecItemCopyMatching` only.
public struct KeychainCredentialSource: CredentialSource {
    private let service: String
    private let gate: KeychainAccessGate

    public init(service: String = "Claude Code-credentials", gate: KeychainAccessGate = KeychainAccessGate()) {
        self.service = service
        self.gate = gate
    }

    public func load() throws -> ClaudeCredential? {
        if gate.isDenied { throw CredentialSourceError.accessDenied(errSecUserCanceled) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        if KeychainAccessGate.isDenial(status) { gate.markDenied() }
        guard status == errSecSuccess else { throw CredentialSourceError.accessDenied(status) }
        guard let data = result as? Data, let credential = try? ClaudeCredential.decode(data) else {
            throw CredentialSourceError.unreadable
        }
        return credential
    }
}

/// Reads the credential from a JSON file (e.g. `~/.claude/.credentials.json`).
public struct FileCredentialSource: CredentialSource {
    private let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> ClaudeCredential? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url), let credential = try? ClaudeCredential.decode(data) else {
            throw CredentialSourceError.unreadable
        }
        return credential
    }
}
