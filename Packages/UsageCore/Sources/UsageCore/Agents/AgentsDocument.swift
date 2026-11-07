import Observation

@Observable @MainActor
public final class AgentsDocument {
    public let source: any AgentSource
    public private(set) var listing: AgentListing?
    public private(set) var loadError: AgentLoadError?
    public private(set) var isLoading = false

    private var isRefreshing = false

    public init(source: any AgentSource) {
        self.source = source
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        isLoading = listing == nil && loadError == nil
        defer {
            isRefreshing = false
            isLoading = false
        }
        do {
            listing = try await source.load()
            loadError = nil
        } catch {
            loadError = error
        }
    }
}
