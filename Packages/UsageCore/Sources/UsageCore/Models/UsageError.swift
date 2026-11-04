public enum UsageError: Error, Sendable, Equatable {
    case notLoggedIn
    case tokenExpired
    case cliNotFound
    case keychainDenied
    case network(retryAfter: Duration?)
    /// The server answered 429. Unlike `network`, a forced refresh waits this out too.
    case rateLimited(retryAfter: Duration?)
    case unexpectedFormat(String)
}
