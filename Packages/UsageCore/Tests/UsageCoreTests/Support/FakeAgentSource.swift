import Foundation
@testable import UsageCore

actor FakeAgentSource: AgentSource {
    nonisolated let provider: ProviderID
    nonisolated let directory: AgentDirectory
    private var results: [Result<AgentListing, AgentLoadError>]
    private(set) var loadCount = 0
    private var isBlocked = false
    private var gate: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    init(provider: ProviderID = .codex, results: [Result<AgentListing, AgentLoadError>]) {
        self.provider = provider
        self.results = results
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        directory = AgentDirectory(url: home.appendingPathComponent("agents"), home: home,
                                   fileExtension: "md", recursive: false)
    }

    func blockLoad() { isBlocked = true }

    func waitForLoad() async {
        if gate != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func releaseLoad() {
        isBlocked = false
        gate?.resume()
        gate = nil
    }

    func load() async throws(AgentLoadError) -> AgentListing {
        loadCount += 1
        precondition(!results.isEmpty, "No scripted agent result")
        let result = results.removeFirst()
        if isBlocked {
            await withCheckedContinuation {
                gate = $0
                started?.resume()
                started = nil
            }
        }
        return try result.get()
    }
}
