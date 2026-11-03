import Foundation
import Synchronization
@testable import UsageCore

/// `HTTPClient` that returns a canned response (or throws) and records every request.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    private enum Outcome {
        case response(status: Int, headers: [String: String], body: Data)
        case failure(any Error)
    }

    private let outcome: Outcome
    private let recorded = Mutex<[URLRequest]>([])

    init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        outcome = .response(status: status, headers: headers, body: body)
    }

    init(error: any Error) { outcome = .failure(error) }

    var requests: [URLRequest] { recorded.withLock { $0 } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.withLock { $0.append(request) }
        switch outcome {
        case let .failure(error):
            throw error
        case let .response(status, headers, body):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://invalid.example")!,
                statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (body, response)
        }
    }
}
