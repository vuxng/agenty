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
        var overlapStarted = false
        let overlap = Task {
            overlapStarted = true
            await document.refresh()
            #expect(document.listing == listing)
        }
        while !overlapStarted { await Task.yield() }
        #expect(await source.loadCount == 1)
        #expect(document.isLoading)
        await source.releaseLoad()
        await refresh.value
        await overlap.value
        #expect(document.listing == listing)
        #expect(!document.isLoading)
    }

    @Test func cancellingRefreshCallerStillPublishesHeldResult() async {
        let listing = AgentListing(folderExists: true, agents: [], usesClaudeAgents: true)
        let source = FakeAgentSource(results: [.success(listing)])
        let document = AgentsDocument(source: source)
        await source.blockLoad()
        let caller = Task { await document.refresh() }
        await source.waitForLoad()
        caller.cancel()
        #expect(document.loadError == nil)
        #expect(document.isLoading)
        await source.releaseLoad()
        await caller.value
        #expect(document.listing == listing)
        #expect(document.loadError == nil)
        #expect(!document.isLoading)
        #expect(await source.loadCount == 1)
    }

    @Test func refreshAfterCancelledCallerAwaitsHeldResult() async {
        let listing = AgentListing(folderExists: true, agents: [], usesClaudeAgents: true)
        let source = FakeAgentSource(results: [.success(listing)])
        let document = AgentsDocument(source: source)
        await source.blockLoad()
        let caller = Task { await document.refresh() }
        await source.waitForLoad()
        caller.cancel()
        var reentryStarted = false
        var reentryFinished = false
        let reentry = Task {
            reentryStarted = true
            await document.refresh()
            reentryFinished = true
            #expect(document.listing == listing)
            #expect(document.loadError == nil)
            #expect(!document.isLoading)
        }
        while !reentryStarted { await Task.yield() }
        #expect(!reentryFinished)
        #expect(document.loadError == nil)
        await source.releaseLoad()
        await caller.value
        await reentry.value
        #expect(document.listing == listing)
        #expect(document.loadError == nil)
        #expect(await source.loadCount == 1)
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
