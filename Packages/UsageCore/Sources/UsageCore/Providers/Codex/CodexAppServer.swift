import Foundation

enum CodexAppServerError: Error {
    case cliNotFound
}

struct CodexAppServer: Sendable {
    let locator: CLILocator
    let pathOverride: @Sendable () -> String?
    let runner: any ProcessRunner
    let clientVersion: String
    let home: URL
    let timeout: Duration

    static func initialize(_ rpc: JSONRPCClient, version: String) async throws {
        _ = try await rpc.call("initialize", params: .object([
            "clientInfo": .object([
                "name": .string("agenty"),
                "title": .string("Agenty"),
                "version": .string(version),
            ]),
        ]))
        try await rpc.notify("initialized", params: nil)
    }

    func withSession<R: Sendable>(
        environment: [String: String] = [:],
        _ body: @Sendable (JSONRPCClient) async throws -> R
    ) async throws -> R {
        guard let executable = await locator.locate("codex", override: pathOverride()) else {
            throw CodexAppServerError.cliNotFound
        }
        let environment = ["PATH": CodexProvider.searchPath(executable: executable, home: home)]
            .merging(environment) { _, value in value }
        return try await withoutActuallyEscaping(body) { body in
            try await withTimeout(timeout) {
                try await runner.run(executable: executable, arguments: ["app-server"], environment: environment) { channel in
                    let rpc = JSONRPCClient(channel: channel, includesVersionField: false)
                    try await Self.initialize(rpc, version: clientVersion)
                    let result = try await body(rpc)
                    try await channel.finishInput()
                    return result
                }
            }
        }
    }
}
