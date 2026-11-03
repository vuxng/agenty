public enum UsageError: Error, Sendable, Equatable {
    case notLoggedIn
    case tokenExpired
    case cliNotFound
    case network(retryAfter: Duration?)
    case unexpectedFormat(String)
}
