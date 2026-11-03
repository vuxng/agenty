import Foundation
import Testing
@testable import UsageCore

@Suite struct ClaudeProviderTests {
    let now = Date(timeIntervalSince1970: 1_793_786_400)
    var fresh: ClaudeCredential { ClaudeCredential(accessToken: "fresh", expiresAt: now + 3600, subscriptionType: "max") }
    var stale: ClaudeCredential { ClaudeCredential(accessToken: "stale", expiresAt: now - 86_400, subscriptionType: "max") }

    func provider(_ sources: [any CredentialSource], _ http: FakeHTTPClient) -> ClaudeProvider {
        let now = now
        return ClaudeProvider(sources: sources, http: http, now: { now })
    }

    func okHTTP() throws -> FakeHTTPClient {
        FakeHTTPClient(status: 200, body: try fixture("claude-oauth-usage"))
    }

    func expect(_ expected: UsageError, _ http: FakeHTTPClient) async {
        let p = provider([StaticCredentialSource(fresh)], http)
        do {
            _ = try await p.fetch()
            Issue.record("expected \(expected)")
        } catch {
            #expect(error == expected)
        }
    }

    @Test func usesFreshestCredential() async throws {
        let http = try okHTTP()
        _ = try await provider([StaticCredentialSource(stale), StaticCredentialSource(fresh)], http).fetch()
        #expect(http.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer fresh")
    }

    @Test func sendsRequiredHeaders() async throws {
        let http = try okHTTP()
        _ = try await provider([StaticCredentialSource(fresh)], http).fetch()
        let r = http.requests[0]
        #expect(r.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(r.httpMethod == "GET")
        #expect(r.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(r.timeoutInterval == 15)
        #expect(r.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
    }

    @Test func mapsFixtureToSnapshot() async throws {
        let s = try await provider([StaticCredentialSource(fresh)], try okHTTP()).fetch()
        #expect(s.provider == .claude)
        #expect(s.plan == "max")
        #expect(s.windows.count == 1)
        #expect(s.fetchedAt == now)
        #expect(s.credits == nil)
    }

    @Test func noCredentialsIsNotLoggedIn() async {
        let http = FakeHTTPClient(status: 200)
        let p = provider([StaticCredentialSource(nil)], http)
        await #expect(throws: UsageError.notLoggedIn) { try await p.fetch() }
        #expect(http.requests.isEmpty)
    }

    @Test func expiredTokenSkipsNetwork() async {
        let http = FakeHTTPClient(status: 200)
        let p = provider([StaticCredentialSource(stale)], http)
        await #expect(throws: UsageError.tokenExpired) { try await p.fetch() }
        #expect(http.requests.isEmpty)
    }

    @Test func nilExpiryIsSentAndNotTreatedAsExpired() async throws {
        let http = try okHTTP()
        let c = ClaudeCredential(accessToken: "noexp", expiresAt: nil, subscriptionType: nil)
        _ = try await provider([StaticCredentialSource(c)], http).fetch()
        #expect(http.requests.count == 1)
    }

    @Test func tieKeepsEarlierSource() async throws {
        let http = try okHTTP()
        let a = ClaudeCredential(accessToken: "first", expiresAt: now + 60, subscriptionType: nil)
        let b = ClaudeCredential(accessToken: "second", expiresAt: now + 60, subscriptionType: nil)
        _ = try await provider([StaticCredentialSource(a), StaticCredentialSource(b)], http).fetch()
        #expect(http.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer first")
    }

    @Test(arguments: [401, 403]) func authFailureIsTokenExpired(status: Int) async {
        await expect(.tokenExpired, FakeHTTPClient(status: status))
    }

    @Test func http429UsesRetryAfter() async {
        await expect(.network(retryAfter: .seconds(120)), FakeHTTPClient(status: 429, headers: ["Retry-After": "120"]))
        await expect(.network(retryAfter: nil), FakeHTTPClient(status: 429))
        await expect(.network(retryAfter: nil), FakeHTTPClient(status: 429, headers: ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"]))
        await expect(.network(retryAfter: nil), FakeHTTPClient(status: 429, headers: ["Retry-After": "-5"]))
    }

    @Test func http503IsNetwork() async {
        await expect(.network(retryAfter: nil), FakeHTTPClient(status: 503))
    }

    @Test func transportErrorIsNetwork() async {
        await expect(.network(retryAfter: nil), FakeHTTPClient(error: URLError(.notConnectedToInternet)))
    }

    @Test func unexpectedStatusIsUnexpectedFormat() async {
        await expect(.unexpectedFormat("HTTP 404"), FakeHTTPClient(status: 404))
    }

    @Test func badBodyPropagatesUnexpectedFormat() async {
        let p = provider([StaticCredentialSource(fresh)], FakeHTTPClient(status: 200, body: Data("nope".utf8)))
        do {
            _ = try await p.fetch()
            Issue.record("expected throw")
        } catch {
            guard case .unexpectedFormat = error else { Issue.record("wrong error \(error)"); return }
        }
    }

    @Test func deniedKeychainFallsBackToFile() async throws {
        let http = try okHTTP()
        let p = provider([ThrowingCredentialSource(.accessDenied(-128)), StaticCredentialSource(fresh)], http)
        _ = try await p.fetch()
        #expect(http.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer fresh")
    }

    @Test func deniedKeychainWithStaleFileIsKeychainDenied() async {
        let http = FakeHTTPClient(status: 200)
        let p = provider([ThrowingCredentialSource(.accessDenied(-128)), StaticCredentialSource(stale)], http)
        await #expect(throws: UsageError.keychainDenied) { try await p.fetch() }
        #expect(http.requests.isEmpty)
    }

    @Test func deniedKeychainWithNoFileIsKeychainDenied() async {
        let p = provider([ThrowingCredentialSource(.accessDenied(-25293)), StaticCredentialSource(nil)], FakeHTTPClient(status: 200))
        await #expect(throws: UsageError.keychainDenied) { try await p.fetch() }
    }

    @Test func nonDenialAccessErrorIsStillNotLoggedIn() async {
        let p = provider([ThrowingCredentialSource(.accessDenied(-25300))], FakeHTTPClient(status: 200))
        await #expect(throws: UsageError.notLoggedIn) { try await p.fetch() }
    }

    @Test func deniedKeychainSkipsKeychainForSession() async {
        let gate = KeychainAccessGate()
        let source = GatedCountingSource(gate: gate)
        let p = provider([source, StaticCredentialSource(stale)], FakeHTTPClient(status: 200))
        await #expect(throws: UsageError.keychainDenied) { try await p.fetch() }
        await #expect(throws: UsageError.keychainDenied) { try await p.fetch() }
        await #expect(throws: UsageError.keychainDenied) { try await p.fetch() }
        #expect(source.keychainCalls == 1)
        #expect(gate.isDenied)
        gate.reset()
        await #expect(throws: UsageError.keychainDenied) { try await p.fetch() }
        #expect(source.keychainCalls == 2)
    }

    @Test func deniedGateShortCircuitsRealKeychainSource() {
        let gate = KeychainAccessGate()
        gate.markDenied()
        // The gate is checked before any Keychain call, so this never touches the Keychain.
        #expect(throws: CredentialSourceError.accessDenied(errSecUserCanceled)) {
            try KeychainCredentialSource(gate: gate).load()
        }
    }

    @Test func gateStatusClassification() {
        #expect(KeychainAccessGate.isDenial(-128))
        #expect(KeychainAccessGate.isDenial(-25293))
        #expect(KeychainAccessGate.isDenial(-25308))
        #expect(!KeychainAccessGate.isDenial(-25300))
    }

    @Test func allSourcesThrowingIsNotLoggedIn() async {
        let p = provider([ThrowingCredentialSource(.accessDenied(-25300)), ThrowingCredentialSource(.unreadable)], FakeHTTPClient(status: 200))
        await #expect(throws: UsageError.notLoggedIn) { try await p.fetch() }
    }

    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("claude-provider-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func fileSourceMissingFileIsNil() throws {
        let d = try tempDir()
        defer { try? FileManager.default.removeItem(at: d) }
        #expect(try FileCredentialSource(url: d.appendingPathComponent("nope.json")).load() == nil)
    }

    @Test func fileSourceReadsCredential() throws {
        let d = try tempDir()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("c.json")
        try Data(#"""
        {"claudeAiOauth":{"accessToken":"tok","expiresAt":1793790000000,"subscriptionType":"pro"}}
        """#.utf8).write(to: url)
        let c = try FileCredentialSource(url: url).load()
        #expect(c == ClaudeCredential(accessToken: "tok", expiresAt: Date(timeIntervalSince1970: 1_793_790_000), subscriptionType: "pro"))
    }

    @Test func fileSourceGarbageIsUnreadable() throws {
        let d = try tempDir()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("c.json")
        try Data("garbage".utf8).write(to: url)
        #expect(throws: CredentialSourceError.unreadable) { try FileCredentialSource(url: url).load() }
    }
}
