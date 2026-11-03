import Foundation
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
