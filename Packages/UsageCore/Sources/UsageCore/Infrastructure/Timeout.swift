import Foundation

public struct TimeoutError: Error, Equatable {
    public init() {}
}

/// Runs `operation`, throwing `TimeoutError` if it does not finish within `timeout`.
public func withTimeout<R: Sendable>(
    _ timeout: Duration,
    _ operation: @escaping @Sendable () async throws -> R
) async throws -> R {
    try await withThrowingTaskGroup(of: R.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw TimeoutError() }
        return first
    }
}
