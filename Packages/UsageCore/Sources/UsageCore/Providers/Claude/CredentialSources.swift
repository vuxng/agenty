import Foundation
import Security

public protocol CredentialSource: Sendable {
    func load() throws -> ClaudeCredential?
}

public enum CredentialSourceError: Error, Equatable {
    case accessDenied(OSStatus)
    case unreadable
}

/// Reads Claude Code's credential from the login Keychain. Read-only: `SecItemCopyMatching` only.
public struct KeychainCredentialSource: CredentialSource {
    private let service: String

    public init(service: String = "Claude Code-credentials") { self.service = service }

    public func load() throws -> ClaudeCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
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
