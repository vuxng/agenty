@testable import UsageCore

actor RecordingNotifier: UsageNotifying {
    private(set) var delivered: [UsageEvent] = []
    func deliver(_ events: [UsageEvent], snapshot: UsageSnapshot) async {
        delivered.append(contentsOf: events)
    }
}
