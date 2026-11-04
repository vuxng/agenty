import Foundation

/// The OAuth access token Claude Code stores. The refresh token is deliberately never decoded.
public struct ClaudeCredential: Sendable, Equatable {
    public var accessToken: String
    public var expiresAt: Date?
    public var subscriptionType: String?
    public var rateLimitTier: String?

    public init(accessToken: String, expiresAt: Date?, subscriptionType: String?, rateLimitTier: String? = nil) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }

    /// The plan name to show. Anthropic renamed Max 20x to Ultra, but the credential still reports
    /// subscriptionType "max", so the rate-limit tier tells the two Max-era plans apart.
    public var plan: String? {
        rateLimitTier == "default_claude_max_20x" ? "ultra" : subscriptionType
    }

    public static func decode(_ data: Data) throws -> ClaudeCredential {
        struct Root: Decodable { let claudeAiOauth: OAuth? }
        struct OAuth: Decodable {
            let accessToken: String?
            let expiresAt: Double?   // epoch milliseconds
            let subscriptionType: String?
            let rateLimitTier: String?
        }
        let root = try JSONDecoder().decode(Root.self, from: data)
        guard let oauth = root.claudeAiOauth, let token = oauth.accessToken else {
            throw UsageError.unexpectedFormat("no claudeAiOauth")
        }
        return ClaudeCredential(
            accessToken: token,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            subscriptionType: oauth.subscriptionType,
            rateLimitTier: oauth.rateLimitTier
        )
    }
}
