import Observation

@Observable @MainActor
public final class AgentsDocument {
    public let source: any AgentSource
    public private(set) var listing: AgentListing?
    public private(set) var loadError: AgentLoadError?
    public private(set) var isLoading = false

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(source: any AgentSource) {
        self.source = source
    }

    public func refresh() async {
        if let loadTask {
            await loadTask.value
            return
        }
        isLoading = listing == nil && loadError == nil
        // The document owns the load, so cancelling a view's waiter cannot cancel it.
        let task = Task { @MainActor in
            defer {
                loadTask = nil
                isLoading = false
            }
            do throws(AgentLoadError) {
                listing = try await source.load()
                loadError = nil
            } catch {
                loadError = error
            }
        }
        loadTask = task
        await task.value
    }
}
