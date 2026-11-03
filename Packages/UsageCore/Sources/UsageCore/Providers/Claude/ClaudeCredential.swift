import Foundation

/// The OAuth access token Claude Code stores. The refresh token is deliberately never decoded.
public struct ClaudeCredential: Sendable, Equatable {
    public var accessToken: String
    public var expiresAt: Date?
    public var subscriptionType: String?

    public init(accessToken: String, expiresAt: Date?, subscriptionType: String?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
        self.subscriptionType = subscriptionType
    }

    public static func decode(_ data: Data) throws -> ClaudeCredential {
        struct Root: Decodable { let claudeAiOauth: OAuth? }
        struct OAuth: Decodable {
            let accessToken: String?
            let expiresAt: Double?   // epoch milliseconds
            let subscriptionType: String?
        }
        let root = try JSONDecoder().decode(Root.self, from: data)
        guard let oauth = root.claudeAiOauth, let token = oauth.accessToken else {
            throw UsageError.unexpectedFormat("no claudeAiOauth")
        }
        return ClaudeCredential(
            accessToken: token,
            expiresAt: oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            subscriptionType: oauth.subscriptionType
        )
    }
}
