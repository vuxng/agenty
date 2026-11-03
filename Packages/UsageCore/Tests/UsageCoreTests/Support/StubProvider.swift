import Foundation
@testable import UsageCore

/// Scripted provider: results are consumed in order, the last one repeats.
/// An optional gate holds each fetch until the gate yields its first element.
struct StubProvider: UsageProvider {
    let id: ProviderID
    let minimumInterval: Duration
    private let state: State
    private let gate: AsyncStream<Void>?

    actor State {
        private var results: [Result<UsageSnapshot, UsageError>]
        private(set) var fetchCount = 0
        init(results: [Result<UsageSnapshot, UsageError>]) { self.results = results }
        func next() -> Result<UsageSnapshot, UsageError> {
            fetchCount += 1
            return results.count > 1 ? results.removeFirst() : results[0]
        }
    }

    init(
        id: ProviderID,
        minimumInterval: Duration = .zero,
        results: [Result<UsageSnapshot, UsageError>],
        gate: AsyncStream<Void>? = nil
    ) {
        self.id = id
        self.minimumInterval = minimumInterval
        self.state = State(results: results)
        self.gate = gate
    }

    var fetchCount: Int { get async { await state.fetchCount } }

    func fetch() async throws(UsageError) -> UsageSnapshot {
        let result = await state.next()
        if let gate { for await _ in gate { break } }
        return try result.get()
    }

    /// Creates a gate and the continuation that opens it.
    static func makeGate() -> (AsyncStream<Void>, AsyncStream<Void>.Continuation) {
        AsyncStream<Void>.makeStream()
    }
}
