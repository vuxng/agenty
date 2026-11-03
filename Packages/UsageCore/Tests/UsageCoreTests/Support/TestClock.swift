import Foundation
import Synchronization

final class TestClock: Sendable {
    private let date: Mutex<Date>
    init(_ start: Date = Date(timeIntervalSince1970: 1_793_786_400)) { date = Mutex(start) }
    func advance(by d: Duration) {
        let s = Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
        date.withLock { $0 = $0.addingTimeInterval(s) }
    }
    var now: @Sendable () -> Date { { [self] in date.withLock { $0 } } }
}
