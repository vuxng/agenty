import Foundation
import Security
import Synchronization

public protocol CredentialSource: Sendable {
    func load() async throws -> ClaudeCredential?
}

public enum CredentialSourceError: Error, Equatable {
    case accessDenied(OSStatus)
    /// The read finished, but the data or exit status made no sense.
    case unreadable
    /// The read never finished (timeout, cancellation, spawn failure, killed by a signal). Transient.
    case unavailable
}

/// Remembers explicit denial or authentication failure for this session to avoid repeated prompts.
/// A locked Keychain is retried on the next refresh rather than remembered as a denial.
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

    /// Excludes -25308 (no UI allowed) so a temporarily locked Keychain can be retried.
    public static func remembersDenial(_ status: OSStatus) -> Bool {
        status == errSecUserCanceled || status == errSecAuthFailed
    }
}

/// Reads Claude Code's credential from the login Keychain by running `/usr/bin/security`. Read-only.
/// Claude Code rewrites the item with `security` on every token refresh, which resets the item's
/// partition list to `apple-tool:` and drops any other app's "Always Allow", so `SecItemCopyMatching`
/// would prompt again every few hours. `security` itself always stays allowed.
public struct KeychainCredentialSource: CredentialSource {
    private let service: String
    private let gate: KeychainAccessGate
    private let runner: any ProcessRunner
    private let executable: URL
    private let timeout: Duration

    public init(
        service: String = "Claude Code-credentials",
        gate: KeychainAccessGate = KeychainAccessGate(),
        runner: any ProcessRunner,
        executable: URL = URL(filePath: "/usr/bin/security"),
        timeout: Duration = .seconds(60)
    ) {
        self.service = service
        self.gate = gate
        self.runner = runner
        self.executable = executable
        self.timeout = timeout
    }

    public func load() async throws -> ClaudeCredential? {
        if gate.isDenied { throw CredentialSourceError.accessDenied(errSecUserCanceled) }
        let output: String
        do {
            output = try await withTimeout(timeout) {
                try await runner.run(
                    executable: executable,
                    arguments: ["find-generic-password", "-s", service, "-w"],
                    environment: [:],
                    requireSuccessfulExit: true
                ) { channel in
                    try await channel.finishInput()
                    var lines: [String] = []
                    while let line = try await channel.receive() { lines.append(line) }
                    return lines.joined(separator: "\n")
                }
            }
        } catch ProcessRunnerError.unsuccessfulExit(let code) {
            guard let code else { throw CredentialSourceError.unavailable }
            let status: OSStatus
            switch code {
            case 44: return nil
            case 128: status = errSecUserCanceled
            case 51: status = errSecAuthFailed
            case 36: status = errSecInteractionNotAllowed
            default: throw CredentialSourceError.unreadable
            }
            if KeychainAccessGate.remembersDenial(status) { gate.markDenied() }
            throw CredentialSourceError.accessDenied(status)
        } catch {
            // Timeout, cancellation or spawn failure: the Keychain may still hold a good credential.
            throw CredentialSourceError.unavailable
        }

        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let credential = try? ClaudeCredential.decode(Data(text.utf8)) { return credential }
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty, bytes.count.isMultiple(of: 2),
              bytes.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw CredentialSourceError.unreadable
        }
        var data = Data()
        for index in stride(from: 0, to: bytes.count, by: 2) {
            guard let byte = UInt8(String(decoding: bytes[index...index + 1], as: UTF8.self), radix: 16) else {
                throw CredentialSourceError.unreadable
            }
            data.append(byte)
        }
        guard let credential = try? ClaudeCredential.decode(data) else { throw CredentialSourceError.unreadable }
        return credential
    }
}

/// Reads the credential from a JSON file (e.g. `~/.claude/.credentials.json`).
public struct FileCredentialSource: CredentialSource {
    private let url: URL

    public init(url: URL) { self.url = url }

    public func load() async throws -> ClaudeCredential? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url), let credential = try? ClaudeCredential.decode(data) else {
            throw CredentialSourceError.unreadable
        }
        return credential
    }
}
