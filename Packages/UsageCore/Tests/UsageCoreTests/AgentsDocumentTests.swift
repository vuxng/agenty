import Testing
@testable import UsageCore

@Suite @MainActor struct AgentsDocumentTests {
    @Test func firstLoadShowsLoadingThenListing() async {
        let listing = AgentListing(folderExists: true, agents: [], usesClaudeAgents: true)
        let source = FakeAgentSource(results: [.success(listing)])
        let document = AgentsDocument(source: source)
        #expect(document.listing == nil)
        #expect(document.loadError == nil)
        #expect(!document.isLoading)
        await source.blockLoad()
        let refresh = Task { await document.refresh() }
        await source.waitForLoad()
        #expect(document.isLoading)
        #expect(document.listing == nil)
        await source.releaseLoad()
        await refresh.value
        #expect(document.listing == listing)
        #expect(document.loadError == nil)
        #expect(!document.isLoading)
    }

    @Test func errorKeepsLastListing() async {
        let first = AgentListing(folderExists: true, agents: [])
        let next = AgentListing(folderExists: false, agents: [])
        let source = FakeAgentSource(results: [.success(first), .failure(.cliNotFound), .success(next)])
        let document = AgentsDocument(source: source)
        await document.refresh()
        await source.blockLoad()
        let refresh = Task { await document.refresh() }
        await source.waitForLoad()
        #expect(!document.isLoading)
        #expect(document.listing == first)
        await source.releaseLoad()
        await refresh.value
        #expect(document.loadError == .cliNotFound)
        #expect(document.listing == first)
        #expect(!document.isLoading)
        await document.refresh()
        #expect(document.loadError == nil)
        #expect(document.listing == next)
        #expect(!document.isLoading)
        #expect(await source.loadCount == 3)
    }

    @Test func overlappingRefreshLoadsOnce() async {
        let listing = AgentListing(folderExists: true, agents: [])
        let source = FakeAgentSource(results: [.success(listing)])
        let document = AgentsDocument(source: source)
        await source.blockLoad()
        let refresh = Task { await document.refresh() }
        await source.waitForLoad()
        await document.refresh()
        #expect(await source.loadCount == 1)
        #expect(document.isLoading)
        await source.releaseLoad()
        await refresh.value
        #expect(document.listing == listing)
        #expect(!document.isLoading)
    }

    @Test func initialErrorRetryDoesNotShowLoading() async {
        let listing = AgentListing(folderExists: false, agents: [])
        let source = FakeAgentSource(results: [.failure(.cliNotFound), .success(listing)])
        let document = AgentsDocument(source: source)
        await document.refresh()
        #expect(document.listing == nil)
        #expect(document.loadError == .cliNotFound)
        #expect(!document.isLoading)
        await source.blockLoad()
        let refresh = Task { await document.refresh() }
        await source.waitForLoad()
        #expect(!document.isLoading)
        #expect(document.loadError == .cliNotFound)
        await source.releaseLoad()
        await refresh.value
        #expect(document.listing == listing)
        #expect(document.loadError == nil)
        #expect(!document.isLoading)
    }
}
