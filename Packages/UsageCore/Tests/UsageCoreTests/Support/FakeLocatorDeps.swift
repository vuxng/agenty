import Foundation
import Synchronization
@testable import UsageCore

/// Probe whose set of executables can change between calls.
final class MutableProbe: ExecutableProbe, Sendable {
    private let executables = Mutex<Set<String>>([])

    func add(_ path: String) { executables.withLock { _ = $0.insert(path) } }
    func isExecutable(atPath path: String) -> Bool { executables.withLock { $0.contains(path) } }
}

struct FakeProbe: ExecutableProbe {
    let executables: Set<String>
    func isExecutable(atPath path: String) -> Bool { executables.contains(path) }
}

actor FakeShell: LoginShellLookup {
    private let result: String?
    private(set) var calls = 0

    init(result: String?) { self.result = result }

    func commandPath(for name: String) async -> String? {
        calls += 1
        return result
    }
}
