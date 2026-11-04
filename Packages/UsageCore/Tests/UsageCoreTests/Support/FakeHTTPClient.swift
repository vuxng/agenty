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
    private let routes: [String: Outcome]
    private let recorded = Mutex<[URLRequest]>([])

    init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        outcome = .response(status: status, headers: headers, body: body)
        routes = [:]
    }

    init(error: any Error) {
        outcome = .failure(error)
        routes = [:]
    }

    /// Answers by URL path; any other path gets a 404.
    init(routes: [String: (status: Int, body: Data)]) {
        outcome = .response(status: 404, headers: [:], body: Data())
        self.routes = routes.mapValues { .response(status: $0.status, headers: [:], body: $0.body) }
    }

    var requests: [URLRequest] { recorded.withLock { $0 } }

    func requests(path: String) -> [URLRequest] { requests.filter { $0.url?.path == path } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.withLock { $0.append(request) }
        switch routes[request.url?.path ?? ""] ?? outcome {
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
