import Foundation
import Testing
@testable import UsageCore

@Suite struct ClaudeCredentialTests {
    @Test func decodesClaudeAiOauth() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1793759846673,"subscriptionType":"max","scopes":[]},"mcpOAuth":{}}"#
        let c = try ClaudeCredential.decode(Data(json.utf8))
        #expect(c.accessToken == "tok")
        #expect(c.subscriptionType == "max")
        #expect(c.expiresAt == Date(timeIntervalSince1970: 1_793_759_846.673))
    }
    @Test func throwsWithoutClaudeAiOauth() {
        #expect(throws: (any Error).self) { try ClaudeCredential.decode(Data(#"{"mcpOAuth":{}}"#.utf8)) }
    }
    @Test func throwsWithoutAccessToken() {
        let json = #"{"claudeAiOauth":{"subscriptionType":"max"}}"#
        #expect(throws: (any Error).self) { try ClaudeCredential.decode(Data(json.utf8)) }
    }
    @Test func decodesRateLimitTier() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"tok","subscriptionType":"max","rateLimitTier":"default_claude_max_20x"}}"#
        #expect(try ClaudeCredential.decode(Data(json.utf8)).rateLimitTier == "default_claude_max_20x")
    }
    /// Anthropic renamed Max 20x to Ultra, but the credential still says subscriptionType "max".
    @Test func max20xTierIsUltra() {
        let c = ClaudeCredential(accessToken: "t", expiresAt: nil, subscriptionType: "max", rateLimitTier: "default_claude_max_20x")
        #expect(c.plan == "ultra")
    }
    @Test func otherTiersKeepSubscriptionType() {
        let max5x = ClaudeCredential(accessToken: "t", expiresAt: nil, subscriptionType: "max", rateLimitTier: "default_claude_max_5x")
        #expect(max5x.plan == "max")
        #expect(ClaudeCredential(accessToken: "t", expiresAt: nil, subscriptionType: "pro").plan == "pro")
    }
    @Test func memberwiseInit() {
        let c = ClaudeCredential(accessToken: "fresh", expiresAt: nil, subscriptionType: "max")
        #expect(c.accessToken == "fresh")
    }
}
